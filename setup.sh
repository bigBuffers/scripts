#!/usr/bin/env bash
# Install or update the tools and expose commands in ~/.local/bin.
{
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: bash setup.sh [--no-path] [--help]

SCRIPTS_DIR       Checkout location (default: ~/tool)
SCRIPTS_BIN_DIR   Command directory (default: ~/.local/bin)

--no-path        Do not update shell startup files
EOF
}

update_path=1
for arg in "$@"; do
    case "$arg" in
        --help|-h) usage; exit 0 ;;
        --no-path) update_path=0 ;;
        *) printf 'Unknown argument: %s\n' "$arg" >&2; usage >&2; exit 2 ;;
    esac
done

repo_url="https://github.com/bigBuffers/scripts.git"
install_dir="${SCRIPTS_DIR:-$HOME/tool}"
bin_dir="${SCRIPTS_BIN_DIR:-$HOME/.local/bin}"
for path in "$install_dir" "$bin_dir"; do
    case "$path" in
        /*) ;;
        *) printf 'Installation paths must be absolute: %s\n' "$path" >&2; exit 1 ;;
    esac
done
command -v git >/dev/null 2>&1 || {
    printf 'Git is required. Install Git, then run setup again.\n' >&2
    exit 1
}

if [[ -e "$install_dir" || -L "$install_dir" ]]; then
    [[ -d "$install_dir/.git" || -f "$install_dir/.git" ]] || {
        printf 'Existing directory is not a Git checkout: %s\n' "$install_dir" >&2
        printf 'Choose another directory with SCRIPTS_DIR.\n' >&2
        exit 1
    }
    origin="$(git -C "$install_dir" config --get remote.origin.url)"
    case "$origin" in
        https://github.com/bigBuffers/scripts|https://github.com/bigBuffers/scripts.git|git@github.com:bigBuffers/scripts|git@github.com:bigBuffers/scripts.git) ;;
        *) printf 'Unexpected origin in %s: %s\n' "$install_dir" "$origin" >&2; exit 1 ;;
    esac
    [[ "$(git -C "$install_dir" symbolic-ref --short HEAD)" == main ]] || {
        printf 'Switch the checkout to main before updating.\n' >&2; exit 1
    }
    [[ -z "$(git -C "$install_dir" status --porcelain)" ]] || {
        printf 'Commit or stash local changes before updating: %s\n' "$install_dir" >&2; exit 1
    }
    git -C "$install_dir" pull --ff-only origin main
else
    mkdir -p "$(dirname "$install_dir")"
    git clone --branch main "$repo_url" "$install_dir"
fi

commands=(machine_detect setup_privoxy start_vnc ssh_bot ssh_drivefarm ssh_dcs ssh_pc setup_rr_dt_ssh setup_maglev download_rrlog pull_sil_rrlogs scripts_update)
sources=(machine_detect.sh setup_privoxy.sh start_vnc.sh ssh_bot_pc.sh ssh_drivefarm.sh ssh_dcs.sh ssh_pc.sh setup_rr_dt_ssh.sh setup_maglev.sh download_rrlog.sh pull_sil_rrlogs.py setup.sh)

# Check every destination before creating links; keep unrelated commands intact.
# Links that already point into this checkout are ours and get refreshed.
for ((i=0; i<${#commands[@]}; i++)); do
    source_path="$install_dir/${sources[$i]}"
    destination="$bin_dir/${commands[$i]}"
    [[ -f "$source_path" ]] || { printf 'Missing script: %s\n' "$source_path" >&2; exit 1; }
    if [[ -L "$destination" ]]; then
        case "$(readlink "$destination")" in
            "$install_dir"/*) ;;
            *) printf 'Command already exists: %s\nChoose another SCRIPTS_BIN_DIR.\n' "$destination" >&2; exit 1 ;;
        esac
    elif [[ -e "$destination" ]]; then
        printf 'Command already exists: %s\nChoose another SCRIPTS_BIN_DIR.\n' "$destination" >&2
        exit 1
    fi
done

mkdir -p "$bin_dir"
for ((i=0; i<${#commands[@]}; i++)); do
    source_path="$install_dir/${sources[$i]}"
    destination="$bin_dir/${commands[$i]}"
    chmod u+x "$source_path"
    ln -sf "$source_path" "$destination"
done

if [[ "$update_path" == 1 ]]; then
    path_line="export PATH=$(printf '%q' "$bin_dir"):\$PATH"
    case "${SHELL:-/bin/bash}" in
        */zsh) startup_files=("$HOME/.zshrc") ;;
        *)
            if [[ "$(uname -s)" == Darwin ]]; then
                startup_files=("$HOME/.bash_profile" "$HOME/.bashrc")
            else
                startup_files=("$HOME/.profile" "$HOME/.bashrc")
            fi
            ;;
    esac
    for startup_file in "${startup_files[@]}"; do
        if ! grep -Fqx "$path_line" "$startup_file" 2>/dev/null; then
            printf '\n# bigBuffers/scripts\n%s\n' "$path_line" >> "$startup_file"
        fi
    done
fi

printf '\nInstalled in %s\nCommands: %s\n' "$install_dir" "${commands[*]}"
printf 'For this shell, run: export PATH=%q:"$PATH"\n' "$bin_dir"
printf 'Update with: SCRIPTS_DIR=%q SCRIPTS_BIN_DIR=%q scripts_update\n' "$install_dir" "$bin_dir"
if [[ ! -f "$install_dir/.env" ]]; then
    printf 'Local settings (passwords, API keys): cp %q %q && chmod 600 %q\n' \
        "$install_dir/.env.example" "$install_dir/.env" "$install_dir/.env"
fi
}
