#!/usr/bin/env bash
# -----------------------------------------------------------------------
# Copyright (c) 2026 Naltarunir (https://github.com/Naltarunir)
# Copyright (c) 2026 musqz (https://github.com/musqz)
#
# This software is licensed under the European Union Public License 1.2
# (EUPL-1.2) or later.
#
# The full text of the license can be found at:
# https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
# -----------------------------------------------------------------------
# Please refer to the README.md before raising an issue on GitHub.
#
# NOTE: 'set -e' and 'pipefail' are intentionally omitted.
# Visit https://mywiki.wooledge.org/BashFAQ/105 for details.
#
# Each function handles its own errors verbosely rather than aborting silently.
#
# bios-info — verify hardware/BIOS settings after a BIOS update
#
# One-time sudoers setup (replace 'youruser' with your actual username):
#   sudo visudo -f /etc/sudoers.d/system-status
#   youruser ALL=(ALL) NOPASSWD: /usr/bin/dmidecode -t memory   ← Arch/Mabox
#   youruser ALL=(ALL) NOPASSWD: /usr/sbin/dmidecode -t memory  ← Debian/Ubuntu
#   youruser ALL=(ALL) NOPASSWD: /usr/bin/lspci -s * -vv
#   sudo chmod 0440 /etc/sudoers.d/system-status

# Note: run directly (bash bios-info.sh), do not source it.
# If sourced anyway, nounset state is saved and restored at the end.
[[ $- == *u* ]] && _SS_U_WAS_SET=1 || _SS_U_WAS_SET=0
set -u

# ────────────────────────────────────────────────────────────────
# COLOURS — disabled automatically when not a TTY, TERM=dumb,
#           or NO_COLOR is set (https://no-color.dev)
# Only used for signaling: GREEN=ok, YELLOW=warn, RED=fail
# ────────────────────────────────────────────────────────────────
if [[ -t 1 && "${TERM:-}" != "dumb" && -z "${NO_COLOR:-}" ]]; then
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    GREEN='' YELLOW='' RED='' BOLD='' RESET=''
fi

# ────────────────────────────────────────────────────────────────
# DISTRO DETECTION — for package install hints
# ────────────────────────────────────────────────────────────────
_PKG_INSTALL="your package manager"
if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    case "${ID_LIKE:-${ID:-}}" in
        *arch*)            _PKG_INSTALL="pacman -S" ;;
        *debian*|*ubuntu*) _PKG_INSTALL="apt install" ;;
        *fedora*|*rhel*)   _PKG_INSTALL="dnf install" ;;
        *opensuse*)        _PKG_INSTALL="zypper install" ;;
    esac
fi

# ────────────────────────────────────────────────────────────────
# HELPERS
# ────────────────────────────────────────────────────────────────
ok()   { echo -e "${GREEN}│ ✓ ${*}${RESET}"; }
warn() { echo -e "${YELLOW}│ ⚠ ${*}${RESET}"; }
fail() { echo -e "${RED}│ ✗ ${*}${RESET}"; }
info() { echo    "│ ${*}"; }
sect() { echo -e "${BOLD}${*}${RESET}"; }

VERDICTS=()

verdict_ok()   { VERDICTS+=("ok:${*}"); }
verdict_warn() { VERDICTS+=("warn:${*}"); }
verdict_fail() { VERDICTS+=("fail:${*}"); }

flush_verdicts() {
    if [[ ${#VERDICTS[@]} -gt 0 ]]; then
        echo "│ ──────────────────────────────────────────────────────────────"
        for v in "${VERDICTS[@]}"; do
            local type="${v%%:*}"
            local msg="${v#*:}"
            case "$type" in
                ok)   echo -e "${GREEN}│ ✓ ${msg}${RESET}" ;;
                warn) echo -e "${YELLOW}│ ⚠ ${msg}${RESET}" ;;
                fail) echo -e "${RED}│ ✗ ${msg}${RESET}" ;;
            esac
        done
        VERDICTS=()
    fi
}

