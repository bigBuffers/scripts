#!/usr/bin/env bash
#
# Download the rrLog output of a Maglev job from the DCS host to this machine.
#
# Usage:   download_rrlog <job_id> <test_id>
# Example: download_rrlog 019c9f65-10a9-7b57-00ec-69e469b73f62 019c994f-7599-1a1e-05d6-61421e8e3299
#
# The remote output path structure is:
#   /tmp/<job_id>/<test_id>/<exec_id>/exec-XXX-REPLAYER_TYPE_*/output
#
# Settings (environment or .env, see .env.example):
#   DCS_SSH_HOST, DCS_SSH_USER (or SSH_USER), DCS_SSH_PASSWORD (empty = SSH keys),
#   RRLOG_LOCAL_DIR (default ~/Downloads/claude_rrLog/rrLog; emptied before download)

# Find the checkout (this file may be a symlink in ~/.local/bin) and load lib + .env.
self="${BASH_SOURCE[0]}"
while [[ -L "$self" ]]; do
    link="$(readlink "$self")"
    case "$link" in /*) self="$link" ;; *) self="$(dirname "$self")/$link" ;; esac
done
. "$(cd "$(dirname "$self")" && pwd)/lib/common.sh"

# Check for required arguments
if [ $# -lt 2 ]; then
    echo "Usage: $0 <job_id> <test_id>"
    echo "Example: $0 019c9f65-10a9-7b57-00ec-69e469b73f62 019c994f-7599-1a1e-05d6-61421e8e3299"
    exit 1
fi

# Configuration
REMOTE_USER="${DCS_SSH_USER:-$(default_user)}"
REMOTE_HOST="${DCS_SSH_HOST:-dcs-sh01.nvidia.com}"
JOB_ID_1="$1"
JOB_ID_2="$2"
JOB_ID="${JOB_ID_1}:${JOB_ID_2}"
REMOTE_TMP_PATH="/tmp"
LOCAL_RRLOG_DIR="${RRLOG_LOCAL_DIR:-$HOME/Downloads/claude_rrLog/rrLog}"

# Use sshpass only when a password is configured; otherwise rely on SSH keys / agent.
if [ -n "${DCS_SSH_PASSWORD:-}" ]; then
    need_cmd sshpass "Install it (macOS: brew install hudochenkov/sshpass/sshpass) or leave DCS_SSH_PASSWORD empty to use SSH keys."
    export SSHPASS="$DCS_SSH_PASSWORD"
    SSH=(sshpass -e ssh)
    SCP=(sshpass -e scp)
else
    SSH=(ssh)
    SCP=(scp)
fi

echo "=== rrLog Download Script ==="
echo ""

# Step 1 & 2: SSH to remote machine and download artifacts
echo "[Step 1-2] Connecting to remote machine and downloading artifacts..."
echo "  Remote: ${REMOTE_USER}@${REMOTE_HOST}"
echo "  Job ID: ${JOB_ID}"
echo ""

# Download artifacts and find the output path
# Pass arguments to the remote script using bash -s
REMOTE_OUTPUT_PATH=$("${SSH[@]}" -o StrictHostKeyChecking=no "${REMOTE_USER}@${REMOTE_HOST}" bash -s -- "$JOB_ID_1" "$JOB_ID_2" << 'ENDSSH'
    JOB_ID_1="$1"
    JOB_ID_2="$2"
    JOB_ID="${JOB_ID_1}:${JOB_ID_2}"
    REMOTE_TMP_PATH="/tmp"
    REMOTE_BASE_PATH="${REMOTE_TMP_PATH}/${JOB_ID_1}/${JOB_ID_2}"

    echo "Connected to remote machine" >&2
    echo "Executing: maglev ts jobs artifacts ${JOB_ID} --download ${REMOTE_TMP_PATH}/" >&2
    maglev ts jobs artifacts ${JOB_ID} --download ${REMOTE_TMP_PATH}/ >&2
    echo "Download completed on remote machine" >&2

    # Find the output folder dynamically
    # Path structure: /tmp/<job_id>/<test_id>/<exec_id>/exec-XXX-REPLAYER_TYPE_*/output
    OUTPUT_PATH=$(find "${REMOTE_BASE_PATH}" -type d -name "output" -path "*/exec-*" 2>/dev/null | head -1)

    if [ -z "$OUTPUT_PATH" ]; then
        # Fallback: check for simple output path
        if [ -d "${REMOTE_BASE_PATH}/output" ]; then
            OUTPUT_PATH="${REMOTE_BASE_PATH}/output"
        fi
    fi

    if [ -n "$OUTPUT_PATH" ] && [ -d "$OUTPUT_PATH" ]; then
        echo "Output folder found: $OUTPUT_PATH" >&2
        ls -la "$OUTPUT_PATH" >&2
        # Return the path to stdout
        echo "$OUTPUT_PATH"
    else
        echo "ERROR: Output folder not found!" >&2
        echo "Checking what exists under ${REMOTE_BASE_PATH}..." >&2
        find "${REMOTE_BASE_PATH}" -type d 2>/dev/null | head -20 >&2
        exit 1
    fi
ENDSSH
)

if [ $? -ne 0 ] || [ -z "$REMOTE_OUTPUT_PATH" ]; then
    echo "Error: Failed to find output folder on remote machine"
    exit 1
fi

echo ""
echo "[Step 3] Remote download completed."
echo "  Output folder: ${REMOTE_OUTPUT_PATH}"
echo ""

# Step 4: Clean up local folder and download output
echo "[Step 4] Preparing local directory..."
echo "  Cleaning up: ${LOCAL_RRLOG_DIR}"

# Create parent directory if it doesn't exist
mkdir -p "$(dirname "${LOCAL_RRLOG_DIR}")"
chmod -R 777 "$(dirname "${LOCAL_RRLOG_DIR}")" 2>/dev/null || true

# Clean up the local rrLog folder
if [ -d "${LOCAL_RRLOG_DIR}" ]; then
    rm -rf "${LOCAL_RRLOG_DIR}"
    echo "  Cleaned up existing folder"
fi
mkdir -p "${LOCAL_RRLOG_DIR}"

echo "  Downloading output from remote to local..."
"${SCP[@]}" -r -o StrictHostKeyChecking=no \
    "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_OUTPUT_PATH}/*" \
    "${LOCAL_RRLOG_DIR}/"

if [ $? -ne 0 ]; then
    echo "Error: Failed to download files from remote machine"
    exit 1
fi

# Set permissions to 777
chmod -R 777 "${LOCAL_RRLOG_DIR}" 2>/dev/null || true

echo "  Download completed to: ${LOCAL_RRLOG_DIR}"
echo "  Contents:"
ls -la "${LOCAL_RRLOG_DIR}"
echo ""

echo ""
echo "=== Download completed ==="
echo "rrLog downloaded to: ${LOCAL_RRLOG_DIR}"
