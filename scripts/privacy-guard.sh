#!/usr/bin/env bash
# privacy-guard.sh - stop private data before it enters the repository.
#
# Usage:
#   scripts/privacy-guard.sh [--staged]        scan the staged changes (default)
#   scripts/privacy-guard.sh --all             scan every tracked file
#   scripts/privacy-guard.sh --message FILE    scan a commit message
#   scripts/privacy-guard.sh --identity        check the author and committer email
#   scripts/privacy-guard.sh --range LOCAL REMOTE
#                                              scan the commits of a push
#
# Exit codes: 0 = no findings, 1 = findings, 2 = usage or git error.
# Requirements: bash, git and python3 (standard library only).
# Read PRIVACY.md for the rules and for the "privacy-guard: allow" marker.

set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
	echo "privacy-guard: python3 is necessary but not found." >&2
	exit 2
fi

exec python3 -I - "$@" <<'PY'
import math
import os
import re
import struct
import subprocess
import sys

ALLOW_MARKER = "privacy-guard: allow"
NOREPLY_DOMAIN = "users.noreply.github.com"
ALLOWED_EMAIL_DOMAINS = {NOREPLY_DOMAIN, "example.com", "example.org"}
ZERO = re.compile(r"^0+$")

IMAGE_EXT = {".jpg", ".jpeg", ".png", ".webp", ".tif", ".tiff", ".heic", ".heif"}
# CAD and fabrication formats hold long lists of coordinates and embedded
# data. The coordinate and entropy rules give false positives there.
CAD_EXT = {
    ".step", ".stp", ".stl", ".wrl", ".obj", ".3mf", ".gbr", ".gtl", ".gbl",
    ".gto", ".gbo", ".gts", ".gbs", ".gtp", ".gbp", ".gko", ".gm1", ".drl",
    ".xln", ".kicad_pcb", ".kicad_sch", ".kicad_pro", ".kicad_sym", ".kicad_mod",
    ".epro", ".eprj",
}

# Generic phrases that tell where a device is or whose it is. Keep this list
# generic. Put names and places in the local denylist (see PRIVACY.md).
BUILTIN_TERMS = [
    r"\bmy\s+(?:house|home|flat|apartment|cottage|summer\s+house|street)\b",
    r"\bour\s+(?:house|home|flat|apartment|cottage|summer\s+house|street)\b",
    r"\bfriend'?s\s+(?:sauna|house|home|place|cottage)\b",
    r"\b(?:home|street|postal)\s+address\b",
]
BUILTIN_RES = [re.compile(t, re.I) for t in BUILTIN_TERMS]

