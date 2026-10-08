# Findings

This file collects what we know about the Harvia control panel and its
cable. Each statement must come from a measurement or from a public source.
Write "unverified" next to each value that nobody has measured.

> **TODO:** The findings are not written yet. Each section below stays empty
> until somebody adds measured data.

## Panel connector

TODO: connector type, number of pins, function of each pin.

Known so far: the passthrough uses a 6-pin connector. Pins 3 to 6 are the
four panel signal lines. The PCB uses pin 1 as +5 V and pin 2 as GND. This
is **unverified**.

## Signal levels

TODO: idle level, active level, rise and fall times, for each line.

## Power budget

TODO: voltage of the panel supply, current that the panel supply can give,
current of the board at Wi-Fi transmit peaks.

## Protocol notes

TODO: line roles, timing, frame format, captures.

## Rev A known issues

PCB rev A is not ordered yet. The design has these known issues:

1. **Unverified pinout.** Nobody has measured the 6-pin pinout and the
   supply voltage. Do not connect rev A to a panel before you measure them.
2. **GPIO21 boot output.** GPIO21 is UART0 TX. The ESP32-C3 ROM bootloader
   prints on it at boot. GPIO21 connects through the TXS0104E to a panel line
   (J4). This output gets to the panel bus at each boot.
3. **The TXS0104E is not correct for unknown bus levels.** Each line of the
   TXS0104E has an internal 10 kΩ pull-up. The pull-ups load the panel lines.
   The level shifter also needs known levels on both sides.
4. **Inrush current.** The 1000 µF capacitor on the panel supply rail causes
   a high inrush current when you connect the board.
5. **USB VBUS back-feed.** The 5 V pin of the ESP32-C3 Supermini module
   connects to USB VBUS. When USB is connected, USB power can flow into the
   panel supply rail.
6. **C1 height.** Capacitor C1 is too tall. It hits the module above it.
