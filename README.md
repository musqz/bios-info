# bios-info

A general Linux tool to verify hardware and BIOS settings at a glance.

Useful after a BIOS update to confirm all settings are still correct —
things like XMP/EXPO, Resizable BAR, PCIe speed, SMT, Secure Boot and more
tend to silently reset to defaults after a firmware update.

## Status

Work in progress — features and distro support expanding.
Tested on Arch/Mabox with Intel hardware. AMD and Nvidia GPU support included but less tested.

## Install

```bash
git clone https://github.com/musqz/bios-info.git
cd bios-info
bash install.sh
```

Installs to `~/.local/bin/` by default. Override if needed:

```bash
INSTALL_DIR=~/bin bash install.sh
```

After install, run `bios-info --check` to verify dependencies and sudoers setup.

## Usage

```bash
bios-info              # standard check
bios-info --full       # extended check (C-states, SATA, ECC, boot order, Thunderbolt)
bios-info --save       # save current BIOS state as baseline
bios-info --compare    # compare current state against saved baseline
bios-info --check      # verify dependencies and sudoers setup
bios-info --help       # usage and sudoers setup instructions
```

## BIOS drift detection

The most useful feature — save your ideal BIOS state once, then check after
every firmware update to see exactly what changed:

```bash
# 1. Set up BIOS as desired
bios-info --save

# 2. Update BIOS firmware

# 3. Check what drifted
bios-info --compare

# 4. Fix settings in BIOS, then update baseline
bios-info --save
```

Baseline stored at `~/.config/bios-info/expected.conf` — plain text, editable.

## Autostart / login check

Use the wrapper to run automatically on login and save a timestamped log:

```bash
bios-info-wrapper
```

The log is saved to `~/.local/share/bios-info/` and opened in your default
text viewer after each run. Add `bios-info-wrapper` to your session autostart
to check settings automatically after every boot.

## Dependencies

| Tool          | Required | Purpose                        |
|---------------|----------|--------------------------------|
| dmidecode     | optional | RAM speed, type, slot info     |
| lspci         | optional | PCIe speed, Resizable BAR      |
| glxinfo       | optional | Mesa/OpenGL info               |
| vulkaninfo    | optional | Vulkan version                 |
| efibootmgr    | optional | Boot order (--full)            |

Run `bios-info --check` to see what is installed and what sudoers entries
are needed on your system.

## Sudoers setup

Some checks require passwordless sudo for `dmidecode` and `lspci`.
Run `bios-info --help` for exact setup instructions for your distro.

## Distro support

- Arch / Mabox / Manjaro
- Debian / Ubuntu
- Fedora / RHEL
- openSUSE

## License

Licensed under the [European Union Public License 1.2](https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12) (EUPL-1.2).
Originally based on [whyd-scripts](https://github.com/Naltarunir/whyd-scripts) by Naltarunir.
