#!/usr/bin/env python3
"""
Recursively download an HTTP directory listing, for example a SIL rrLog folder.

Usage:
    pull_sil_rrlogs.py <directory_url> [-o OUTPUT_DIR]

Example:
    pull_sil_rrlogs.py "https://pdx.s8k.io/v1/AUTH_team-dsps/sim_work_flows/SIL-Dev/356/<test>/1/output/<timestamp>/<test>/rrLog/"

Requires: pip install requests beautifulsoup4
"""

import argparse
import os
import sys
from urllib.parse import urljoin, urlparse


def download_file(url, output_dir):
    import requests

    local_filename = os.path.join(output_dir, os.path.basename(urlparse(url).path))
    with requests.get(url, stream=True) as r:
        r.raise_for_status()
        with open(local_filename, 'wb') as f:
            for chunk in r.iter_content(chunk_size=8192000):
                f.write(chunk)
    return local_filename


def download_directory(url, output_dir):
    import requests
    from bs4 import BeautifulSoup

    response = requests.get(url)
    response.raise_for_status()

    soup = BeautifulSoup(response.text, 'html.parser')
    for link in soup.find_all('a'):
        href = link.get('href')
        if href not in (None, '', '../'):
            full_url = urljoin(url, href)
            if full_url.endswith('/'):
                # Create a directory in the output_dir
                new_dir = os.path.join(output_dir, os.path.basename(href.rstrip('/')))
                os.makedirs(new_dir, exist_ok=True)
                # Recursive call for directories
                download_directory(full_url, new_dir)
            else:
                # Download file directly into output_dir
                print(f"Downloading {full_url}")
                download_file(full_url, output_dir)


def download_all(url, output_dir):
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
    download_directory(url, output_dir)


def main():
    parser = argparse.ArgumentParser(
        description="Recursively download an HTTP directory listing (e.g. a SIL rrLog folder)."
    )
    parser.add_argument("url", help="URL of the directory listing; a trailing slash is added if missing")
    parser.add_argument("-o", "--output", default="~/Downloads/SIL",
                        help="local output directory (default: ~/Downloads/SIL)")
    args = parser.parse_args()

    try:
        import requests  # noqa: F401
        import bs4  # noqa: F401
    except ImportError as exc:
        sys.exit(f"Missing dependency ({exc.name}). Install with: pip install requests beautifulsoup4")

    url = args.url if args.url.endswith("/") else args.url + "/"
    output_dir = os.path.expanduser(args.output)
    download_all(url, output_dir)
    print(f"Done. Files saved under {output_dir}")


if __name__ == "__main__":
    main()