# ────────────────────────────────────────────────────────────────
# HELP
# ────────────────────────────────────────────────────────────────
show_help() {
    cat <<'EOF'
Usage: bios-info [--help|--check|--full]

Checks BIOS/hardware settings after a BIOS update.
No arguments needed for normal use — just run it.

Options:
  --help    Show this message
  --check   Verify setup requirements without running the full check
  --full    Extended check — adds C-states, power limits (PL1/PL2),
            Above 4G decoding, SATA mode, ECC, boot order, Thunderbolt

One-time setup (required for RAM speed, RAM type/slots, and PCIe/BAR info):

  1. Find your dmidecode path:
       which dmidecode
       → /usr/bin/dmidecode   (Arch/Mabox)
       → /usr/sbin/dmidecode  (Debian/Ubuntu)

  2. Create sudoers entry:
       sudo visudo -f /etc/sudoers.d/system-status

     Add these lines (replace 'youruser' with your actual username):
       youruser ALL=(ALL) NOPASSWD: /usr/bin/dmidecode -t memory
       youruser ALL=(ALL) NOPASSWD: /usr/bin/lspci -s * -vv

  3. Lock the file:
       sudo chmod 0440 /etc/sudoers.d/system-status

Without sudoers:
  - RAM speed, type, and slot info will show as unavailable
  - Resizable BAR and PCIe info will be skipped (discrete GPU only)
  - NVMe PCIe link speed will be skipped
  - Above 4G decoding check will be limited (--full)
EOF
}

# ────────────────────────────────────────────────────────────────
# CHECK
# ────────────────────────────────────────────────────────────────
show_check() {
    echo ""
    sect "┌─ SETUP CHECK ─────────────────────────────────────────────────┘"

    local dmidecode lspci first_pci sudoers_file perms

    dmidecode=$(command -v dmidecode 2>/dev/null)
    if [[ -n "$dmidecode" ]]; then
        ok "dmidecode found: $dmidecode"
        if sudo -n "$dmidecode" -t memory >/dev/null 2>&1; then
            ok "sudoers: dmidecode entry OK"
        else
            fail "sudoers: dmidecode entry MISSING or WRONG PATH"
            info "  Add to /etc/sudoers.d/system-status (replace youruser with your username):"
            info "  youruser ALL=(ALL) NOPASSWD: $dmidecode -t memory"
        fi
    else
        fail "dmidecode: not installed ($_PKG_INSTALL dmidecode)"
    fi

    lspci=$(command -v lspci 2>/dev/null)
    if [[ -n "$lspci" ]]; then
        ok "lspci found: $lspci"
        first_pci=$(lspci | awk '{print $1; exit}')
        if sudo -n "$lspci" -s "$first_pci" -vv >/dev/null 2>&1; then
            ok "sudoers: lspci entry OK"
        else
            fail "sudoers: lspci entry MISSING or WRONG PATH"
            info "  Add to /etc/sudoers.d/system-status (replace youruser with your username):"
            info "  youruser ALL=(ALL) NOPASSWD: $lspci -s * -vv"
        fi
    else
        fail "lspci: not installed ($_PKG_INSTALL pciutils)"
    fi

    if command -v glxinfo >/dev/null 2>&1; then
        ok "glxinfo found (Mesa info available)"
    else
        warn "glxinfo: not installed — Mesa info unavailable"
        info "  Install: $_PKG_INSTALL mesa-utils"
    fi

    if command -v vulkaninfo >/dev/null 2>&1; then
        ok "vulkaninfo found (Vulkan info available)"
    else
        warn "vulkaninfo: not installed — Vulkan info unavailable"
        info "  Install: $_PKG_INSTALL vulkan-tools"
    fi

    if command -v efibootmgr >/dev/null 2>&1; then
        ok "efibootmgr found (boot order available in --full)"
    else
        warn "efibootmgr: not installed — boot order unavailable in --full"
        info "  Install: $_PKG_INSTALL efibootmgr"
    fi

    if ! sudo -n "${dmidecode:-dmidecode}" -t memory >/dev/null 2>&1 || \
       ! sudo -n "${lspci:-lspci}" -s "${first_pci:-00:00.0}" -vv >/dev/null 2>&1; then
        sudoers_file="/etc/sudoers.d/system-status"
        if [[ -f "$sudoers_file" ]]; then
            perms=$(stat -c "%a" "$sudoers_file")
            if [[ "$perms" == "440" ]]; then
                ok "$sudoers_file permissions: $perms (correct)"
            else
                warn "$sudoers_file permissions: $perms (should be 440)"
                info "  Fix: sudo chmod 0440 $sudoers_file"
            fi
        else
            warn "No sudoers entry found — see --help for setup instructions"
        fi
    fi

    sect "└───────────────────────────────────────────────────────────────┐"
    echo ""
}

