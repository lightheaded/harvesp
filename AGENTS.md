# Instructions for AI agents

This repository is public. Its purpose is to share firmware, findings, PCB
and enclosure designs for HarvESP. Follow these instructions in each task.

## Before you write

1. Read [PRIVACY.md](PRIVACY.md).
2. Read [README.md](README.md) for the layout.

## Privacy rules

- Never write a name of a person, an email address, a phone number or a
  home or street location into a file, a commit message or a pull request.
- Never write where a device is installed, whose it is, or details of a
  building.
- Never write a Wi-Fi network name, a password, a key or a token. In ESPHome
  files, use `!secret`. Put example values only in
  `firmware/secrets.yaml.example`, and use `CHANGE_ME`.
- Never write a MAC address, a serial number, a private IP address, a local
  hostname or a file path from outside this repository.
- Never write details of private infrastructure or of other private projects.
- Never add the private terms of the user to a committed file. Private terms
  go only in `.git/info/privacy-denylist`.
- Never commit an image before its metadata is stripped. Never commit a HEIC
  file.
- Write facts only when they come from a measurement or a source. Mark an
  unmeasured value as "unverified". Do not invent findings.

## Git rules

- Use the git identity of the clone. Do not set or override `user.name`,
  `user.email` or the signing key.
- The commit email must be a GitHub noreply address. Commits must be signed.
- Never use `--no-verify`, and never change `core.hooksPath`.
- Run the guard before each commit:

  ```sh
  scripts/privacy-guard.sh --staged
  tests/test-privacy-guard.sh
  ```

- If the guard blocks a change, remove the data. Add the marker
  `privacy-guard: allow` only when the finding is not private data, and say
  so in your report.

## Writing style

Write prose in ASD-STE100 Simplified Technical English: short sentences,
active voice, one instruction in each sentence.
