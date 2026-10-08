# Enclosure

SPDX-License-Identifier: CERN-OHL-P-2.0

This directory will contain the enclosure design files:

- STEP files for CAD
- STL or 3MF files for 3D printing
- Notes about print settings and assembly

## Before you add a file

- Read [PRIVACY.md](../../PRIVACY.md).
- A STEP file header can contain an author name, an organization and the
  original file path. Clear these fields before you export, or edit the
  `FILE_NAME` line of the header.
- Run `scripts/privacy-guard.sh --staged` before you commit.