RE_PRIVATE_KEY = re.compile(r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY(?: BLOCK)?-----")
RE_KNOWN_TOKEN = re.compile(
    r"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|"
    r"AKIA[0-9A-Z]{16}|xox[abprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9_-]{32,}|"
    r"glpat-[A-Za-z0-9_-]{20,})"
)
RE_B64_TOKEN = re.compile(r"[A-Za-z0-9+/_-]{32,}={0,2}")
RE_EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@(?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,}")
RE_PHONE = re.compile(r"(?<![\w+/=])\+[1-9][0-9 ().-]{6,20}[0-9]")
RE_MAC = re.compile(
    r"(?<![0-9A-Fa-f:-])[0-9A-Fa-f]{2}([:-])(?:[0-9A-Fa-f]{2}\1){4}[0-9A-Fa-f]{2}(?![0-9A-Fa-f:-])"
)
RE_IPV4 = re.compile(
    r"(?<![\d.])(?:10(?:\.\d{1,3}){3}|172\.(?:1[6-9]|2\d|3[01])(?:\.\d{1,3}){2}|"
    r"192\.168(?:\.\d{1,3}){2}|100\.(?:6[4-9]|[7-9]\d|1[01]\d|12[0-7])(?:\.\d{1,3}){2})(?![\d.]*\d)"
)
RE_HOST = re.compile(
    r"\b(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+(?:local|lan|home|internal|localdomain|intranet|home\.arpa)\b(?![.-]?\w)",
    re.I,
)
ALLOWED_HOSTS = {"harvesp.local"}
RE_GPS_PAIR = re.compile(
    r"(?<![\d.,])(-?\d{1,2}\.\d{4,})\s*,\s*(-?\d{1,3}\.\d{4,})(?![\d.])(?!\s*,\s*-?\d)"
)
RE_GPS_DMS = re.compile(r"\d{1,3}\s*°\s*\d{1,2}\s*['′]\s*(?:\d{1,2}(?:\.\d+)?\s*[\"″]\s*)?[NSEW]\b")
RE_GPS_KEY = re.compile(r"\b(?:lat|latitude|lon|lng|longitude)[\"']?\s*[:=]\s*-?\d{1,3}\.\d{3,}", re.I)
RE_MAP_LINK = re.compile(r"(?:maps\.google\.|google\.[a-z.]+/maps|goo\.gl/maps|maps\.app\.goo\.gl|openstreetmap\.org/[#?])", re.I)
RE_HOME_PATH = re.compile(r"(?:/Users/|/home/)[A-Za-z0-9._-]+/|[A-Za-z]:\\Users\\[^\\\s]+", re.I)
RE_SERIAL = re.compile(r"\b(?:serial(?:\s*(?:no\.?|number|#))?|s/n)\s*[:#]\s*[A-Z0-9][A-Z0-9-]{4,}", re.I)
RE_YAML_SECRET = re.compile(
    r"^\s*(?:-\s*)?[\"']?([\w.-]*(?:password|passwd|pass|ssid|psk|key|token|secret|apikey))[\"']?\s*:\s*(.*)$",
    re.I,
)
RE_PLACEHOLDER = re.compile(
    r"^(?:change_?me|replace_?me|your_[a-z_]+|<[^>]*>|x{3,}|\*{3,}|placeholder|example|null|~|true|false|yes|no)$",
    re.I,
)
RE_COAUTHOR = re.compile(r"^\s*co-authored-by:", re.I)


class Guard:
    def __init__(self):
        self.findings = []
        self.terms = []
        self.seen_blobs = set()

    # -- helpers -----------------------------------------------------------
    def add(self, where, line, rule, detail):
        item = (where, line, rule, detail)
        if item not in self.findings:
            self.findings.append(item)

    @staticmethod
    def mask(value):
        value = value.strip()
        if len(value) <= 4:
            return value[:1] + "***"
        return value[:4] + "***"

    # -- denylist ----------------------------------------------------------
    def load_denylist(self):
        paths = []
        try:
            p = git_text("rev-parse", "--git-path", "info/privacy-denylist").strip()
            if p:
                paths.append(os.path.abspath(p))
        except GitError:
            pass
        env = os.environ.get("HARVESP_DENYLIST")
        if env:
            if os.path.isfile(env):
                paths.append(env)
            else:
                print(f"privacy-guard: HARVESP_DENYLIST file not found: {env}", file=sys.stderr)
        for path in paths:
            if not os.path.isfile(path):
                continue
            with open(path, encoding="utf-8", errors="replace") as fh:
                for raw in fh:
                    term = raw.split("#", 1)[0].strip().lower()
                    if term and term not in self.terms:
                        self.terms.append(term)

    # -- text rules --------------------------------------------------------
    def scan_line(self, where, n, line, kind, ext="", yaml=False):
        if ALLOW_MARKER in line:
            return
        low = line.lower()
        for i, term in enumerate(self.terms, 1):
            if term in low:
                self.add(where, n, "denylist", f"matches local denylist term #{i}")
        for rx in BUILTIN_RES:
            m = rx.search(line)
            if m:
                self.add(where, n, "setup-detail", f"generic setup phrase '{m.group(0)}'")
        if RE_PRIVATE_KEY.search(line):
            self.add(where, n, "private-key", "private key block")
        for m in RE_KNOWN_TOKEN.finditer(line):
            self.add(where, n, "token", f"known token format {self.mask(m.group(0))}")
        if ext not in CAD_EXT:
            for m in RE_B64_TOKEN.finditer(line):
                tok = m.group(0)
                if high_entropy(tok):
                    self.add(where, n, "entropy", f"high-entropy string {self.mask(tok)}")
        for m in RE_EMAIL.finditer(line):
            email = m.group(0)
            local, domain = email.rsplit("@", 1)
            domain = domain.lower()
            if domain in ALLOWED_EMAIL_DOMAINS:
                continue
            if kind == "message" and RE_COAUTHOR.match(line) and local.lower() == "noreply":
                continue
            self.add(where, n, "email", f"email address {self.mask(email)} (only {NOREPLY_DOMAIN} and example.com/org pass)")
        for m in RE_PHONE.finditer(line):
            digits = re.sub(r"\D", "", m.group(0))
            if 8 <= len(digits) <= 15:
                self.add(where, n, "phone", f"phone number {self.mask(m.group(0))}")
        for m in RE_MAC.finditer(line):
            mac = m.group(0).lower().replace("-", ":")
            if mac not in ("00:00:00:00:00:00", "ff:ff:ff:ff:ff:ff"):
                self.add(where, n, "mac", f"MAC address {self.mask(m.group(0))}")
        for m in RE_IPV4.finditer(line):
            self.add(where, n, "private-ip", f"private IPv4 address {self.mask(m.group(0))}")
        for m in RE_HOST.finditer(line):
            if m.group(0).lower() not in ALLOWED_HOSTS:
                self.add(where, n, "hostname", f"private hostname {self.mask(m.group(0))}")
        if ext not in CAD_EXT:
            for m in RE_GPS_PAIR.finditer(line):
                lat, lon = float(m.group(1)), float(m.group(2))
                if abs(lat) <= 90 and abs(lon) <= 180:
                    self.add(where, n, "gps", "coordinate pair")
            if RE_GPS_DMS.search(line) or RE_GPS_KEY.search(line):
                self.add(where, n, "gps", "coordinates")
        if RE_MAP_LINK.search(line):
            self.add(where, n, "gps", "map link")
        for m in RE_HOME_PATH.finditer(line):
            self.add(where, n, "path", f"path outside the repository {self.mask(m.group(0))}")
        if RE_SERIAL.search(line):
            self.add(where, n, "serial", "device serial number")
        if yaml:
            self.scan_yaml_line(where, n, line)

    def scan_yaml_line(self, where, n, line):
        m = RE_YAML_SECRET.match(line)
        if not m:
            return
        key, value = m.group(1), m.group(2)
        value = re.sub(r"\s+#.*$", "", value).strip()
        if not value or value.startswith("#") or value in ("|", ">", "|-", ">-", "{}", "[]"):
            return
        if value.startswith("!secret") or "${" in value or "{{" in value:
            return
        if value.startswith("!") and not value.startswith("!!"):
            return  # another YAML tag, for example !lambda or !include
        bare = value.strip("\"'")
        if not bare or RE_PLACEHOLDER.match(bare):
            return
        self.add(where, n, "yaml-secret", f"'{key}' has a literal value. Use '!secret {key}' instead")

    def scan_text(self, where, text, kind, ext="", yaml=False, lines=None):
        all_lines = text.splitlines()
        numbered = lines if lines is not None else list(enumerate(all_lines, 1))
        for n, line in numbered:
            self.scan_line(where, n, line, kind, ext, yaml)

    # -- paths -------------------------------------------------------------
    def scan_path(self, path):
        parts = path.split("/")
        base = parts[-1].lower()
        ext = os.path.splitext(base)[1]
        if ".esphome" in parts:
            self.add(path, 0, "forbidden-file", "ESPHome build directory .esphome/")
        if base in ("secrets.yaml", "secrets.yml"):
            self.add(path, 0, "forbidden-file", "secrets file. Commit secrets.yaml.example instead")
        if base == ".env" or base.endswith(".env") or (base.startswith(".env.") and not base.endswith(".example")):
            self.add(path, 0, "forbidden-file", "environment file")
        if ext in (".pem", ".key", ".p12", ".pfx") or base in ("id_rsa", "id_ecdsa", "id_ed25519"):
            self.add(path, 0, "forbidden-file", "key or certificate file")
        self.scan_line(path, 0, path, "path")

    # -- blobs -------------------------------------------------------------
    def scan_blob(self, path, data, added_lines=None):
        """Scan one file. added_lines limits the text scan to the given lines."""
        self.scan_path(path)
        ext = os.path.splitext(path.lower())[1]
        if ext in IMAGE_EXT or looks_like_image(data):
            self.scan_image(path, data, ext)
            self.scan_binary_terms(path, data)
            return
        if b"\0" in data[:8000]:
            self.scan_binary_terms(path, data)
            return
        text = data.decode("utf-8", errors="replace")
        yaml = bool(re.search(r"\.ya?ml(?:\.example)?$", path, re.I))
        self.scan_text(path, text, "file", ext, yaml, added_lines)

    def scan_binary_terms(self, path, data):
        low = data.lower()
        for i, term in enumerate(self.terms, 1):
            if term.encode("utf-8") in low:
                self.add(path, 0, "denylist", f"binary file contains local denylist term #{i}")

    def scan_image(self, path, data, ext):
        fix = "Strip it: exiftool -all= FILE  or  mogrify -strip FILE"
        try:
            kind, found = image_metadata(data)
        except Exception:  # broken file: do not trust it
            self.add(path, 0, "image", "image cannot be parsed. Re-export it without metadata")
            return
        if kind == "heic":
            self.add(path, 0, "heic", "HEIC/HEIF is not accepted. Convert to JPEG or PNG and strip metadata")
            return
        if kind is None:
            if ext in IMAGE_EXT:
                self.add(path, 0, "image", "unknown image format. Convert to JPEG or PNG")
            return
        if found:
            self.add(path, 0, "image-metadata", f"{kind.upper()} metadata: {', '.join(found)}. {fix}")


# -- image parsers ---------------------------------------------------------
def looks_like_image(data):
    return (
        data[:2] == b"\xff\xd8"
        or data[:8] == b"\x89PNG\r\n\x1a\n"
        or (data[:4] == b"RIFF" and data[8:12] == b"WEBP")
        or data[:4] in (b"II*\x00", b"MM\x00*")
        or data[4:8] == b"ftyp"
    )


def tiff_ifd0_tags(buf):
    if buf[:2] == b"II":
        e = "<"
    elif buf[:2] == b"MM":
        e = ">"
    else:
        return set()
    off = struct.unpack(e + "I", buf[4:8])[0]
    count = struct.unpack(e + "H", buf[off:off + 2])[0]
    tags = set()
    for i in range(count):
        p = off + 2 + i * 12
        tags.add(struct.unpack(e + "H", buf[p:p + 2])[0])
    return tags


def image_metadata(d):
    found = []
    if d[:2] == b"\xff\xd8":
        i = 2
        while i + 4 <= len(d):
            if d[i] != 0xFF:
                break
            m = d[i + 1]
            if m == 0xFF:
                i += 1
                continue
            if m in (0xD8, 0x01) or 0xD0 <= m <= 0xD7:
                i += 2
                continue
            if m in (0xD9, 0xDA):
                break
            length = struct.unpack(">H", d[i + 2:i + 4])[0]
            seg = d[i + 4:i + 2 + length]
            if m == 0xE1 and seg.startswith(b"Exif\0"):
                tags = tiff_ifd0_tags(seg[6:])
                found.append("EXIF with GPS" if 0x8825 in tags else "EXIF")
            elif m == 0xE1 and b"ns.adobe.com/xap" in seg[:64]:
                found.append("XMP")
            elif m == 0xE1:
                found.append("APP1")
            elif m == 0xED:
                found.append("IPTC/Photoshop")
            elif m == 0xFE:
                found.append("comment")
            i += 2 + length
        return "jpeg", found
    if d[:8] == b"\x89PNG\r\n\x1a\n":
        i = 8
        while i + 8 <= len(d):
            length = struct.unpack(">I", d[i:i + 4])[0]
            ctype = d[i + 4:i + 8]
            if ctype in (b"tEXt", b"iTXt", b"zTXt", b"eXIf"):
                found.append(ctype.decode())
            if ctype == b"IEND":
                break
            i += 12 + length
        return "png", found
    if d[:4] == b"RIFF" and d[8:12] == b"WEBP":
        i = 12
        while i + 8 <= len(d):
            ctype = d[i:i + 4]
            length = struct.unpack("<I", d[i + 4:i + 8])[0]
            if ctype in (b"EXIF", b"XMP "):
                found.append(ctype.decode().strip())
            i += 8 + length + (length & 1)
        return "webp", found
    if d[:4] in (b"II*\x00", b"MM\x00*"):
        names = {0x8825: "GPS", 0x8769: "EXIF", 0x02BC: "XMP", 0x83BB: "IPTC",
                 0x010F: "Make", 0x0110: "Model", 0x013B: "Artist", 0x8298: "Copyright"}
        tags = tiff_ifd0_tags(d)
        found = [v for k, v in names.items() if k in tags]
        return "tiff", found
    if d[4:8] == b"ftyp" and d[8:12] in (b"heic", b"heix", b"hevc", b"heim", b"heis", b"mif1", b"msf1", b"heif"):
        return "heic", ["HEIC"]
    return None, []


def high_entropy(tok):
    core = tok.rstrip("=")
    if len(core) < 32:
        return False
    if not (re.search(r"[A-Z]", core) and re.search(r"[a-z]", core) and re.search(r"\d", core)):
        return False
    counts = {}
    for c in core:
        counts[c] = counts.get(c, 0) + 1
    ent = -sum(v / len(core) * math.log2(v / len(core)) for v in counts.values())
    return ent >= 4.3


# -- git -------------------------------------------------------------------
class GitError(Exception):
    pass


def git(*args):
    r = subprocess.run(["git", *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if r.returncode != 0:
        raise GitError(f"git {' '.join(args)}: {r.stderr.decode(errors='replace').strip()}")
    return r.stdout


def git_text(*args):
    return git(*args).decode("utf-8", errors="replace")


def parse_raw(out):
    """Parse 'git diff --raw -z' output into (status, oid, path, new_mode)."""
    items = out.split(b"\0")
    res = []
    i = 0
    while i < len(items) and items[i]:
        meta = items[i].decode().lstrip(":").split()
        status = meta[4]
        if status[0] in "RC":
            path = items[i + 2]
            i += 3
        else:
            path = items[i + 1]
            i += 2
        res.append((status[0], meta[3], path.decode("utf-8", errors="replace"), meta[1]))
    return res


def added_lines_of(diff_text):
    lines = []
    n = 0
    for line in diff_text.splitlines():
        if line.startswith("@@"):
            m = re.match(r"@@ -\d+(?:,\d+)? \+(\d+)", line)
            n = int(m.group(1)) if m else 0
        elif line.startswith("+++"):
            continue
        elif line.startswith("+"):
            lines.append((n, line[1:]))
            n += 1
        elif line.startswith(" "):
            n += 1
    return lines


# -- identity --------------------------------------------------------------
def identity_allow_patterns():
    pats = []
    try:
        p = os.path.abspath(git_text("rev-parse", "--git-path", "info/privacy-identity-allow").strip())
    except GitError:
        return pats
    if os.path.isfile(p):
        with open(p, encoding="utf-8", errors="replace") as fh:
            for raw in fh:
                raw = raw.strip()
                if raw and not raw.startswith("#"):
                    try:
                        pats.append(re.compile(raw, re.I))
                    except re.error:
                        print(f"privacy-guard: bad regex in identity allow file: {raw[:20]}", file=sys.stderr)
    return pats


def email_ok(email, pats):
    email = email.strip().strip("<>")
    if email.lower().endswith("@" + NOREPLY_DOMAIN):
        return True
    return any(p.search(email) for p in pats)


# -- modes -----------------------------------------------------------------
def mode_staged(g):
    out = git("diff", "--cached", "--raw", "-z", "--no-abbrev", "--diff-filter=ACMRT")
    for status, oid, path, mode in parse_raw(out):
        if mode == "160000":
            continue
        data = git("cat-file", "blob", oid)
        diff = git_text("diff", "--cached", "-U0", "--no-color", "--no-ext-diff", "--", path)
        if status == "A" or b"\0" in data[:8000]:
            g.scan_blob(path, data)
        else:
            g.scan_blob(path, data, added_lines_of(diff))


def mode_all(g):
    out = git("ls-files", "-s", "-z")
    for entry in out.split(b"\0"):
        if not entry:
            continue
        meta, path = entry.split(b"\t", 1)
        mode, oid, _stage = meta.decode().split()
        if mode == "160000" or oid in g.seen_blobs:
            continue
        g.seen_blobs.add(oid)
        g.scan_blob(path.decode("utf-8", errors="replace"), git("cat-file", "blob", oid))


def scan_message_text(g, text, where):
    lines = []
    for n, line in enumerate(text.splitlines(), 1):
        if re.match(r"^# -+ >8 -+$", line):
            break
        if line.startswith("#"):
            continue
        lines.append((n, line))
    g.scan_text(where, text, "message", lines=lines)


def mode_message(g, path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        scan_message_text(g, fh.read(), "COMMIT_MSG")


def mode_identity(g):
    pats = identity_allow_patterns()
    for var, label in (("GIT_AUTHOR_IDENT", "author"), ("GIT_COMMITTER_IDENT", "committer")):
        ident = git_text("var", var)
        m = re.search(r"<([^>]*)>", ident)
        email = m.group(1) if m else ""
        if not email_ok(email, pats):
            g.add("IDENTITY", 0, "identity",
                  f"{label} email {Guard.mask(email)} is not a GitHub noreply address (*@{NOREPLY_DOMAIN})")


def mode_range(g, local, remote):
    if ZERO.match(local):
        return
    if ZERO.match(remote):
        revs = git_text("rev-list", local, "--not", "--remotes").split()
    else:
        try:
            revs = git_text("rev-list", f"{remote}..{local}").split()
        except GitError:
            revs = git_text("rev-list", local, "--not", "--remotes").split()
    pats = identity_allow_patterns()
    for c in revs:
        short = c[:10]
        info = git_text("log", "-1", "--format=%ae%x00%ce%x00%G?", c).strip().split("\0")
        ae, ce, sig = info[0], info[1], info[2] if len(info) > 2 else "N"
        for label, email in (("author", ae), ("committer", ce)):
            if not email_ok(email, pats):
                g.add(f"commit {short}", 0, "identity",
                      f"{label} email {Guard.mask(email)} is not a GitHub noreply address")
        if sig in ("N", "B"):
            g.add(f"commit {short}", 0, "signature",
                  "commit is not signed" if sig == "N" else "commit has a bad signature")
        scan_message_text(g, git_text("log", "-1", "--format=%B", c), f"commit {short} message")
        out = git("diff-tree", "-r", "-m", "--root", "--raw", "-z", "--no-abbrev",
                  "--no-commit-id", "--diff-filter=ACMRT", c)
        for _status, oid, path, mode in parse_raw(out):
            if mode == "160000" or oid in g.seen_blobs:
                continue
            g.seen_blobs.add(oid)
            g.scan_blob(f"{path}", git("cat-file", "blob", oid))


def main(argv):
    g = Guard()
    mode = argv[0] if argv else "--staged"
    try:
        g.load_denylist()
        if mode == "--staged":
            mode_staged(g)
        elif mode == "--all":
            mode_all(g)
        elif mode == "--message" and len(argv) == 2:
            mode_message(g, argv[1])
        elif mode == "--identity":
            mode_identity(g)
        elif mode == "--range" and len(argv) == 3:
            mode_range(g, argv[1], argv[2])
        else:
            print("usage: privacy-guard.sh [--staged | --all | --identity | --message FILE | --range LOCAL REMOTE]",
                  file=sys.stderr)
            return 2
    except GitError as exc:
        print(f"privacy-guard: {exc}", file=sys.stderr)
        return 2

    if not g.findings:
        return 0
    print(f"privacy-guard: BLOCKED. {len(g.findings)} finding(s):", file=sys.stderr)
    for where, line, rule, detail in g.findings:
        loc = f"{where}:{line}" if line else where
        print(f"  {loc}  [{rule}]  {detail}", file=sys.stderr)
    print("Remove the data and try again. Read PRIVACY.md.", file=sys.stderr)
    print(f"For a false positive, add the marker '{ALLOW_MARKER}' to that line, in a comment.", file=sys.stderr)
    return 1


sys.exit(main(sys.argv[1:]))
PY
