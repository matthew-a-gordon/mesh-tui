# Research: meshtasticd on uConsole CM4 with HackerGadgets AIO v2

Resolves #4 (part of #1). Researched 2026-11-05.

**Nothing here was tested on hardware.** Every claim below comes from the cited pages. None of it was run on a uConsole, a CM4, or an AIO v2.

## Short answer

meshtasticd is a native Linux binary that exposes the Meshtastic API over TCP 4403. On the uConsole it has to be installed, given an SX1262 pin config, and the LoRa rail has to be powered through `aiov2_ctl` before the radio is visible. The official Meshtastic pages fetched did not contain the SX1262 pin config, the SPI enablement steps, or anything about the uConsole or AIO board. For those, the only source is forum posts and the HackerGadgets package. Treat the pin values below as unverified.

## Install

- HackerGadgets ships a Debian package (author Rex, forum thread 17875, 2025-06-08): `sudo apt update && sudo apt --install-recommends install hackergadgets-uconsole-aio-board -y && sudo apt install meshtastic-mui -y`. It targets Debian and supports CM4 and CM5; other distros are "YMMV". [forum 17875](https://forum.clockworkpi.com/t/17875)
- Rex says it was built and tested on clean Debian Bookworm (2025-06-11). [forum 17875](https://forum.clockworkpi.com/t/17875)
- Upstream route: Debian packages come from the OpenSUSE Build Service. For Debian 13 beta, add the `deb http://download.opensuse.org/repositories/network:/Meshtastic:/beta/Debian_13/ /` source and key, then `sudo apt install meshtasticd`. Bookworm uses `Debian_12`. The page has no SPI steps. [meshtastic.org Debian install](https://meshtastic.org/docs/software/linux/installation/debian/)
- Docker alternative: `docker run -p 4403:4403 --restart unless-stopped --name meshtasticd meshtastic/meshtasticd:beta`. [usage page](https://meshtastic.org/docs/software/linux/usage/)

## config.yaml

- Default file `/etc/meshtasticd/config.yaml`. Precedence: `-c` file, then `./config.yaml`, then the default. Presets live in `/etc/meshtasticd/available.d` and are copied into `/etc/meshtasticd/config.d/`. The file is sensitive to spacing. Restart with `sudo systemctl restart meshtasticd`. Logs: `journalctl -u meshtasticd -b`. [usage page](https://meshtastic.org/docs/software/linux/usage/)
- No verbatim AIO v2 yaml was found in the fetched sources. The only evidence is a log from a user on the AIO (Nanderoo, 2025-07-11, thread 17875 page 13): `Activate sx1262 radio on SPI port /dev/spidev1.0`, `SX126xInterface(cs=-1, irq=26, rst=25, busy=24)`, and `SX126X_DIO3_TCXO_VOLTAGE not defined, not using DIO3 as TCXO reference voltage`. That log came from a failing setup ("SX126x init result -2"), so it shows what the config selected, not a known-good config. [forum 17875 p13](https://forum.clockworkpi.com/t/hackergadgets-aio-board-package/17875?page=13)
- Users report the package's config files going missing or not updating (`cp: cannot stat '/tmp/config.yaml'`, 2025-06-10; "config.txt and the meshtasticd yaml files were not updated", 2025-06-08). [forum 17875](https://forum.clockworkpi.com/t/17875)
- Thread 21959 (2026-03-28): vileer says the Meshtastic docs SX1262 warning does not apply to the AIO, "The AIO board uses SPI, and it has a TCXO". The warning text was a screenshot and was not verified against the Meshtastic docs. [forum 21959](https://forum.clockworkpi.com/t/21959)

## Enabling the board with aiov2_ctl

From the [aiov2_ctl README](https://github.com/hackergadgets/aiov2_ctl):
- `aiov2_ctl` shows GPIO state; `aiov2_ctl --status` shows detail.
- `aiov2_ctl LORA on|off` (features: GPS, LORA, SDR, USB). Writes take effect immediately.
- `aiov2_ctl --boot-rail LORA on|off|status` sets the persisted boot state; `--boot-rails-status` lists all. `--install` installs `aiov2-rails-boot.service`, which applies boot states at startup.
- `--gui` is a tray app that must not run as root; `--autostart` creates a desktop autostart entry.

Underlying GPIOs (vileer, thread 20800, 2026-01-16): GPS 27, LoRa 16, SDR 7, internal USB 23, driven with `pinctrl <n> op` then `pinctrl <n> dh|dl`. On CM5 GPIO 7 is high at boot so the SDR powers up. [forum 20800](https://forum.clockworkpi.com/t/20800)

## TCP API on 4403

- meshtasticd serves clients on TCP 4403 by default; `-p` changes it. [usage page](https://meshtastic.org/docs/software/linux/usage/)
- The Python CLI connects with `--host HOST` (default localhost). Documented commands: `--info`, `--nodes`, `--get`/`--set` for preferences, `--sendtext` with `--ch-index`/`--dest`. The page only shows `--host` with `--info`, so whether every option works over TCP is not stated. [Python CLI](https://meshtastic.org/docs/software/python/cli/)
- Limit stated in the docs: Bluetooth is unsupported on meshtasticd. [usage page](https://meshtastic.org/docs/software/linux/usage/)
- What a client cannot do over the API is not documented in the pages read. The yaml is a local file, so hardware pin config appears to be host-side only. This is an inference, not a documented statement.

## Reported failures (including after reboot)

- "SX126x init result -2" / "No sx1262 radio" after a reboot on AIO v2, Debian Trixie; the poster's fix was restoring a GPIO line in config.txt they had removed. Another poster advises restarting meshtasticd every time LoRa is enabled with the script. This comes from a web search summary of the RTL-SDR extension board thread, not a page read directly, so it is second-hand. [thread 14804](https://forum.clockworkpi.com/t/rtl-sdr-extension-board-with-usb-hub-and-rtc/14804)
- Thread 20800 (2026-01-15 to 18): on CM5, Meshtastic Web shows no activity and meshtastic-mui reports "connection failed" while SDR works; on CM4 (Trixie and Bookworm) the HackerGadgets install script errors at the end (a dpkg error suspected); bored99 advises running aiov2_ctl to enable pins first. [forum 20800](https://forum.clockworkpi.com/t/20800)
- Thread 17875 (2025-07-12): clint70 fixed a similar `-2` failure with a fresh OS image and re-running the install scripts.
- Related thread titles seen but not read: "AIO V2 / CM5 / Debian Trixie – Meshtasticd SX1262 initialization failure" and "SX1262 LoRa not detected on SPI bus — CM5 + AIO v2".
- Not found: a documented reboot-persistence procedure. Inference only: if the LoRa rail is off at boot the radio will not initialise, so `--boot-rail LORA on` is the likely remedy, untested.

## Untested / open

- Everything above, on a CM4 specifically. Most reports are CM5 or unspecified.
- The known-good `config.yaml` Lora block for AIO v2 (CS/IRQ/busy/reset, spidev, TCXO) and the config.txt SPI overlay lines.
- Whether `--boot-rail LORA on` makes the radio survive reboot, and whether meshtasticd must be restarted after the rail comes up.
- Thread 20800 was only read through page 1; thread 21959 turned out to be about the SX1262 warning, not install steps.
- Official Meshtastic hardware/board pages (SPI, pinouts) were not retrievable in useful form; read them directly before implementing.