# ────────────────────────────────────────────────────────────────
# CPU
# ────────────────────────────────────────────────────────────────
check_cpu() {
    sect "┌─ CPU ─────────────────────────────────────────────────────────┘"
    VERDICTS=()

    local cpu_model cpu_mhz cur_freq max_freq
    local microcode ucode_pkg ucode_date ucode_name
    local cpu_vendor iommu_groups
    local logical_cores threads_per_core physical_cores

    cpu_model=$(awk -F: '/model name/ {print $2; exit}' /proc/cpuinfo | xargs)
    info "Model: $cpu_model"

    if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]]; then
        cur_freq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null)
        max_freq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null)
        [[ -n "$cur_freq" && -n "$max_freq" ]] && \
            info "Speed: $((cur_freq/1000)) MHz (max: $((max_freq/1000)) MHz)"
    else
        cpu_mhz=$(awk -F: '/cpu MHz/ {print $2; exit}' /proc/cpuinfo | xargs)
        info "Speed: ${cpu_mhz:-Unknown} MHz"
    fi

    microcode=$(awk '/microcode/ {print $3; exit}' /proc/cpuinfo 2>/dev/null)
    ucode_pkg=$(pacman -Q intel-ucode 2>/dev/null || pacman -Q amd-ucode 2>/dev/null)
    ucode_date=$(echo "$ucode_pkg" | grep -oE '[0-9]{8}')
    ucode_name=$(echo "$ucode_pkg" | awk '{print $1}')
    if [[ -n "$ucode_date" ]]; then
        info "Microcode: ${microcode:-Unknown} ($ucode_name $ucode_date)"
    else
        info "Microcode: ${microcode:-Unknown}"
    fi

    cpu_vendor=$(awk -F: '/vendor_id/ {print $2; exit}' /proc/cpuinfo | xargs)

    iommu_groups=$(ls /sys/class/iommu/ 2>/dev/null | wc -l)
    if [[ "$iommu_groups" -eq 0 ]] && \
       ! grep -qiE "intel_iommu|amd_iommu|iommu" /proc/cmdline 2>/dev/null; then
        info "IOMMU: Not active (only needed for VM/GPU passthrough)"
    fi

    logical_cores=$(grep -c "^processor" /proc/cpuinfo)
    threads_per_core=$(lscpu 2>/dev/null | awk '/Thread\(s\) per core/ {print $NF}')
    threads_per_core=${threads_per_core:-1}
    physical_cores=$((logical_cores / threads_per_core))

    # --full: power limits
    if [[ "$FULL_MODE" == true ]]; then
        local rapl_path="/sys/class/powercap/intel-rapl/intel-rapl:0"
        if [[ -d "$rapl_path" ]]; then
            local pl1_uw pl2_uw
            pl1_uw=$(cat "$rapl_path/constraint_0_power_limit_uw" 2>/dev/null)
            pl2_uw=$(cat "$rapl_path/constraint_1_power_limit_uw" 2>/dev/null)
            if [[ "$pl1_uw" =~ ^[0-9]+$ && "$pl2_uw" =~ ^[0-9]+$ ]]; then
                info "Power Limits: PL1 $((pl1_uw/1000000))W / PL2 $((pl2_uw/1000000))W"
            fi
        else
            info "Power Limits: Intel RAPL not available"
        fi
    fi

    # Verdicts
    if command -v checkupdates >/dev/null 2>&1; then
        if checkupdates 2>/dev/null | grep -qE "intel-ucode|amd-ucode"; then
            verdict_warn "Microcode package update available — update your system"
        else
            verdict_ok "Microcode package up to date"
        fi
    fi

    if grep -q vmx /proc/cpuinfo; then
        verdict_ok "Intel VT-x: ENABLED"
    elif grep -q svm /proc/cpuinfo; then
        verdict_ok "AMD-V (SVM): ENABLED"
    else
        [[ "$cpu_vendor" == *"Intel"* ]] \
            && verdict_fail "Intel VT-x: NOT DETECTED (check BIOS settings)" \
            || verdict_fail "AMD-V (SVM): NOT DETECTED (check BIOS settings)"
    fi

    if [[ "$iommu_groups" -gt 0 ]]; then
        verdict_ok "IOMMU: ACTIVE ($iommu_groups groups)"
    elif grep -qiE "intel_iommu|amd_iommu|iommu" /proc/cmdline 2>/dev/null; then
        verdict_warn "IOMMU: in kernel cmdline but no groups found (check BIOS VT-d/AMD-Vi)"
    fi

    if [[ "$threads_per_core" -eq 2 ]]; then
        verdict_ok "SMT: ENABLED ($physical_cores cores → $logical_cores threads)"
    elif [[ "$threads_per_core" -eq 1 ]]; then
        verdict_fail "SMT: DISABLED ($physical_cores cores, enable in BIOS)"
    fi

    # --full: C-states
    if [[ "$FULL_MODE" == true ]]; then
        local max_cstate
        if [[ -f /sys/module/intel_idle/parameters/max_cstate ]]; then
            max_cstate=$(cat /sys/module/intel_idle/parameters/max_cstate 2>/dev/null)
            if [[ "$max_cstate" -ge 6 ]]; then
                verdict_ok "C-States: All enabled (max C${max_cstate})"
            else
                verdict_warn "C-States: Limited to C${max_cstate} (BIOS may be restricting)"
            fi
        elif [[ -f /sys/module/acpi_idle/parameters/max_cstate ]]; then
            max_cstate=$(cat /sys/module/acpi_idle/parameters/max_cstate 2>/dev/null)
            verdict_ok "C-States: max C${max_cstate} (via acpi_idle)"
        fi
    fi

    flush_verdicts
    sect "└───────────────────────────────────────────────────────────────┐"
    echo
}

