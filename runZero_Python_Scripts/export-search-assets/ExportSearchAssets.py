#!/usr/bin/env python3
"""Export all runZero assets matching a search query to JSON and CSV files.

Uses the runZero export endpoints (GET /export/org/assets.json and assets.csv),
which return every matching asset without pagination.

Requires an organization API token in the RUNZERO_ORG_TOKEN environment variable.

Usage:
    python3 ExportSearchAssets.py 'os:windows and alive:t'
    python3 ExportSearchAssets.py 'type:server' --output-dir ~/Desktop --name servers
"""

import argparse
import csv
import os
import re
import sys
from datetime import datetime
from pathlib import Path

import requests

DEFAULT_BASE_URL = "https://console.runzero.com/api/v1.0"
REQUEST_TIMEOUT_SECONDS = 900
CHUNK_SIZE = 1024 * 1024


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Export runZero assets matching a search query to JSON and CSV."
    )
    parser.add_argument("search", help="runZero asset search query, e.g. 'os:windows'")
    parser.add_argument("--output-dir", default="~/Downloads",
                        help="Directory to write files to (default: ~/Downloads)")
    parser.add_argument("--name", default="",
                        help="Base filename (default: runzero_assets_<timestamp>)")
    parser.add_argument("--fields", default="",
                        help="Optional comma-separated list of asset fields to include")
    parser.add_argument("--base-url", default=os.getenv("RUNZERO_BASE_URL", DEFAULT_BASE_URL),
                        help=f"runZero API base URL (default: {DEFAULT_BASE_URL})")
    return parser.parse_args()


def download(session: requests.Session, url: str, params: dict, destination: Path) -> None:
    with session.get(url, params=params, stream=True, timeout=REQUEST_TIMEOUT_SECONDS) as response:
        if response.status_code == 401:
            sys.exit("ERROR: Unauthorized - check that RUNZERO_ORG_TOKEN is set and valid.")
        if response.status_code != 200:
            sys.exit(f"ERROR: {url} returned {response.status_code}: {response.text[:500]}")

        tmp_path = destination.with_suffix(destination.suffix + ".part")
        with open(tmp_path, "wb") as handle:
            for chunk in response.iter_content(chunk_size=CHUNK_SIZE):
                handle.write(chunk)
        tmp_path.replace(destination)


def main() -> None:
    args = parse_args()

    token = os.getenv("RUNZERO_ORG_TOKEN")
    if not token:
        sys.exit("ERROR: Missing RUNZERO_ORG_TOKEN environment variable.")

    output_dir = Path(args.output_dir).expanduser()
    output_dir.mkdir(parents=True, exist_ok=True)

    base_name = args.name or f"runzero_assets_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    # Keep user-supplied names from escaping the output directory.
    base_name = re.sub(r"[^A-Za-z0-9._-]", "_", Path(base_name).name)

    params = {"search": args.search}
    if args.fields:
        params["fields"] = args.fields

    session = requests.Session()
    session.headers.update({"Authorization": f"Bearer {token}"})
    base_url = args.base_url.rstrip("/")

    json_path = output_dir / f"{base_name}.json"
    csv_path = output_dir / f"{base_name}.csv"

    print(f"Search: {args.search}")
    download(session, f"{base_url}/export/org/assets.json", params, json_path)
    print(f"Wrote {json_path}")
    download(session, f"{base_url}/export/org/assets.csv", params, csv_path)
    print(f"Wrote {csv_path}")

    csv.field_size_limit(sys.maxsize)
    with open(csv_path, "r", encoding="utf-8", errors="replace", newline="") as handle:
        row_count = max(sum(1 for _ in csv.reader(handle)) - 1, 0)
    print(f"Exported {row_count} assets.")


if __name__ == "__main__":
    main()
