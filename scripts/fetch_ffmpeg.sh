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
  mkdir -p "$TMPDIR/extracted/$target_dir"
  case "$url" in
    *.zip)
      unzip -q "$out" -d "$TMPDIR/extracted/$target_dir"
      ;;
    *.tar.xz|*.tar.gz|*.tgz)
      tar -xf "$out" -C "$TMPDIR/extracted/$target_dir"
      ;;
    *)
      cp "$out" "$TMPDIR/extracted/$target_dir/"
      ;;
  esac

  # Prefer an exact ffmpeg file; use grouped predicates and return first match
  ff=$(find "$TMPDIR/extracted/$target_dir" -type f \( -iname 'ffmpeg' -o -iname 'ffmpeg.exe' \) -print -quit || true)
  if [ -z "$ff" ]; then
    echo "ffmpeg binary not found inside archive: $url" >&2
    return 2
  fi

  echo "Found ffmpeg binary: $ff"
  ffbase=$(basename "$ff")

  # Validate that the discovered binary matches the requested target platform.
  # Prevent installing a Windows binary into linux assets (and vice-versa).
  if [[ "$target_dir" == windows* ]]; then
    if [[ "$ffbase" != *.exe ]]; then
      echo "Discovered ffmpeg ($ffbase) is not a Windows .exe but target is $target_dir — skipping install." >&2
      return 2
    fi
  else
    # non-windows targets should not receive .exe binaries
    if [[ "$ffbase" == *.exe ]]; then
      echo "Discovered ffmpeg ($ffbase) appears to be a Windows binary but target is $target_dir — skipping install." >&2
      return 2
    fi
  fi
  # preserve .exe for Windows targets or when the discovered binary has .exe
  # destname already inferred above as ffbase extension matches target
  destname="ffmpeg"
  if [[ "$ffbase" == *.exe ]]; then
    destname="ffmpeg.exe"
  fi
  mkdir -p "$OUTDIR/$target_dir"
  cp "$ff" "$OUTDIR/$target_dir/$destname"
  chmod +x "$OUTDIR/$target_dir/$destname"

  # Copy sibling runtime files that are relevant for the target platform only.
  # Avoid copying Windows DLLs into linux assets and vice-versa.
  srcdir=$(dirname "$(dirname "$ff")")
  echo "Copying companion files from $srcdir to $OUTDIR/$target_dir"
  for s in $srcdir/bin/* $srcdir/lib/*; do
    [ -f "$s" ] || continue
    name=$(basename "$s")
    # skip the ffmpeg we already copied (different name)
    if [ "$name" = "$ffbase" ]; then
      continue
    fi

    copy_it=0
    # Determine allowed companion extensions per platform
    if [[ "$target_dir" == windows* ]]; then
      case "$name" in
        *.dll|*.exe|ffprobe.exe|ffplay.exe|ffprobe|ffplay)
          copy_it=1;;
      esac
    elif [[ "$target_dir" == linux* ]]; then
      case "$name" in
        *.so|ffprobe|ffplay)
          copy_it=1;;
      esac
    elif [[ "$target_dir" == darwin* || "$target_dir" == mac* || "$target_dir" == osx* ]]; then
      case "$name" in
        *.dylib|ffprobe|ffplay)
          copy_it=1;;
      esac
    else
      # default: copy typical helpers and shared libs
      case "$name" in
        *.dll|*.so|*.dylib|ffprobe|ffplay|*.exe)
          copy_it=1;;
      esac
    fi

    if [ "$copy_it" -eq 1 ]; then
      cp "$s" "$OUTDIR/$target_dir/" 2>/dev/null || true
      chmod +x "$OUTDIR/$target_dir/$name" || true
      echo "  - copied $name"
    else
      # skip unrelated files
      :
    fi
  done

  echo "Installed to $OUTDIR/$target_dir/ (ffmpeg + companions)"
}

echo "Creating output folders"
mkdir -p "$OUTDIR"

# Map targets to search patterns
download_asset "win64|windows.*64" "windows-amd64" || true
download_asset "linux.*(amd64|x86_64|64)" "linux-amd64" || true

echo "Fetch complete. Check $OUTDIR for installed ffmpeg binaries."
