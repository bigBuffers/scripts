#!/usr/bin/env bash
#
# One-time setup so that `ssh rr-dt` connects through the xterm jump host
# with no passwords. Run this once; afterwards just use `ssh rr-dt`.
#
# It will prompt ONCE for the jump-host password, then ONCE for the rr-dt
# password (the hosts use different passwords).
#
# Settings (environment or .env): RR_DT_USER and RR_DT_JUMP_USER (default:
# SSH_USER or the local user), RR_DT_HOST, RR_DT_JUMP_HOST, RR_DT_JUMP_PORT.
set -euo pipefail

# Find the checkout (this file may be a symlink in ~/.local/bin) and load lib + .env.
self="${BASH_SOURCE[0]}"
while [[ -L "$self" ]]; do
    link="$(readlink "$self")"
    case "$link" in /*) self="$link" ;; *) self="$(dirname "$self")/$link" ;; esac
done
. "$(cd "$(dirname "$self")" && pwd)/lib/common.sh"

JUMP_HOST="${RR_DT_JUMP_HOST:-dc2-container-xterm-011.prd.it.nvidia.com}"
JUMP_PORT="${RR_DT_JUMP_PORT:-2704}"
JUMP_USER="${RR_DT_JUMP_USER:-$(default_user)}"
JUMP_ALIAS="xterm-jump"

TARGET_HOST="${RR_DT_HOST:-rr-dt.nvidia.com}"
TARGET_USER="${RR_DT_USER:-$(default_user)}"
TARGET_ALIAS="rr-dt"

KEY="${HOME}/.ssh/id_ed25519"
CONFIG="${HOME}/.ssh/config"

# 1. Make sure a key exists.
if [[ ! -f "$KEY" ]]; then
  echo "==> No key at $KEY, generating one..."
  ssh-keygen -t ed25519 -f "$KEY" -N "" -C "${USER:-$(id -un)}@$(hostname)"
fi

# 2. Add SSH config entries (idempotent).
mkdir -p "$(dirname "$CONFIG")"
touch "$CONFIG"
chmod 600 "$CONFIG"

if ! grep -q "^Host ${JUMP_ALIAS}\$" "$CONFIG"; then
  echo "==> Adding ${JUMP_ALIAS} to $CONFIG"
  cat >> "$CONFIG" <<CFG

Host ${JUMP_ALIAS}
    HostName ${JUMP_HOST}
    Port ${JUMP_PORT}
    User ${JUMP_USER}
    IdentityFile ${KEY}
CFG
else
  echo "==> ${JUMP_ALIAS} already in $CONFIG, skipping"
fi

if ! grep -q "^Host ${TARGET_ALIAS}\$" "$CONFIG"; then
  echo "==> Adding ${TARGET_ALIAS} to $CONFIG"
  cat >> "$CONFIG" <<CFG

Host ${TARGET_ALIAS}
    HostName ${TARGET_HOST}
    User ${TARGET_USER}
    IdentityFile ${KEY}
    ProxyJump ${JUMP_ALIAS}
CFG
else
  echo "==> ${TARGET_ALIAS} already in $CONFIG, skipping"
fi

# 3. Install the public key on the jump host (prompts for jump password).
echo
echo "==> Installing key on jump host (${JUMP_ALIAS}). Enter the JUMP-HOST password when asked."
ssh-copy-id -i "${KEY}.pub" "${JUMP_ALIAS}"

# 4. Install the public key on the target, routed through the jump host.
#    The jump hop is now key-based, so you only enter the rr-dt password.
echo
echo "==> Installing key on target (${TARGET_ALIAS}). Enter the RR-DT password when asked."
ssh-copy-id -i "${KEY}.pub" "${TARGET_ALIAS}"

echo
echo "==> Done. You can now connect with:  ssh ${TARGET_ALIAS}"