# ────────────────────────────────────────────────────────────────
# RAM
# ────────────────────────────────────────────────────────────────
check_ram() {
    sect "┌─ RAM ─────────────────────────────────────────────────────────┘"
    VERDICTS=()

    local total_ram dmidecode dmidecode_mem
    local ram_type slots_total slots_used ram_speed

    total_ram=$(awk '/MemTotal/ {printf "%.1f GiB", $2/1024/1024}' /proc/meminfo)
    info "Total: $total_ram"

    dmidecode=$(command -v dmidecode 2>/dev/null)
    dmidecode_mem=""
    if [[ -n "$dmidecode" ]] && sudo -n "$dmidecode" -t memory >/dev/null 2>&1; then
        dmidecode_mem=$(sudo -n "$dmidecode" -t memory 2>/dev/null)

        ram_type=$(awk '/^\s*Type:/ && !/Unknown/ && !/Other/ && !/Error/ {
            gsub(/^\s+|\s+$/, "", $2); print $2; exit}' <<< "$dmidecode_mem")
        info "Type: ${ram_type:-Unknown}"

        slots_total=$(grep -c "Memory Device" <<< "$dmidecode_mem" || true)
        slots_used=$(awk '/^\s*Size:/ && /GB|MB/ {count++} END {print count+0}' \
            <<< "$dmidecode_mem")
        info "Slots: $slots_used of $slots_total populated"

        # --full: ECC
        if [[ "$FULL_MODE" == true ]]; then
            local ecc
            ecc=$(awk '/Error Correction Type:/ {
                sub(/.*: /, ""); gsub(/^\s+|\s+$/, ""); print; exit}' <<< "$dmidecode_mem")
            [[ -n "$ecc" ]] && info "ECC: $ecc"
        fi

        ram_speed=$(awk -F: '/^\s*Speed:/ && /[0-9]/ && !/Unknown/ {
            gsub(/^\s+|\s+$/, "", $2); print $2; exit}' <<< "$dmidecode_mem")
        if [[ -n "$ram_speed" ]]; then
            verdict_ok "Speed: $ram_speed"
        else
            verdict_warn "Speed: Unable to detect (check XMP/DOCP/EXPO in BIOS)"
        fi
    else
        verdict_warn "dmidecode not available (or missing sudoers entry)"
    fi

    flush_verdicts
    sect "└───────────────────────────────────────────────────────────────┐"
    echo
}

