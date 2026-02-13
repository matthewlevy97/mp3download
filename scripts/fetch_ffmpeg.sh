#!/usr/bin/env bash
set -euo pipefail

# Fetch latest FFmpeg builds from BtbN/FFmpeg-Builds GitHub releases
# Requirements: curl, jq, unzip, tar

REPO="BtbN/FFmpeg-Builds"
OUTDIR="$(pwd)/assets/ffmpeg"
TMPDIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

echo "Fetching latest release info for $REPO"
API_URL="https://api.github.com/repos/${REPO}/releases/latest"
RESP=$(curl -sL "$API_URL")

if ! command -v jq >/dev/null 2>&1; then
  echo "This script requires 'jq' (sudo apt install jq / brew install jq)" >&2
  exit 1
fi

mkdir -p "$OUTDIR"

download_asset() {
  local pattern="$1"
  local target_dir="$2"

  echo "Looking for asset matching pattern: $pattern"
  url=$(echo "$RESP" | jq -r --arg pat "$pattern" '.assets[] | select(.name|test($pat; "i")) | .browser_download_url' | head -n1)
  if [ -z "$url" ] || [ "$url" = "null" ]; then
    echo "No matching asset found for pattern: $pattern" >&2
    return 1
  fi

  download_and_install "$url" "$target_dir"
}

download_and_install() {
  local url="$1"
  local target_dir="$2"

  out="$TMPDIR/asset"
  echo "Downloading: $url -> $out"
  curl -L -o "$out" "$url"

  mkdir -p "$OUTDIR/$target_dir"

  # Extract and find ffmpeg binary
  mkdir -p "$TMPDIR/extracted"
  case "$url" in
    *.zip)
      unzip -q "$out" -d "$TMPDIR/extracted"
      ;;
    *.tar.xz|*.tar.gz|*.tgz)
      tar -xf "$out" -C "$TMPDIR/extracted"
      ;;
    *)
      cp "$out" "$TMPDIR/extracted/"
      ;;
  esac

  ff=$(find "$TMPDIR/extracted" -type f -iname 'ffmpeg' -o -iname 'ffmpeg.exe' | head -n1 || true)
  if [ -z "$ff" ]; then
    # Sometimes binaries are under bin/ffmpeg
    ff=$(find "$TMPDIR/extracted" -type f -iname '*ffmpeg*' | head -n1 || true)
  fi

  if [ -z "$ff" ]; then
    echo "ffmpeg binary not found inside archive: $url" >&2
    return 2
  fi

  echo "Found ffmpeg binary: $ff"
  cp "$ff" "$OUTDIR/$target_dir/ffmpeg"
  chmod +x "$OUTDIR/$target_dir/ffmpeg"
  echo "Installed to $OUTDIR/$target_dir/ffmpeg"
}

echo "Creating output folders"
mkdir -p "$OUTDIR"

# Map targets to search patterns
download_asset "win64|windows.*64" "windows-amd64" || true
download_asset "linux.*(amd64|x86_64|64)" "linux-amd64" || true

echo "Fetch complete. Check $OUTDIR for installed ffmpeg binaries."
