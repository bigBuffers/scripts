# scripts

Small, dependency-free shell scripts. Each one runs directly from GitHub on any
network-connected machine, no install step:

```sh
curl -fsSL https://raw.githubusercontent.com/bigBuffers/scripts/main/<script> | bash
```

## machine_detect.sh

Collects hardware information on Ubuntu/Linux and macOS: system / DMI, CPU,
memory (per-DIMM on Linux with root), GPU (lspci + nvidia-smi, or
system_profiler), storage, network, USB, PCI, battery.
Works with bash 3.2 (macOS default) and bash 5.

```sh
# full report to the terminal
curl -fsSL https://raw.githubusercontent.com/bigBuffers/scripts/main/machine_detect.sh | bash

# only some sections (system,cpu,memory,gpu,storage,network,usb,pci,power)
curl -fsSL https://raw.githubusercontent.com/bigBuffers/scripts/main/machine_detect.sh | bash -s -- -s cpu,memory,gpu

# Linux, with root: serial numbers, DIMM details, verbose dumps, and save to a file
curl -fsSL https://raw.githubusercontent.com/bigBuffers/scripts/main/machine_detect.sh | sudo bash -s -- -v -o /tmp/hw.txt

# or download once and keep it
curl -fsSLo machine_detect.sh https://raw.githubusercontent.com/bigBuffers/scripts/main/machine_detect.sh
chmod +x machine_detect.sh && ./machine_detect.sh -h
```

Options: `-o FILE` also write to a file, `-s SECTIONS` subset, `-v` verbose, `-h` help.
Root is optional; without it the Linux DMI serials and per-DIMM table are skipped with a hint.