# ────────────────────────────────────────────────────────────────
# GPU & GRAPHICS
# ────────────────────────────────────────────────────────────────
check_gpu() {
    sect "┌─ GPU & GRAPHICS ──────────────────────────────────────────────┘"
    VERDICTS=()

    local gpu_line gpu_name gpu_pci gpu_vendor
    local glxinfo vulkan_api
    local gpu_sclk gpu_mclk card card_dir vram_total vram_used vram_found

    gpu_line=$(lspci | grep -E "VGA|3D|Display" | head -1)
    gpu_name=$(echo "$gpu_line" | cut -d: -f3- | xargs)
    gpu_pci=$(echo "$gpu_line" | awk '{print $1}')

    if echo "$gpu_name" | grep -qi "intel"; then        gpu_vendor="intel"
    elif echo "$gpu_name" | grep -qi "amd\|radeon"; then gpu_vendor="amd"
    elif echo "$gpu_name" | grep -qi "nvidia"; then      gpu_vendor="nvidia"
    else                                                  gpu_vendor="unknown"
    fi

    # Export so check_performance() can use it
    GPU_VENDOR="$gpu_vendor"
    GPU_PCI="$gpu_pci"

    info "GPU: ${gpu_name:-None detected}"

    if command -v glxinfo >/dev/null 2>&1; then
        glxinfo=$(glxinfo -B 2>/dev/null)
        info "Mesa: $(awk -F: '/OpenGL version string/ {print $2}' <<< "$glxinfo" | xargs)"
        info "Renderer: $(awk -F: '/OpenGL renderer string/ {print $2}' <<< "$glxinfo" | xargs)"
    else
        info "Mesa info: glxinfo not available"
    fi

    if command -v vulkaninfo >/dev/null 2>&1; then
        vulkan_api=$(vulkaninfo --summary 2>/dev/null | \
            awk -F: '/Vulkan Instance Version/ {print $2}' | xargs)
        info "Vulkan: ${vulkan_api:-Available}"
    fi

    if [[ "$gpu_vendor" == "amd" ]]; then
        gpu_sclk="" gpu_mclk=""
        for card in /sys/class/drm/card*/device; do
            [[ -f "$card/pp_dpm_sclk" ]] && \
                gpu_sclk=$(grep "\*" "$card/pp_dpm_sclk" | awk '{print $2}')
            [[ -f "$card/pp_dpm_mclk" ]] && \
                gpu_mclk=$(grep "\*" "$card/pp_dpm_mclk" | awk '{print $2}')
            if [[ -n "$gpu_sclk" && -n "$gpu_mclk" ]]; then
                info "Clocks: Core $gpu_sclk | Memory $gpu_mclk"; break
            fi
        done
        vram_found=false
        for card in /sys/class/drm/card*/device/mem_info_vram_total; do
            [[ -f "$card" ]] || continue
            card_dir=$(dirname "$card")
            vram_total=$(cat "$card" 2>/dev/null)
            vram_used=$(cat "${card_dir}/mem_info_vram_used" 2>/dev/null)
            if [[ "$vram_total" =~ ^[0-9]+$ && "$vram_total" -gt 0 ]]; then
                vram_found=true
                info "VRAM: $((vram_used/1024/1024)) MiB used / $((vram_total/1024/1024)) MiB total"
                break
            fi
        done
        [[ "$vram_found" == false ]] && info "VRAM: Unable to detect"
    elif [[ "$gpu_vendor" == "intel" ]]; then
        info "VRAM: Shared system RAM (integrated GPU)"
    fi

    flush_verdicts
    sect "└───────────────────────────────────────────────────────────────┐"
    echo
}

