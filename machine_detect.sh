#!/usr/bin/env bash
# machine_detect.sh - collect hardware information on Ubuntu (Linux) and macOS.
#
# Compatible with bash 3.2 (macOS default) and bash 5 (Ubuntu).
# Root is not required. On Linux, DMI serials and per-DIMM details come from
# dmidecode and need root; without it those parts are skipped with a hint.

set -u
set -o pipefail
export LC_ALL=C

ALL_SECTIONS="system cpu memory gpu storage network usb pci power"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [-o FILE] [-s SECTIONS] [-v] [-h]

  -o FILE      also write the report to FILE (stdout is kept)
  -s SECTIONS  comma-separated subset of: ${ALL_SECTIONS// /,}
  -v           verbose: include full raw dumps (dmidecode, lspci -nnk, lsusb -t,
               sysctl hw, system_profiler storage / usb trees)
  -h           show this help

Examples:
  $(basename "$0")                         # full report to stdout
  $(basename "$0") -s cpu,memory,gpu       # only a few sections
  sudo $(basename "$0") -v -o /tmp/hw.txt  # Linux: full detail incl. serials

Run from any machine without installing:
  curl -fsSL https://raw.githubusercontent.com/bigBuffers/scripts/main/machine_detect.sh | bash
  curl -fsSL https://raw.githubusercontent.com/bigBuffers/scripts/main/machine_detect.sh | bash -s -- -s cpu,memory
  curl -fsSL https://raw.githubusercontent.com/bigBuffers/scripts/main/machine_detect.sh | sudo bash -s -- -v -o /tmp/hw.txt
USAGE
}

OS="$(uname -s)"
ARCH="$(uname -m)"
OUTPUT=""
SECTIONS="${ALL_SECTIONS// /,}"
VERBOSE=0

while getopts ":o:s:vh" opt; do
  case "$opt" in
    o) OUTPUT="$OPTARG" ;;
    s) SECTIONS="$OPTARG" ;;
    v) VERBOSE=1 ;;
    h) usage; exit 0 ;;
    \?) echo "unknown option: -$OPTARG" >&2; usage >&2; exit 2 ;;
    :)  echo "option -$OPTARG requires an argument" >&2; exit 2 ;;
  esac
done

# validate -s
for s in $(printf '%s' "$SECTIONS" | tr ',' ' '); do
  case " $ALL_SECTIONS " in
    *" $s "*) ;;
    *) echo "unknown section '$s' (valid: ${ALL_SECTIONS// /,})" >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------- helpers ---

