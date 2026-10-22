#!/usr/bin/env python3
"""
Download rrLog files from the DCS host and optionally analyze the crash with Claude.

Usage:
    download_rrlog.py <job_id> <test_id> [--commit <commit_hash>] [--analyze]

Example:
    download_rrlog.py 019c33de-136e-76ff-06fb-76a0729adfdd 019c33dd-88a5-1366-05dd-2f66c3b9bb90
    download_rrlog.py 019c33de-136e-76ff-06fb-76a0729adfdd 019c33dd-88a5-1366-05dd-2f66c3b9bb90 --commit abc123def --analyze

Settings come from the environment or from the .env file next to this script
(see .env.example): DCS_SSH_HOST, DCS_SSH_USER (or SSH_USER), DCS_SSH_PASSWORD,
RRLOG_LOCAL_DIR, NDAS_WORKSPACE, RRLOG_DOC_PATH. Without a password the SSH
agent and ~/.ssh keys are used.
"""

import argparse
import getpass
import os
import shutil
import subprocess
import sys
from pathlib import Path


def load_env(env_file=Path(__file__).resolve().parent / ".env"):
    """Load KEY=VALUE lines from .env; variables already in the environment win."""
    if not env_file.is_file():
        return
    for raw in env_file.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        if line.startswith("export "):
            line = line[len("export "):]
        key, value = line.split("=", 1)
        key, value = key.strip(), value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        if key.isidentifier():
            os.environ.setdefault(key, value)


def path_setting(name, default):
    return os.path.expanduser(os.path.expandvars(os.environ.get(name, default)))


load_env()

# Configuration
REMOTE_HOST = os.environ.get("DCS_SSH_HOST", "dcs-sh01.nvidia.com")
REMOTE_USER = os.environ.get("DCS_SSH_USER") or os.environ.get("SSH_USER") or getpass.getuser()
REMOTE_PASSWORD = os.environ.get("DCS_SSH_PASSWORD") or None  # None -> SSH agent / keys
REMOTE_TMP_DIR = "/tmp"

LOCAL_RRLOG_DIR = path_setting("RRLOG_LOCAL_DIR", "~/Downloads/claude_rrLog/rrLog")
LOCAL_WORKSPACE = path_setting("NDAS_WORKSPACE", "~/workspace/ndas")
LOCAL_DOC_PATH = path_setting(
    "RRLOG_DOC_PATH", "~/Downloads/claude_rrLog/ComputeGraphFrameworkDocumentation.docx"
)


def import_ssh_libs():
    """Import paramiko and scp, installing them on first use."""
    global paramiko, SCPClient
    try:
        import paramiko
        from scp import SCPClient
    except ImportError:
        print("Required packages not found. Installing...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", "paramiko", "scp"])
        import paramiko
        from scp import SCPClient


def create_ssh_client(host, user, password):
    """Create and return an SSH client connected to the remote host."""
    auth = "password" if password else "SSH keys/agent"
    print(f"Connecting to {user}@{host} ({auth})...")
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(host, username=user, password=password)
    print("Connected successfully.")
    return client


def execute_remote_command(ssh_client, command, timeout=600):
    """Execute a command on the remote host and wait for completion."""
    print(f"Executing: {command}")
    stdin, stdout, stderr = ssh_client.exec_command(command, timeout=timeout)

    # Wait for command to complete
    exit_status = stdout.channel.recv_exit_status()

    stdout_text = stdout.read().decode('utf-8')
    stderr_text = stderr.read().decode('utf-8')

    if stdout_text:
        print(f"STDOUT:\n{stdout_text}")
    if stderr_text:
        print(f"STDERR:\n{stderr_text}")

    return exit_status, stdout_text, stderr_text


def clean_local_directory(directory):
    """Clean up the local directory before downloading."""
    print(f"Cleaning up local directory: {directory}")
    if os.path.exists(directory):
        shutil.rmtree(directory)
    os.makedirs(directory, exist_ok=True)
    print("Local directory cleaned.")


def download_directory(ssh_client, remote_path, local_path):
    """Download a directory from remote to local using SCP."""
    print(f"Downloading {remote_path} to {local_path}...")

    with SCPClient(ssh_client.get_transport()) as scp:
        scp.get(remote_path, local_path, recursive=True)

    print("Download completed.")