# ────────────────────────────────────────────────────────────────
# STORAGE
# ────────────────────────────────────────────────────────────────
check_storage() {
    sect "┌─ STORAGE ─────────────────────────────────────────────────────┘"
    VERDICTS=()

    local nvme_count nvme_pci nvme_name nvme_lnksta nvme_speed nvme_width

    nvme_count=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        nvme_pci=$(echo "$line" | awk '{print $1}')
        nvme_name=$(echo "$line" | cut -d: -f3- | xargs)
        nvme_count=$((nvme_count + 1))
        nvme_lnksta=$(sudo -n lspci -s "$nvme_pci" -vv 2>/dev/null | grep "LnkSta:")
        info "NVMe $nvme_count: $nvme_name"
        if [[ -n "$nvme_lnksta" ]]; then
            nvme_speed=$(echo "$nvme_lnksta" | sed -E 's/.*Speed ([^,]+),.*/\1/')
            nvme_width=$(echo "$nvme_lnksta" | sed -E 's/.*Width x([0-9]+).*/\1/')
            [[ "$nvme_speed" != "$nvme_lnksta" ]] && \
                info "        PCIe $nvme_speed x$nvme_width"
        fi
    done < <(lspci | grep -i "Non-Volatile\|NVMe")
    [[ "$nvme_count" -eq 0 ]] && info "NVMe: None detected"

    # --full: SATA mode
    if [[ "$FULL_MODE" == true ]]; then
        local sata_count sata_name
        sata_count=0
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            sata_count=$((sata_count + 1))
            sata_name=$(echo "$line" | cut -d: -f3- | xargs)
            if echo "$sata_name" | grep -qi "ahci"; then
                verdict_ok "SATA $sata_count: AHCI mode — $sata_name"
            elif echo "$sata_name" | grep -qi "raid"; then
                verdict_warn "SATA $sata_count: RAID mode — use AHCI for Linux unless intentional"
            else
                info "SATA $sata_count: $sata_name"
            fi
        done < <(lspci | grep -iE "SATA|AHCI" | grep -iv "NVMe\|Non-Volatile")
        [[ "$sata_count" -eq 0 ]] && info "SATA: No SATA controller detected"
    fi

    flush_verdicts
    sect "└───────────────────────────────────────────────────────────────┐"
    echo
}

