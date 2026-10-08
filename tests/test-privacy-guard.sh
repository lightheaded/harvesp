#!/usr/bin/env bash
# test-privacy-guard.sh - tests for scripts/privacy-guard.sh and .githooks.
#
# The test makes temporary git repositories. It makes all bad samples at run
# time from parts, so this file itself passes the guard.
# It uses a temporary global git config, so your own config and hooks do not
# apply to the temporary repositories.
set -u

src=$(cd "$(dirname "$0")/.." && pwd -P)
GUARD="$src/scripts/privacy-guard.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

export HOME="$work/home"
export GIT_CONFIG_GLOBAL="$work/gitconfig"
export GIT_CONFIG_NOSYSTEM=1
unset HARVESP_DENYLIST GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
mkdir -p "$HOME"
: >"$GIT_CONFIG_GLOBAL"

NR="users.noreply.github.com"
git config --global user.name "tester"
git config --global user.email "tester@$NR"
git config --global init.defaultBranch main
git config --global core.hooksPath "$work/no-hooks"

# An SSH key for signed test commits. It is made now and deleted at exit.
ssh-keygen -q -t ed25519 -N "" -C "test" -f "$work/signkey" >/dev/null
printf 'tester@%s %s\n' "$NR" "$(cat "$work/signkey.pub")" >"$work/allowed_signers"
git config --global gpg.format ssh
git config --global user.signingkey "$work/signkey"
git config --global gpg.ssh.allowedSignersFile "$work/allowed_signers"
git config --global commit.gpgsign true

passed=0
failed=0
out="$work/out.txt"

ok() { passed=$((passed + 1)); printf 'ok    %s\n' "$1"; }
bad() { failed=$((failed + 1)); printf 'FAIL  %s\n' "$1"; sed 's/^/      /' "$out"; }

new_repo() {
	rm -rf "$work/r"
	git init -q "$work/r"
	cd "$work/r" || exit 2
}

# check NAME EXPECT RULE -- COMMAND...
# EXPECT is pass or fail. RULE is the [rule] tag that must show (fail only).
check() {
	local name=$1 expect=$2 rule=$3
	shift 4
	"$@" >"$out" 2>&1
	local rc=$?
	if [ "$expect" = pass ]; then
		if [ "$rc" -eq 0 ]; then ok "$name"; else bad "$name (expected pass, rc=$rc)"; fi
	else
		if [ "$rc" -eq 1 ] && grep -q "\[$rule\]" "$out"; then
			ok "$name"
		else
			bad "$name (expected [$rule], rc=$rc)"
		fi
	fi
}

# stage_text NAME EXPECT RULE FILE CONTENT
stage_text() {
	new_repo
	mkdir -p "$(dirname "$4")"
	printf '%s\n' "$5" >"$4"
	git add -f -- "$4"
	check "$1" "$2" "$3" -- "$GUARD" --staged
}

# stage_bin NAME EXPECT RULE FILE PYTHON-EXPRESSION-FOR-BYTES
stage_bin() {
	new_repo
	python3 -c "import sys,struct,zlib; sys.stdout.buffer.write($5)" >"$4"
	git add -f -- "$4"
	check "$1" "$2" "$3" -- "$GUARD" --staged
}

echo "== text: good samples"
stage_text "plain text" pass - README.md "HarvESP reads the status of the panel."
stage_text "yaml with !secret" pass - fw.yaml "$(printf 'wifi:\n  ssid: !secret wifi_ssid\n  password: !secret wifi_password\napi:\n  encryption:\n    key: !secret api_encryption_key')"
stage_text "yaml substitution in ssid" pass - fw.yaml "$(printf 'wifi:\n  ap:\n    ssid: "${friendly_name} Fallback"')"
stage_text "secrets example placeholders" pass - firmware/secrets.yaml.example "$(printf 'wifi_ssid: "CHANGE_ME"\nwifi_password: "CHANGE_ME"\napi_encryption_key: "CHANGE_ME"')"
stage_text "noreply and example emails" pass - a.md "Mail tester@$NR or info@example.com"
stage_text "public IP and versions" pass - a.md "DNS 1.1.1.1, version 1.10.2, 3.3 V, +5V rail"
stage_text "hex dump" pass - a.md "00 12 34 56 78 9a bc de f0 11"
stage_text "STEP coordinates" pass - a.md "CARTESIAN_POINT('',(12.345678,-4.567890,0.))"
stage_text "allow marker" pass - a.md "192.$((100 + 68)).1.20 is the example  # privacy-guard: allow"
stage_text "mdns name of the device" pass - a.md "Open harvesp.local in a browser."

