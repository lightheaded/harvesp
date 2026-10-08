# HarvESP

HarvESP makes a Harvia sauna control panel smart. It is an ESP32-C3 board
with ESPHome firmware. You connect it to Home Assistant.

> **Status: work in progress.** The hardware is not tested on a panel yet.
> The pinout of the panel connector is not verified. Do not use this design
> for a sauna that people use until a later release says that it is safe.

## What it is

- A **passthrough board**. You put it between the Harvia control panel and
  its cable. The panel signals go through the board without a change.
- The board **reads** the status lines of the panel. The firmware shows the
  status in Home Assistant.
- A **fallback "clicker"**. A PC817 optocoupler pushes the panel button,
  as a finger does. The clicker is for the case where we cannot decode the
  panel protocol.

The board does not replace a Harvia part. It does not touch the heater
contactors or the mains wiring.

## Safety

**Read this before you start.**

- A sauna heater uses mains power and makes high temperatures. An incorrect
  connection can cause fire, electric shock, injury or death.
- Only a qualified electrician must open the heater or the control unit, or
  work on mains wiring.
- You use the information, firmware and designs in this repository at your
  own risk. There is no warranty. Read [LICENSE](LICENSE).
- Never leave a heater on without supervision. A remote start does not
  replace the safety devices of the heater.
- Obey the instructions of the manufacturer and your local regulations.

HarvESP is not affiliated with, endorsed by or supported by Harvia. Harvia
and all other trademarks belong to their owners. This project uses the names
only to identify compatible equipment.

## Repository layout

| Path | Contents |
| --- | --- |
| `firmware/harvesp.yaml` | ESPHome firmware for PCB rev A |
| `firmware/harvesp-debug.yaml` | ESPHome firmware for the breadboard prototype |
| `firmware/secrets.yaml.example` | Template for your `secrets.yaml` |
| `docs/findings.md` | What we know about the panel, and the known issues |
| `hardware/pcb/` | PCB design files (EasyEDA exports, Gerbers) |
| `hardware/enclosure/` | Enclosure design files (STEP, STL) |
| `scripts/privacy-guard.sh` | Privacy guard. The git hooks and CI run it |
| `scripts/install-hooks.sh` | Turns on the git hooks in your clone |
| `.githooks/` | Git hooks that run the privacy guard |
| `tests/` | Tests for the privacy guard |
| `PRIVACY.md` | Publishing rules. Read them before you contribute |
| `AGENTS.md` | The same rules, for AI coding agents |

## Build the firmware

You need [ESPHome](https://esphome.io/).

1. Copy the secrets template:

   ```sh
   cp firmware/secrets.yaml.example firmware/secrets.yaml
   ```

2. Put your own values in `firmware/secrets.yaml`. Git ignores this file.
   To make an API encryption key, run `openssl rand -base64 32`.
3. Select the file for your hardware:
   - `firmware/harvesp.yaml` for PCB rev A.
   - `firmware/harvesp-debug.yaml` for the breadboard prototype.
4. Compile and flash the first time over USB:

   ```sh
   esphome run firmware/harvesp.yaml
   ```

   After the first flash, ESPHome can update the device over Wi-Fi.

To use different pins, change the values in the `substitutions:` block.

## Contribute

Findings, measurements, photos of the panel PCB and design improvements are
welcome.

1. Read [PRIVACY.md](PRIVACY.md).
2. Clone the repository and turn on the hooks:

   ```sh
   scripts/install-hooks.sh
   ```

3. Add your private terms to `.git/info/privacy-denylist`.
4. Set your git email to your GitHub noreply address and sign your commits.
5. Open a pull request. CI runs the privacy guard and gitleaks.

To run the tests of the guard:

```sh
tests/test-privacy-guard.sh
```

## Licenses

| Part | License |
| --- | --- |
| Code: firmware, scripts, hooks, tests | MIT. Read [LICENSE](LICENSE) |
| Hardware: all files in `hardware/` | CERN-OHL-P-2.0. Read [LICENSES/](LICENSES/) |
| Documentation: `docs/` and the Markdown files | CC-BY-4.0. Read [LICENSES/](LICENSES/) |
