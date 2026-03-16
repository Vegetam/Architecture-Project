#!/usr/bin/env bash
# Shared helpers for install/render scripts.
# shellcheck shell=bash

COMMON_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_ROOT_DIR="$(cd "${COMMON_SCRIPT_DIR}/../.." && pwd)"
VERSIONS_FILE="${COMMON_ROOT_DIR}/k8s/versions.yaml"

ensure_python3() {
  command -v python3 >/dev/null 2>&1 || {
    echo "python3 is required for this script." >&2
    exit 1
  }
}

chart_version() {
  local chart_key="$1"
  ensure_python3
  python3 - "$VERSIONS_FILE" "$chart_key" <<'PY'
import re
import sys

versions_path, chart_key = sys.argv[1:3]
inside = False
with open(versions_path, encoding="utf-8") as fh:
    for line in fh:
        if re.match(rf"^  {re.escape(chart_key)}:\s*$", line):
            inside = True
            continue
        if inside:
            match = re.match(r"^    version:\s*([^\s#]+)\s*$", line)
            if match:
                print(match.group(1))
                sys.exit(0)
            if re.match(r"^  [A-Za-z0-9_-]+:\s*$", line):
                break
print(f"Chart version not found in {versions_path}: charts.{chart_key}.version", file=sys.stderr)
sys.exit(1)
PY
}

ensure_tmp_dir() {
  if [[ -z "${TMP_WORK_DIR:-}" ]]; then
    TMP_WORK_DIR="$(mktemp -d)"
  fi
}

sanitize_path_for_temp() {
  local src="$1"
  src="${src#${COMMON_ROOT_DIR}/}"
  src="${src#./}"
  printf '%s' "$src" | tr '/.' '__'
}

render_env_file() {
  local src="$1"
  local dst="$2"
  ensure_python3
  python3 - "$src" "$dst" <<'PY'
import os
import re
import sys

src, dst = sys.argv[1:3]
pattern = re.compile(r"\$\{([A-Z0-9_]+)(:-([^}]*))?\}")
text = open(src, encoding="utf-8").read()
missing = []


def replace(match: re.Match[str]) -> str:
    name = match.group(1)
    default = match.group(3)
    value = os.environ.get(name)
    if default is not None:
        if value not in (None, ""):
            return value
        return default
    if value is not None:
        return value
    missing.append(name)
    return match.group(0)

rendered = pattern.sub(replace, text)
if missing:
    unique = ", ".join(sorted(set(missing)))
    print(f"Missing required environment variables for {src}: {unique}", file=sys.stderr)
    sys.exit(1)
with open(dst, "w", encoding="utf-8") as fh:
    fh.write(rendered)
PY
}

render_to_temp() {
  local src="$1"
  ensure_tmp_dir
  local safe_name
  safe_name="$(sanitize_path_for_temp "$src")"
  local dst="${TMP_WORK_DIR}/${safe_name}"
  render_env_file "$src" "$dst"
  printf '%s\n' "$dst"
}