echo "== text: bad samples"
pw="hunter""2hunter2"
key=$(head -c 32 /dev/urandom | base64)
stage_text "yaml literal password" fail yaml-secret fw.yaml "$(printf 'wifi:\n  password: "%s"' "$pw")"
stage_text "yaml literal ssid" fail yaml-secret fw.yml "$(printf 'wifi:\n  ssid: %s' "Some""Net")"
stage_text "yaml literal encryption key" fail yaml-secret fw.yaml "$(printf 'api:\n  encryption:\n    key: "%s"' "$key")"
stage_text "high-entropy token" fail entropy notes.txt "token $key"
stage_text "private key block" fail private-key k.txt "-----BEGIN ""OPENSSH PRIVATE KEY-----"
stage_text "email address" fail email a.md "Mail jane.doe""@""mail.ee"
stage_text "email at another domain" fail email a.md "Mail someone""@""example"".net"
stage_text "phone number" fail phone a.md "Call +3""72 5123 4567"
stage_text "MAC address" fail mac a.md "MAC 3C:71:BF"":12:34:56"
stage_text "private IPv4" fail private-ip a.md "Device at 192.$((100 + 68)).1.20"
stage_text "private hostname" fail hostname a.md "Broker at nas"".lan"
stage_text "GPS pair" fail gps a.md "At 59.4""3696, 24.7""5353"
stage_text "GPS map link" fail gps a.md "https://maps.""google.com/?q=1"
stage_text "home path" fail path a.md "See /Us""ers/someone/notes"
stage_text "serial number" fail serial a.md "Serial""#: AB12C""D3456"
stage_text "generic setup phrase" fail setup-detail a.md "It hangs in my ""house"

echo "== denylist"
new_repo
printf '# comment\n%s\n' "zorb""lax" >"$(git rev-parse --git-path info/privacy-denylist)"
printf 'The %s sauna\n' "Zorb""lax" >a.md
git add a.md
check "local denylist in .git/info" fail denylist -- "$GUARD" --staged
git rm -q --cached a.md
printf 'x\n' >"$work/r/zorb""lax-notes.md"
git add -A
check "local denylist in a file name" fail denylist -- "$GUARD" --staged

new_repo
printf '%s\n' "quux""ville" >"$work/extra-deny"
printf 'Built in %s\n' "Quux""ville" >a.md
git add a.md
check "HARVESP_DENYLIST file" fail denylist -- env HARVESP_DENYLIST="$work/extra-deny" "$GUARD" --staged
check "same file without HARVESP_DENYLIST" pass - -- "$GUARD" --staged

echo "== forbidden files"
stage_text "secrets.yaml" fail forbidden-file firmware/secrets.yaml "wifi_ssid: !secret x"
stage_text ".env file" fail forbidden-file .env "A=1"
stage_text ".esphome directory" fail forbidden-file firmware/.esphome/build.txt "x"

echo "== images"
JFIF='b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00\xff\xd9"'
EXIF_GPS='b"\xff\xd8" + b"\xff\xe1" + struct.pack(">H", 2+6+8+2+12+4) + b"Exif\x00\x00" + b"II*\x00\x08\x00\x00\x00" + struct.pack("<H",1) + struct.pack("<HHII",0x8825,4,1,0) + b"\x00"*4 + b"\xff\xd9"'
png_chunk='lambda t,d: struct.pack(">I",len(d))+t+d+struct.pack(">I",zlib.crc32(t+d))'
PNG_OK="(lambda c: b\"\\x89PNG\\r\\n\\x1a\\n\"+c(b\"IHDR\",struct.pack(\">IIBBBBB\",1,1,8,0,0,0,0))+c(b\"IDAT\",zlib.compress(b\"\\x00\\x00\"))+c(b\"IEND\",b\"\"))($png_chunk)"
PNG_TEXT="(lambda c: b\"\\x89PNG\\r\\n\\x1a\\n\"+c(b\"IHDR\",struct.pack(\">IIBBBBB\",1,1,8,0,0,0,0))+c(b\"tEXt\",b\"Comment\\x00hi\")+c(b\"IDAT\",zlib.compress(b\"\\x00\\x00\"))+c(b\"IEND\",b\"\"))($png_chunk)"
WEBP_EXIF='(lambda body: b"RIFF"+struct.pack("<I",4+len(body))+b"WEBP"+body)(b"EXIF"+struct.pack("<I",4)+b"II*\x00")'
HEIC='struct.pack(">I",24)+b"ftypheic"+b"\x00"*12'
stage_bin "clean JPEG" pass - photo.jpg "$JFIF"
stage_bin "JPEG with EXIF GPS" fail image-metadata photo.jpg "$EXIF_GPS"
stage_bin "clean PNG" pass - pic.png "$PNG_OK"
stage_bin "PNG with tEXt chunk" fail image-metadata pic.png "$PNG_TEXT"
stage_bin "WebP with EXIF chunk" fail image-metadata pic.webp "$WEBP_EXIF"
stage_bin "HEIC file" fail heic pic.heic "$HEIC"
stage_bin "JPEG data under a .bin name" fail image-metadata blob.bin "$EXIF_GPS"
if grep -q "GPS" "$out"; then ok "EXIF GPS named in the message"; else bad "EXIF GPS named in the message"; fi

