# bios-info

A general Linux tool to verify hardware and BIOS settings at a glance.

Useful after a BIOS update to confirm all settings are still correct —
things like XMP/EXPO, Resizable BAR, PCIe speed, SMT, Secure Boot and more
tend to silently reset to defaults after a firmware update.

## Status

Work in progress — features and distro support expanding.

## Usage

```bash
bash bin/bios-info.sh              # standard check
bash bin/bios-info.sh --check      # verify dependencies and sudoers setup
bash bin/bios-info.sh --full       # extended check (C-states, SATA, ECC, boot order, Thunderbolt)
bash bin/bios-info.sh --help       # usage and sudoers setup instructions
```

## Autostart / login check

Use the wrapper to run automatically on login and log the output:

```bash
bash bin/bios-info-wrapper.sh
```

The wrapper saves a timestamped log to `~/.local/share/bios-info/` and opens
it in your default text viewer.

## Dependencies

| Tool          | Required | Purpose                        |
|---------------|----------|--------------------------------|
| dmidecode     | optional | RAM speed, type, slot info     |
| lspci         | optional | PCIe speed, Resizable BAR      |
| glxinfo       | optional | Mesa/OpenGL info               |
| vulkaninfo    | optional | Vulkan version                 |
| efibootmgr    | optional | Boot order (--full)            |

Run `--check` to verify what is installed and what sudoers entries are needed.

## Sudoers setup

Some checks require passwordless sudo for `dmidecode` and `lspci`.
Run `--help` for exact setup instructions for your distro.

## Distro support

- Arch / Mabox / Manjaro
- Debian / Ubuntu
- Fedora / RHEL
- openSUSE

## License

Licensed under the [European Union Public License 1.2](https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12) (EUPL-1.2).