# ────────────────────────────────────────────────────────────────
# PERFORMANCE FEATURES
# ────────────────────────────────────────────────────────────────
check_performance() {
    sect "┌─ PERFORMANCE FEATURES ────────────────────────────────────────┘"
    VERDICTS=()

    local bar_info bar_size pcie_info pcie_speed pcie_width
    local current_profile gov ab4g

    if [[ "${GPU_VENDOR:-unknown}" == "intel" ]]; then
        info "BAR/PCIe: Integrated GPU — no discrete PCIe slot"
    elif [[ -n "${GPU_PCI:-}" ]]; then
        bar_info=$(sudo -n lspci -s "$GPU_PCI" -vv 2>/dev/null | grep -i "Region 0")
        if [[ -n "$bar_info" ]]; then
            bar_size=$(echo "$bar_info" | sed -E 's/.*\[size=([^]]+)\].*/\1/')
            if [[ -n "$bar_size" && "$bar_size" != "$bar_info" ]]; then
                if [[ "$bar_size" == *"G"* ]]; then
                    verdict_ok "Resizable BAR: ENABLED ($bar_size)"
                else
                    verdict_fail "Resizable BAR: DISABLED ($bar_size) — enable in BIOS"
                fi
            fi
        fi
        pcie_info=$(sudo -n lspci -s "$GPU_PCI" -vv 2>/dev/null | grep -i "LnkSta:")
        if [[ -n "$pcie_info" ]]; then
            pcie_speed=$(echo "$pcie_info" | sed -E 's/.*Speed ([^,]+),.*/\1/')
            pcie_width=$(echo "$pcie_info" | sed -E 's/.*Width x([0-9]+).*/\1/')
            if [[ "$pcie_speed" == *"32GT/s"* && "$pcie_width" == "16" ]]; then
                verdict_ok "PCIe: Gen5 x16 @ 32GT/s (maximum performance)"
            elif [[ "$pcie_speed" == *"16GT/s"* && "$pcie_width" == "16" ]]; then
                verdict_ok "PCIe: Gen4 x16 @ 16GT/s (good)"
            elif [[ "$pcie_width" != "16" ]]; then
                verdict_warn "PCIe: $pcie_speed x$pcie_width (expected x16)"
            elif [[ "$pcie_speed" == *"8GT/s"* ]]; then
                verdict_warn "PCIe: Gen3 @ 8GT/s (slower than expected)"
            else
                info "PCIe: $pcie_speed x$pcie_width"
            fi
        fi
    fi

    # --full: Above 4G decoding
    if [[ "$FULL_MODE" == true ]]; then
        ab4g=$(sudo -n lspci -vv 2>/dev/null | \
            grep -c "Memory at.*64-bit, prefetchable" || true)
        if [[ "$ab4g" -gt 0 ]]; then
            verdict_ok "Above 4G Decoding: Active ($ab4g 64-bit prefetchable regions)"
        else
            info "Above 4G Decoding: No 64-bit prefetchable BARs detected"
        fi
    fi

    if command -v powerprofilesctl >/dev/null 2>&1; then
        current_profile=$(powerprofilesctl get 2>/dev/null)
        if [[ -n "$current_profile" ]]; then
            if [[ "$current_profile" == "performance" ]]; then
                verdict_ok "Power Profile: Performance mode"
            elif [[ "$current_profile" == "balanced" ]]; then
                verdict_warn "Power Profile: Balanced (consider performance for gaming)"
            else
                info "Power Profile: $current_profile"
            fi
        fi
    else
        if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]]; then
            gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)
            if [[ "$gov" == "performance" ]]; then
                verdict_ok "CPU Governor: Performance"
            else
                info "CPU Governor: $gov"
            fi
        fi
    fi

    flush_verdicts
    sect "└───────────────────────────────────────────────────────────────┐"
    echo
}

