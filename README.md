# bios-info

A general Linux tool to verify hardware and BIOS settings.
Checks CPU, RAM, GPU, storage, PCIe and system info in one quick run.
Useful after a BIOS update to confirm all settings are still correct.

## Status
Work in progress — more features and distro support coming.

## Usage
    bash bin/bios-info.sh
    bash bin/bios-info.sh --check
    bash bin/bios-info.sh --full

## Dependencies
dmidecode, lspci, glxinfo (optional), vulkaninfo (optional)

## Distro support
Arch, Debian/Ubuntu, Fedora — more to follow