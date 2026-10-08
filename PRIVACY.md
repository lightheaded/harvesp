# Privacy and publishing rules

This repository is public. Everything that you commit stays public, also
after you delete it. A force push does not remove a commit from the copies
that other people have. Thus, the only safe control is this: do not commit
private data.

## What you can commit

- Firmware, scripts and tests.
- Measurements, oscilloscope captures and logic analyzer captures of the
  panel signals.
- Photos of the panel PCB, the HarvESP board and the enclosure, after you
  strip the metadata (see below).
- PCB and enclosure design files, after you clear the author fields.
- Generic descriptions: "a Harvia panel", "a 6-pin cable".

## What you must never commit

- Names of people, email addresses (other than the GitHub noreply address),
  phone numbers and postal addresses.
- Locations: GPS coordinates, map links, names of towns or streets, and any
  photo that shows a building, a room, a window view or a car plate.
- Details of an installation: whose sauna it is, where it is, which building.
- Wi-Fi network names and passwords, API keys, OTA passwords, tokens and
  private keys. Use `!secret` in ESPHome files.
- MAC addresses, device serial numbers and barcodes.
- Private IP addresses and local hostnames.
- File paths from your computer and names of your other projects.
- `secrets.yaml`, `.env` files and the `.esphome/` build directory.

## Photos

1. Crop or blur each serial label, barcode and QR code.
2. Crop everything that shows a home or its surroundings.
3. Strip all metadata. Use one of these commands:

   ```sh
   exiftool -all= photo.jpg
   mogrify -strip photo.jpg
   ```

4. Convert HEIC photos to JPEG or PNG. The guard blocks all HEIC files.

The guard blocks JPEG, PNG, WebP and TIFF files that contain EXIF, XMP, IPTC,
comments or PNG text chunks.

## Commit identity

- Set your git email to your GitHub noreply address
  (`ID+USERNAME@users.noreply.github.com`). You find it in the GitHub email
  settings.
- Sign your commits (GPG or SSH).

The pre-commit hook blocks a commit when the author or committer email is not
a noreply address. The pre-push hook blocks a push that contains a commit
with a different email, or a commit with no signature or a bad signature.

To allow a different address in your own clone only, add a regular
expression on one line of `.git/info/privacy-identity-allow`. Git never
commits this file.

## The privacy guard

`scripts/privacy-guard.sh` scans the content before it enters the
repository. It needs only bash, git and python3.

| Hook or job | What it scans |
| --- | --- |
| `pre-commit` | The author and committer email, then the staged changes |
| `commit-msg` | The commit message |
| `pre-push` | Each pushed commit: email, signature, message and changed files |
| CI (`.github/workflows/privacy.yml`) | All tracked files (`--all`), the tests, and gitleaks |

The guard finds:

- literal values of `password:`, `ssid:`, `key:` and similar YAML keys
  (use `!secret`), high-entropy strings, known token formats and private keys
- email addresses outside `users.noreply.github.com`, `example.com` and
  `example.org`
- phone numbers in international format, MAC addresses, private IPv4
  addresses and `.local`, `.lan`, `.home` and `.internal` hostnames
- GPS coordinates and map links
- home directory paths and serial numbers
- a short list of generic phrases that tell where a device is
- the terms of your local denylist
- metadata in images, and forbidden files

Turn on the hooks once in each clone:

```sh
scripts/install-hooks.sh
```

The hooks run your global git hooks after their own checks, if you have
global hooks. Thus your own tools continue to work.

### Your local denylist

The guard cannot know your private words. Put them in
`.git/info/privacy-denylist`, one term on each line. Use names of people,
places, streets, networks, devices and your other projects. The match
ignores case and finds the term inside longer words. A line that starts
with `#` is a comment.

This file is inside `.git`. Git never commits it.

To use a second denylist file, for example one file for all your clones, set
`HARVESP_DENYLIST` to its path.

### False positives

Some findings are not private data. To skip one line, add the marker
`privacy-guard: allow` to that line, in a comment. Use the marker only when
you are sure. A reviewer must agree with each marker.

### If private data is pushed

1. Do not edit the data away in a new commit only. The old commit stays
   readable.
2. Rotate each secret that was in the data.
3. Rewrite the history, force-push, and ask GitHub Support to remove the
   cached views. Check the forks of the repository, because each fork keeps
   its own copy.