# ────────────────────────────────────────────────────────────────
# SYSTEM INFO
# ────────────────────────────────────────────────────────────────
check_system() {
    sect "┌─ SYSTEM INFO ─────────────────────────────────────────────────┘"
    VERDICTS=()

    local bios_vendor bios_version bios_date
    local sb_var sb_val sb_status tpm_ver

    info "Kernel: $(uname -r)"

    bios_vendor=$(cat /sys/class/dmi/id/bios_vendor 2>/dev/null)
    bios_version=$(cat /sys/class/dmi/id/bios_version 2>/dev/null)
    bios_date=$(cat /sys/class/dmi/id/bios_date 2>/dev/null)
    info "BIOS: ${bios_vendor:-Unknown} ${bios_version:-Unknown}"
    info "Date: ${bios_date:-Unknown}"

    # --full: boot order + Thunderbolt
    if [[ "$FULL_MODE" == true ]]; then
        local boot_current tb_devices tb_security
        if command -v efibootmgr >/dev/null 2>&1; then
            boot_current=$(efibootmgr 2>/dev/null | awk '/BootCurrent:/ {print $2}')
            info "Boot Current: ${boot_current:-Unknown}"
            info "Boot Order:"
            efibootmgr 2>/dev/null | awk \
                -v g="${GREEN}" -v r="${RED}" -v rs="${RESET}" \
                '/Boot[0-9A-F]{4}/ && !/BootCurrent|BootOrder|BootNext/ {
                    active = /\*/ ? g "✓" rs : r "✗" rs
                    sub(/Boot[0-9A-F]{4}[* ]+/, "")
                    printf "│   %s %s\n", active, $0
                }' | head -6
        else
            info "Boot Order: efibootmgr not installed ($_PKG_INSTALL efibootmgr)"
        fi

        tb_devices=$(ls /sys/bus/thunderbolt/devices/ 2>/dev/null | wc -l)
        if [[ "$tb_devices" -gt 0 ]]; then
            tb_security=$(cat /sys/bus/thunderbolt/devices/domain0/security \
                2>/dev/null | xargs)
            info "Thunderbolt: Present (security: ${tb_security:-unknown}, devices: $tb_devices)"
        else
            info "Thunderbolt: Not detected or disabled in BIOS"
        fi
    fi

    # Verdicts
    if [[ -d /sys/firmware/efi ]]; then
        verdict_ok "Boot Mode: UEFI"
        sb_var=$(find /sys/firmware/efi/efivars -name "SecureBoot-*" \
            2>/dev/null | head -1)
        if [[ -n "$sb_var" ]]; then
            sb_val=$(od -An -t u1 "$sb_var" 2>/dev/null | awk '{print $NF}')
            if [[ "$sb_val" == "1" ]]; then
                verdict_ok "Secure Boot: ENABLED"
            else
                verdict_warn "Secure Boot: DISABLED"
            fi
        elif command -v mokutil >/dev/null 2>&1; then
            sb_status=$(mokutil --sb-state 2>/dev/null | xargs)
            verdict_warn "Secure Boot: ${sb_status:-Unknown}"
        fi
    else
        verdict_fail "Boot Mode: Legacy BIOS (not UEFI)"
    fi

    if [[ -d /sys/class/tpm/tpm0 ]]; then
        tpm_ver=$(cat /sys/class/tpm/tpm0/tpm_version_major 2>/dev/null)
        verdict_ok "TPM: Present (version ${tpm_ver:-?})"
    else
        verdict_warn "TPM: Not detected (check BIOS fTPM/TPM setting)"
    fi

    flush_verdicts
    sect "└───────────────────────────────────────────────────────────────┐"
    echo
}

# ────────────────────────────────────────────────────────────────
# ARGUMENT HANDLING
# ────────────────────────────────────────────────────────────────
FULL_MODE=false
case "${1:-}" in
    --help|-h)  show_help;  exit 0 ;;
    --check|-c) show_check; exit 0 ;;
    --full|-f)  FULL_MODE=true ;;
    "")         ;;
    *)          echo "Unknown option: $1  (use --help)"; exit 1 ;;
esac

# ────────────────────────────────────────────────────────────────
# MAIN
# ────────────────────────────────────────────────────────────────
main() {
    echo ""
    if [[ "$FULL_MODE" == true ]]; then
        echo -e "${BOLD}╔════════════════════════════════════════════════════════════════╗${RESET}"
        echo -e "${BOLD}║     SYSTEM STATUS CHECK - BIOS Settings ok? [FULL MODE]        ║${RESET}"
        echo -e "${BOLD}║     Verifying hardware settings after BIOS update              ║${RESET}"
        echo -e "${BOLD}╚════════════════════════════════════════════════════════════════╝${RESET}"
    else
        echo -e "${BOLD}╔════════════════════════════════════════════════════════════════╗${RESET}"
        echo -e "${BOLD}║        SYSTEM STATUS CHECK - BIOS Settings ok?                 ║${RESET}"
        echo -e "${BOLD}║        Verifying hardware settings after BIOS update           ║${RESET}"
        echo -e "${BOLD}╚════════════════════════════════════════════════════════════════╝${RESET}"
    fi
    echo ""

    check_cpu
    check_ram
    check_gpu
    check_storage
    check_performance
    check_system
}

main
