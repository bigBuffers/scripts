#!/usr/bin/env bash
# Install the Maglev CLI and log in with MAGLEV_API_KEY (environment or .env).
# The key is also added to the shell startup file so later shells can use it.
set -euo pipefail

# Find the checkout (this file may be a symlink in ~/.local/bin) and load lib + .env.
self="${BASH_SOURCE[0]}"
while [[ -L "$self" ]]; do
    link="$(readlink "$self")"
    case "$link" in /*) self="$link" ;; *) self="$(dirname "$self")/$link" ;; esac
done
. "$(cd "$(dirname "$self")" && pwd)/lib/common.sh"

[[ -n "${MAGLEV_API_KEY:-}" ]] || die "MAGLEV_API_KEY is not set. Add it to $TOOL_DIR/.env (see .env.example) or export it first."

case "${SHELL:-/bin/bash}" in
    */zsh) rc_file="$HOME/.zshrc" ;;
    *)     rc_file="$HOME/.bashrc" ;;
esac
export_line="export MAGLEV_API_KEY=\"$MAGLEV_API_KEY\""

# 1. Ensure the startup file exists and contains the export (idempotent).
if [[ ! -f "$rc_file" ]]; then
    touch "$rc_file"
    chmod 600 "$rc_file"
fi
if ! grep -qxF "$export_line" "$rc_file"; then
    printf '\n%s\n' "$export_line" >> "$rc_file"
    echo "==> Added MAGLEV_API_KEY to $rc_file"
fi

# 2. Install the maglev CLI and log in.
export MAGLEV_API_KEY
bash -c "$(curl -fsSL https://cdn-prod.nvda.ai/cli/install-maglev-cli.sh)"
maglev login maglev.nvda.ai "$MAGLEV_API_KEY"
