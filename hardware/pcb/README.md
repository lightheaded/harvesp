# PCB

SPDX-License-Identifier: CERN-OHL-P-2.0

This directory will contain the PCB design files:

- EasyEDA exports (project and schematic)
- Gerber and drill files for fabrication
- Bill of materials and pick-and-place files
- A PDF of the schematic

Current revision: **rev A**, not ordered yet. Read the known issues in
[docs/findings.md](../../docs/findings.md#rev-a-known-issues).

## Before you add a file

- Read [PRIVACY.md](../../PRIVACY.md).
- Remove the author, company and file path fields from the export.
  EasyEDA, KiCad and STEP exporters can write them into the file header.
- Run `scripts/privacy-guard.sh --staged` before you commit.
