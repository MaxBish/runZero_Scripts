#!/usr/bin/env python3
"""Export runZero assets to JSON, then convert to CSV.

This script uses the runZero Export API endpoint to retrieve asset data,
persists the full JSON payload, then flattens each asset record into a CSV row.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Set, Tuple, cast

import requests

DEFAULT_BASE_URL = "https://console.runzero.com/api/v1.0/export/org/assets.json"
TOKEN_ENV_VAR = "RUNZERO_EXPORT_TOKEN"
DEFAULT_SEARCH = "type:printer"
DEFAULT_BASE_NAME = "runzero_assets"
DEFAULT_TIMEOUT_SECONDS = 120


def parse_args() -> argparse.Namespace:
	parser = argparse.ArgumentParser(
		description=(
			"Export runZero assets to JSON and CSV. By default, the script "
			"filters assets with the query 'type:printer'."
		)
	)
	parser.add_argument(
		"--search",
		default=DEFAULT_SEARCH,
		help="runZero search query. Use an empty value to export all assets.",
	)
	parser.add_argument(
		"--output-dir",
		default=None,
		help="Optional output directory. Defaults to Downloads, then Desktop.",
	)
	parser.add_argument(
		"--base-name",
		default=DEFAULT_BASE_NAME,
		help="Base filename prefix (without extension).",
	)
	parser.add_argument(
		"--timeout",
		type=int,
		default=DEFAULT_TIMEOUT_SECONDS,
		help="HTTP request timeout in seconds.",
	)
	parser.add_argument(
		"--base-url",
		default=DEFAULT_BASE_URL,
		help="runZero Export API endpoint URL.",
	)
	return parser.parse_args()


def resolve_output_dir(override_dir: str | None) -> Path:
	if override_dir:
		output = Path(override_dir).expanduser().resolve()
		output.mkdir(parents=True, exist_ok=True)
		if not os.access(output, os.W_OK):
			raise OSError(f"Output directory is not writable: {output}")
		return output

	candidates = [Path.home() / "Downloads", Path.home() / "Desktop"]
	for candidate in candidates:
		if candidate.exists() and candidate.is_dir() and os.access(candidate, os.W_OK):
			return candidate

	raise OSError("Could not find a writable Downloads or Desktop directory.")


def build_output_paths(output_dir: Path, base_name: str) -> Tuple[Path, Path]:
	timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%SZ")
	safe_base = base_name.strip() or DEFAULT_BASE_NAME
	json_path = output_dir / f"{safe_base}_{timestamp}.json"
	csv_path = output_dir / f"{safe_base}_{timestamp}.csv"
	return json_path, csv_path


def fetch_assets(base_url: str, token: str, search: str, timeout: int) -> List[Dict[str, Any]]:
	headers = {
		"Authorization": f"Bearer {token}",
		"Accept": "application/json",
	}
	params: Dict[str, str] = {}
	if search.strip():
		params["search"] = search

	response = requests.get(base_url, headers=headers, params=params, timeout=timeout)
	if response.status_code != 200:
		raise RuntimeError(
			"runZero API request failed: "
			f"HTTP {response.status_code} - {response.text[:500]}"
		)

	payload: Any = response.json()
	if isinstance(payload, list):
		assets: List[Dict[str, Any]] = []
		for item in cast(List[Any], payload):
			if isinstance(item, dict):
				assets.append(cast(Dict[str, Any], item))
		return assets

	if isinstance(payload, dict):
		payload_dict = cast(Dict[str, Any], payload)

		data_value = payload_dict.get("data")
		if isinstance(data_value, list):
			return [cast(Dict[str, Any], item) for item in cast(List[Any], data_value) if isinstance(item, dict)]

		assets_value = payload_dict.get("assets")
		if isinstance(assets_value, list):
			return [cast(Dict[str, Any], item) for item in cast(List[Any], assets_value) if isinstance(item, dict)]

	raise RuntimeError("Unexpected API response shape: expected a list of assets.")


def write_json(path: Path, assets: List[Dict[str, Any]]) -> None:
	with path.open("w", encoding="utf-8") as handle:
		json.dump(assets, handle, indent=2, ensure_ascii=False)


def flatten_asset(asset: Dict[str, Any]) -> Dict[str, Any]:
	flat: Dict[str, Any] = {}

	def _walk(value: Any, prefix: str) -> None:
		if isinstance(value, dict):
			dict_value = cast(Dict[Any, Any], value)
			for key, nested_value in dict_value.items():
				key_obj: object = cast(object, key)
				key_str = str(key_obj)
				next_prefix = f"{prefix}.{key_str}" if prefix else key_str
				_walk(nested_value, next_prefix)
			return

		if isinstance(value, list):
			flat[prefix] = json.dumps(value, ensure_ascii=False)
			return

		flat[prefix] = value

	_walk(asset, "")
	return flat


def ordered_columns(rows: List[Dict[str, Any]]) -> List[str]:
	keys: Set[str] = set()
	for row in rows:
		keys.update(row.keys())

	preferred = [
		"id",
		"address",
		"mac",
		"type",
		"site",
		"alive",
		"names",
		"first_seen",
		"last_seen",
	]

	ordered = [column for column in preferred if column in keys]
	remaining = sorted(column for column in keys if column not in ordered)
	return ordered + remaining


def normalize_csv_value(value: Any) -> Any:
	if value is None:
		return ""
	return value


def write_csv(path: Path, assets: List[Dict[str, Any]]) -> int:
	rows = [flatten_asset(asset) for asset in assets]
	if not rows:
		with path.open("w", newline="", encoding="utf-8") as handle:
			writer = csv.writer(handle)
			writer.writerow(["message"])
			writer.writerow(["No assets returned by the runZero query."])
		return 0

	columns = ordered_columns(rows)
	with path.open("w", newline="", encoding="utf-8") as handle:
		writer = csv.DictWriter(handle, fieldnames=columns, extrasaction="ignore")
		writer.writeheader()
		for row in rows:
			writer.writerow({k: normalize_csv_value(row.get(k)) for k in columns})

	return len(rows)


def main() -> int:
	args = parse_args()

	token = os.getenv(TOKEN_ENV_VAR)
	if not token:
		print(
			f"Missing {TOKEN_ENV_VAR}. Example:\n"
			f"  export {TOKEN_ENV_VAR}=\"XT-YOUR-EXPORT-TOKEN\""
		)
		return 1

	try:
		output_dir = resolve_output_dir(args.output_dir)
		json_path, csv_path = build_output_paths(output_dir, args.base_name)

		assets = fetch_assets(args.base_url, token, args.search, args.timeout)
		write_json(json_path, assets)
		csv_count = write_csv(csv_path, assets)

		print(f"Fetched {len(assets)} assets from runZero.")
		print(f"JSON written to: {json_path}")
		print(f"CSV written to:  {csv_path}")
		print(f"CSV row count:   {csv_count}")
		return 0
	except requests.RequestException as exc:
		print(f"Network error while calling runZero API: {exc}")
		return 1
	except Exception as exc:
		print(f"Error: {exc}")
		return 1


if __name__ == "__main__":
	sys.exit(main())