echo "== commit message"
printf 'Add firmware\n\nCo-Authored-By: Claude <noreply%santhropic.com>\n# comment jane%smail.ee\n' "@" "@" >"$work/msg-ok"
check "message with co-author trailer" pass - -- "$GUARD" --message "$work/msg-ok"
printf 'Fix it for jane.doe%smail.ee\n' "@" >"$work/msg-bad"
check "message with email" fail email -- "$GUARD" --message "$work/msg-bad"
printf 'Test at 10.%s.0.7\n' "1" >"$work/msg-ip"
check "message with private IP" fail private-ip -- "$GUARD" --message "$work/msg-ip"

echo "== identity"
new_repo
check "noreply identity" pass - -- "$GUARD" --identity
check "author with other domain" fail identity -- env GIT_AUTHOR_EMAIL="dev@corp""mail.test" "$GUARD" --identity
check "committer with other domain" fail identity -- env GIT_COMMITTER_EMAIL="dev@corp""mail.test" "$GUARD" --identity
printf '# allowed\n^dev@corp''mail\\.test$\n' >"$(git rev-parse --git-path info/privacy-identity-allow)"
check "identity allow file" pass - -- env GIT_AUTHOR_EMAIL="dev@corp""mail.test" "$GUARD" --identity

echo "== --all and --range"
new_repo
printf 'clean\n' >a.md
git add a.md && git commit -q -m "clean"
check "--all on a clean tree" pass - -- "$GUARD" --all
c1=$(git rev-parse HEAD)
check "--range of signed noreply commits" pass - -- "$GUARD" --range "$c1" 0000000000000000000000000000000000000000
printf 'Host at nas%s\n' ".lan" >b.md
git add b.md && git commit -q -m "add b"
check "--all finds a committed problem" fail hostname -- "$GUARD" --all
git rm -q b.md && git commit -q -m "remove b"
check "--all after the removal" pass - -- "$GUARD" --all
check "--range finds it in history" fail hostname -- "$GUARD" --range "$(git rev-parse HEAD)" 0000000000000000000000000000000000000000
check "--range from the clean base" fail hostname -- "$GUARD" --range "$(git rev-parse HEAD)" "$c1"
new_repo
printf 'x\n' >a.md && git add a.md
git -c commit.gpgsign=false commit -q -m "unsigned"
check "--range finds an unsigned commit" fail signature -- "$GUARD" --range "$(git rev-parse HEAD)" 0000000000000000000000000000000000000000
new_repo
printf 'x\n' >a.md && git add a.md
GIT_AUTHOR_EMAIL="dev@corp""mail.test" git commit -q -m "other author"
check "--range finds a non-noreply author" fail identity -- "$GUARD" --range "$(git rev-parse HEAD)" 0000000000000000000000000000000000000000

echo "== hooks and chaining"
new_repo
mkdir -p scripts
cp -R "$src/.githooks" .
cp "$src/scripts/privacy-guard.sh" "$src/scripts/install-hooks.sh" scripts/
bash scripts/install-hooks.sh >/dev/null
[ -f "$(git rev-parse --git-path info/privacy-denylist)" ] && ok "install-hooks makes the denylist" || bad "install-hooks makes the denylist"
[ "$(git config core.hooksPath)" = ".githooks" ] && ok "install-hooks sets core.hooksPath" || bad "install-hooks sets core.hooksPath"

fake="$HOME/global-hooks"
mkdir -p "$fake"
for h in pre-commit commit-msg pre-push post-commit; do
	printf '#!/bin/sh\necho "$0 $*" >>"%s/calls"\n[ "${0##*/}" = pre-push ] && cat >"%s/stdin"\nexit 0\n' "$work" "$work" >"$fake/$h"
	chmod +x "$fake/$h"
done
git config --global core.hooksPath "~/global-hooks"

git add -A
check "commit runs the repo hooks" pass - -- git commit -q -m "Add hooks"
for h in pre-commit commit-msg post-commit; do
	if grep -q "/$h" "$work/calls" 2>/dev/null; then ok "global $h ran through the chain"; else bad "global $h ran through the chain"; fi
done
: >"$work/calls"
printf 'Host at nas%s\n' ".lan" >c.md
git add c.md
check "blocked commit" fail hostname -- git commit -q -m "bad"
if [ -s "$work/calls" ]; then bad "global hook skipped after a block"; else ok "global hook skipped after a block"; fi
git reset -q c.md && rm c.md

head=$(git rev-parse HEAD)
line="refs/heads/main $head refs/heads/main 0000000000000000000000000000000000000000"
printf '%s\n' "$line" >"$work/push-in"
check "pre-push passes" pass - -- sh -c '.githooks/pre-push origin https://example.com/x.git <"$1"' _ "$work/push-in"
if grep -q "/pre-push origin https://example.com/x.git" "$work/calls" && cmp -s "$work/push-in" "$work/stdin"; then
	ok "global pre-push got the same args and stdin"
else
	bad "global pre-push got the same args and stdin"
fi

git config --global core.hooksPath "$work/r/.githooks"
: >"$work/calls"
printf 'y\n' >d.md && git add d.md
check "no loop when the global path is .githooks" pass - -- git commit -q -m "loop test"

echo
echo "passed: $passed  failed: $failed"
[ "$failed" -eq 0 ]