def run_claude_analysis(commit=None):
    """Run Claude to analyze the crash.

    Args:
        commit: Optional commit hash to analyze the code at a specific point in time.
    """
    print("Running Claude analysis...")

    if commit:
        prompt = (
            f'The crash occurred at commit: {commit}. '
            f'First, checkout to this commit using "git checkout {commit}" to analyze the code at that point. '
            f'Reading the document: {LOCAL_DOC_PATH}, '
            f'I encountered a crash. The log is located at: {LOCAL_RRLOG_DIR}. '
            f'Analyze the crash reason based on the code at commit {commit}, '
            f'find the commit that introduced this crash, '
            f'and share the fix solution. '
            f'After analysis, remember to checkout back to the original branch.'
        )
    else:
        prompt = (
            f'Based on the current code repo, reading the document: {LOCAL_DOC_PATH}, '
            f'I encountered a crash. The log is located at: {LOCAL_RRLOG_DIR}. '
            f'Analyze the crash reason, find the commit that introduced this crash, '
            f'and share the fix solution.'
        )

    cmd = ["claude", "--allow-dangerously-skip-permissions", "-p", prompt]

    print(f"Executing: {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=LOCAL_WORKSPACE)

    return result.returncode


def main():
    parser = argparse.ArgumentParser(
        description="Download rrLog files and optionally analyze crashes with Claude"
    )
    parser.add_argument("job_id", help="Job ID (e.g., 019c33de-136e-76ff-06fb-76a0729adfdd)")
    parser.add_argument("test_id", help="Test ID (e.g., 019c33dd-88a5-1366-05dd-2f66c3b9bb90)")
    parser.add_argument("--commit", "-c", help="Git commit hash when the crash occurred (for accurate code analysis)")
    parser.add_argument("--analyze", action="store_true",
                        help=f"After downloading, run Claude in {LOCAL_WORKSPACE} to analyze the crash")

    args = parser.parse_args()

    job_id = args.job_id
    test_id = args.test_id

    print(f"Job ID: {job_id}")
    print(f"Test ID: {test_id}")
    if args.commit:
        print(f"Commit: {args.commit}")
    print("-" * 60)

    import_ssh_libs()
    ssh_client = None
    try:
        # Step 1: Connect to remote machine
        ssh_client = create_ssh_client(REMOTE_HOST, REMOTE_USER, REMOTE_PASSWORD)

        # Step 2: Check if artifacts already exist, if not download them
        base_path = f"{REMOTE_TMP_DIR}/{job_id}/{test_id}"
        check_cmd = f"test -d {base_path} && echo 'EXISTS' || echo 'NOT_EXISTS'"
        _, stdout_text, _ = execute_remote_command(ssh_client, check_cmd)

        if "NOT_EXISTS" in stdout_text:
            print(f"Artifacts not found, downloading...")
            artifact_id = f"{job_id}:{test_id}"
            maglev_cmd = f"maglev ts jobs artifacts {artifact_id} --download {REMOTE_TMP_DIR}/"

            exit_status, _, _ = execute_remote_command(ssh_client, maglev_cmd, timeout=600)
            if exit_status != 0:
                print(f"Warning: maglev command exited with status {exit_status}")

        else:
            print(f"Artifacts already exist at {base_path}, skipping download.")

        # Step 3: Find the output folder dynamically
        # Path structure: /tmp/{job_id}/{test_id}/{sub_id}/exec-XXX-REPLAYER_TYPE_*/output/
        find_cmd = f"find {base_path} -type d -name 'output' 2>/dev/null | head -1"
        exit_status, stdout_text, _ = execute_remote_command(ssh_client, find_cmd)

        remote_output_path = stdout_text.strip()
        if not remote_output_path:
            print(f"Error: Output folder not found under {base_path}")
            print("Listing directory structure for debugging:")
            execute_remote_command(ssh_client, f"find {base_path} -type d 2>/dev/null")
            sys.exit(1)

        print(f"Found output folder: {remote_output_path}")

        # Step 4: Clean local directory and download
        clean_local_directory(LOCAL_RRLOG_DIR)
        download_directory(ssh_client, remote_output_path, LOCAL_RRLOG_DIR)

        # Move contents from output subfolder to rrLog if needed
        downloaded_output = os.path.join(LOCAL_RRLOG_DIR, "output")
        if os.path.exists(downloaded_output):
            for item in os.listdir(downloaded_output):
                src = os.path.join(downloaded_output, item)
                dst = os.path.join(LOCAL_RRLOG_DIR, item)
                shutil.move(src, dst)
            os.rmdir(downloaded_output)

        print(f"Files downloaded to: {LOCAL_RRLOG_DIR}, pwd: {os.getcwd()}")
        print("-" * 60)

        # Step 5 & 6: Change to workspace and run Claude analysis
        if args.analyze:
            os.chdir(LOCAL_WORKSPACE)
            print(f"Changed to directory: {LOCAL_WORKSPACE}")
            if args.commit:
                print(f"Analyzing code at commit: {args.commit}")
            run_claude_analysis(commit=args.commit)
        else:
            print("Skipping Claude analysis (pass --analyze to run it)")

    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)
    finally:
        if ssh_client:
            ssh_client.close()
            print("SSH connection closed.")


if __name__ == "__main__":
    main()