have()    { command -v "$1" >/dev/null 2>&1; }
hr()      { printf '%s\n' "------------------------------------------------------------"; }
section() { printf '\n'; hr; printf '## %s\n' "$1"; hr; }
sub()     { printf '\n### %s\n' "$1"; }
want()    { case ",$SECTIONS," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

# kv LABEL VALUE : print "LABEL : VALUE" only when VALUE is non-empty
kv() { [ -n "${2:-}" ] && printf '%-18s: %s\n' "$1" "$2"; return 0; }

# strip system_profiler indentation and blank lines
sp_clean() { sed 's/^ *//' | grep -v '^$'; }

# dimm_table : stdin = "dmidecode -t memory", stdout = one line per populated slot
dimm_table() {
  printf '%-14s %-10s %-8s %-14s %-18s %s\n' LOCATOR SIZE TYPE SPEED MANUFACTURER PART
  awk '
        function flush() {
          if (indev && size != "" && size != "No Module Installed" && size != "Not Installed")
            printf "%-14s %-10s %-8s %-14s %-18s %s\n", loc, size, type, speed, mfr, part
          indev = 0
        }
        /^Memory Device$/     { flush(); indev=1; size=type=speed=mfr=part=loc=""; next }
        indev && /^\tSize:/          { sub(/^\tSize: /, "");         size=$0 }
        indev && /^\tType:/          { sub(/^\tType: /, "");         type=$0 }
        indev && /^\tSpeed:/         { sub(/^\tSpeed: /, "");        speed=$0 }
        indev && /^\tManufacturer:/  { sub(/^\tManufacturer: /, ""); mfr=$0 }
        indev && /^\tPart Number:/   { sub(/^\tPart Number: /, "");  part=$0 }
        indev && /^\tLocator:/       { sub(/^\tLocator: /, "");      loc=$0 }
        /^$/                  { flush() }
        END                   { flush() }
  '
}

IS_ROOT=0
[ "$(id -u)" = "0" ] && IS_ROOT=1

# how to re-run with root; differs when the script is piped through "curl | bash"
RAW_URL="https://raw.githubusercontent.com/bigBuffers/scripts/main/machine_detect.sh"
if [ -f "$0" ]; then SELF="sudo $0"; else SELF="curl -fsSL $RAW_URL | sudo bash"; fi

# dmi ARGS... : run dmidecode as root when possible (direct or passwordless sudo)
dmi() {
  if [ "$IS_ROOT" = 1 ]; then
    dmidecode "$@" 2>/dev/null
  elif have sudo && sudo -n true 2>/dev/null; then
    sudo -n dmidecode "$@" 2>/dev/null
  else
    return 1
  fi
}

# ------------------------------------------------------------------ Linux ---

linux_system() {
  section "SYSTEM"
  kv "Hostname" "$(hostname)"
  kv "OS" "$( . /etc/os-release 2>/dev/null && printf '%s' "${PRETTY_NAME:-}" )"
  kv "Kernel" "$(uname -r)"
  kv "Arch" "$ARCH"
  kv "Uptime" "$(uptime -p 2>/dev/null || uptime)"
  if have hostnamectl; then
    hostnamectl 2>/dev/null \
      | grep -E 'Chassis|Virtualization|Hardware Vendor|Hardware Model|Firmware' \
      | sed 's/^ *//'
  fi
  [ -r /proc/device-tree/model ] && kv "Device-tree model" "$(tr -d '\0' </proc/device-tree/model)"
  [ -r /etc/nv_tegra_release ] && kv "Tegra release" "$(head -1 /etc/nv_tegra_release)"

  sub "DMI (vendor / model / serial / BIOS)"
  if dmi -t system >/dev/null 2>&1; then
    kv "Manufacturer"  "$(dmi -s system-manufacturer)"
    kv "Product"       "$(dmi -s system-product-name)"
    kv "Version"       "$(dmi -s system-version)"
    kv "Serial"        "$(dmi -s system-serial-number)"
    kv "UUID"          "$(dmi -s system-uuid)"
    kv "Baseboard"     "$(dmi -s baseboard-manufacturer) $(dmi -s baseboard-product-name)"
    kv "Baseboard S/N" "$(dmi -s baseboard-serial-number)"
    kv "BIOS"          "$(dmi -s bios-vendor) $(dmi -s bios-version) ($(dmi -s bios-release-date))"
    if [ "$VERBOSE" = 1 ]; then sub "dmidecode -t system -t baseboard -t bios -t chassis"; dmi -t system -t baseboard -t bios -t chassis; fi
  elif [ -d /sys/class/dmi/id ]; then
    # sysfs is readable without root, but has no serial numbers
    local f
    for f in sys_vendor product_name product_version board_vendor board_name bios_vendor bios_version bios_date; do
      [ -r "/sys/class/dmi/id/$f" ] && kv "$f" "$(cat "/sys/class/dmi/id/$f")"
    done
    printf '(serial numbers / UUID need root: %s)\n' "$SELF"
  else
    printf '(no DMI on this platform)\n'
  fi
}

linux_cpu() {
  section "CPU"
  if have lscpu; then
    lscpu | grep -E '^(Architecture|CPU\(s\)|On-line|Vendor ID|Model name|Thread\(s\) per core|Core\(s\) per socket|Socket\(s\)|CPU max MHz|CPU min MHz|L1d|L1i|L2|L3|NUMA node\(s\)|Virtualization|Hypervisor)'
    if [ "$VERBOSE" = 1 ]; then sub "lscpu (full)"; lscpu; fi
  else
    grep -m1 'model name' /proc/cpuinfo
    kv "Logical CPUs" "$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo)"
  fi
}

linux_memory() {
  section "MEMORY"
  if have free; then free -h; else grep -E 'MemTotal|MemAvailable|SwapTotal' /proc/meminfo; fi

  sub "DIMM slots (dmidecode -t memory)"
  if dmi -t memory >/dev/null 2>&1; then
    if [ "$VERBOSE" = 1 ]; then
      dmi -t memory
    else
      dmi -t memory | dimm_table
    fi
  else
    printf '(per-DIMM size/type/speed needs root: %s)\n' "$SELF"
  fi
}

linux_gpu() {
  section "GPU"
  if have lspci; then
    lspci -nn 2>/dev/null | grep -Ei 'vga|3d controller|display controller' \
      || printf '(no PCI display controller; integrated/Tegra GPU has no PCI entry)\n'
  fi
  if have nvidia-smi; then
    sub "nvidia-smi"
    nvidia-smi --query-gpu=index,name,driver_version,memory.total,pci.bus_id,vbios_version --format=csv 2>&1
  fi
  if [ -d /proc/driver/nvidia ]; then
    sub "NVIDIA kernel driver"
    head -1 /proc/driver/nvidia/version 2>/dev/null
  fi
}

linux_storage() {
  section "STORAGE"
  sub "Block devices (lsblk)"
  if have lsblk; then
    lsblk -e 7 -o NAME,SIZE,TYPE,FSTYPE,MODEL,SERIAL,TRAN,ROTA,MOUNTPOINT 2>/dev/null || lsblk -e 7
  else
    printf '(lsblk not installed)\n'
  fi
  sub "Filesystems (df)"
  df -hT -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs 2>/dev/null || df -h
  if [ "$VERBOSE" = 1 ] && have nvme; then
    sub "NVMe (nvme list)"; nvme list 2>&1
  fi
}

linux_network() {
  section "NETWORK"
  if have ip; then
    sub "Interfaces (link / MAC)"
    ip -brief link 2>/dev/null || ip link
    sub "Addresses"
    ip -brief addr 2>/dev/null || ip addr
    sub "Default route"
    ip route show default 2>/dev/null
  elif have ifconfig; then
    ifconfig -a
  fi
  if have lspci; then
    sub "Network controllers (PCI)"
    lspci 2>/dev/null | grep -Ei 'ethernet|network|wireless' || printf '(none)\n'
  fi
}

linux_usb() {
  section "USB"
  if have lsusb; then
    lsusb 2>&1
    if [ "$VERBOSE" = 1 ]; then sub "lsusb -t"; lsusb -t 2>&1; fi
  else
    printf '(lsusb not installed: sudo apt install usbutils)\n'
  fi
}

linux_pci() {
  section "PCI"
  if have lspci; then
    if [ "$VERBOSE" = 1 ]; then lspci -nnk 2>&1; else lspci 2>&1; fi
  else
    printf '(lspci not installed: sudo apt install pciutils)\n'
  fi
}

linux_power() {
  section "POWER / BATTERY"
  local found=0 d k
  for d in /sys/class/power_supply/*; do
    [ -d "$d" ] || continue
    found=1
    printf '%s:' "$(basename "$d")"
    for k in type status capacity energy_full_design energy_full cycle_count manufacturer model_name; do
      [ -r "$d/$k" ] && printf ' %s=%s' "$k" "$(cat "$d/$k" 2>/dev/null)"
    done
    printf '\n'
  done
  [ "$found" = 0 ] && printf '(no battery / power-supply entries)\n'
  return 0
}

# ------------------------------------------------------------------ macOS ---

mac_system() {
  section "SYSTEM"
  kv "Hostname"      "$(hostname)"
  kv "Computer name" "$(scutil --get ComputerName 2>/dev/null)"
  kv "OS"            "$(sw_vers -productName) $(sw_vers -productVersion) (build $(sw_vers -buildVersion))"
  kv "Kernel"        "$(uname -r)"
  kv "Arch"          "$ARCH"
  kv "Uptime"        "$(uptime)"
  sub "Hardware overview (system_profiler SPHardwareDataType)"
  system_profiler SPHardwareDataType 2>/dev/null | sp_clean | grep -v -e '^Hardware:$' -e '^Hardware Overview:$'
}

mac_cpu() {
  section "CPU"
  kv "Model"          "$(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
  kv "Physical cores" "$(sysctl -n hw.physicalcpu 2>/dev/null)"
  kv "Logical cores"  "$(sysctl -n hw.logicalcpu 2>/dev/null)"
  # Apple Silicon: performance / efficiency core split
  local p e
  p="$(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null)"
  e="$(sysctl -n hw.perflevel1.physicalcpu 2>/dev/null)"
  [ -n "$p" ] && kv "P-cores / E-cores" "$p / ${e:-0}"
  kv "L2 cache (bytes)" "$(sysctl -n hw.l2cachesize 2>/dev/null || sysctl -n hw.perflevel0.l2cachesize 2>/dev/null)"
  if [ "$VERBOSE" = 1 ]; then sub "sysctl hw / machdep.cpu"; sysctl hw machdep.cpu 2>/dev/null; fi
}

mac_memory() {
  section "MEMORY"
  local bytes
  bytes="$(sysctl -n hw.memsize 2>/dev/null)"
  [ -n "$bytes" ] && kv "Total" "$(( bytes / 1024 / 1024 / 1024 )) GiB"
  sub "system_profiler SPMemoryDataType"
  system_profiler SPMemoryDataType 2>/dev/null | sp_clean | grep -v '^Memory:$'
}

mac_gpu() {
  section "GPU / DISPLAYS"
  system_profiler SPDisplaysDataType 2>/dev/null | sp_clean | grep -v '^Graphics/Displays:$'
}

mac_storage() {
  section "STORAGE"
  sub "diskutil list"
  diskutil list 2>&1
  sub "Filesystems (df)"
  df -h -T nodevfs,noautofs 2>/dev/null || df -h
  if [ "$VERBOSE" = 1 ]; then
    sub "system_profiler SPNVMeDataType SPSerialATADataType"
    system_profiler SPNVMeDataType SPSerialATADataType 2>/dev/null | sp_clean
  fi
}

mac_network() {
  section "NETWORK"
  sub "Hardware ports (networksetup)"
  networksetup -listallhardwareports 2>/dev/null | grep -v '^$'
  sub "Interfaces with addresses or active link (ifconfig)"
  ifconfig 2>/dev/null | awk '
    /^[a-z0-9]+: /   { iface=$1; sub(":", "", iface); order[++n]=iface; mac[iface]=""; inet[iface]=""; act[iface]=0 }
    /^\tether /      { mac[iface]=$2 }
    /^\tinet /       { inet[iface]=inet[iface] $2 " " }
    /status: active/ { act[iface]=1 }
    END { for (i=1; i<=n; i++) { x=order[i]; if (act[x] || inet[x] != "")
            printf "%-10s mac=%-18s inet=%s\n", x, mac[x], inet[x] } }
  '
  sub "Default route"
  route -n get default 2>/dev/null | grep -E 'gateway|interface' | sed 's/^ *//'
}

mac_usb() {
  section "USB"
  if [ "$VERBOSE" = 1 ]; then
    system_profiler SPUSBDataType 2>/dev/null | sp_clean
  else
    # device tree only (lines ending in ':'), keep indentation to show hierarchy
    system_profiler SPUSBDataType 2>/dev/null | grep -E ':$' | grep -v '^USB:$'
  fi
}

mac_pci() {
  section "PCI / THUNDERBOLT"
  system_profiler SPPCIDataType SPThunderboltDataType 2>/dev/null | sp_clean
}

mac_power() {
  section "POWER / BATTERY"
  pmset -g batt 2>/dev/null
  sub "system_profiler SPPowerDataType"
  system_profiler SPPowerDataType 2>/dev/null | sp_clean \
    | grep -E 'Device Name|Manufacturer|Serial Number|Cycle Count|Condition|Maximum Capacity|State of Charge|Fully Charged|Charging|Wattage|Connected'
}

# ------------------------------------------------------------------- main ---

main() {
  local pfx s
  case "$OS" in
    Linux)  pfx=linux ;;
    Darwin) pfx=mac ;;
    *) echo "unsupported OS: $OS (only Linux and Darwin)" >&2; exit 1 ;;
  esac
  printf '# machine_detect report\n'
  kv "Generated" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
  kv "User"      "$(id -un)$( [ "$IS_ROOT" = 1 ] && printf ' (root)' )"
  kv "Platform"  "$OS $ARCH"
  kv "Sections"  "$SECTIONS"
  for s in $ALL_SECTIONS; do
    want "$s" || continue
    "${pfx}_${s}"
  done
}

if [ -n "$OUTPUT" ]; then
  main 2>&1 | tee "$OUTPUT"
  printf '\nReport written to %s\n' "$OUTPUT" >&2
else
  main
fi
