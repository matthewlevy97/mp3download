#!/usr/bin/env bash
set -euo pipefail

# Package built binaries in `dist/` into release ZIPs including README and LICENSE
# Usage: ./scripts/package_release.sh [dist_dir]

DIST_DIR="${1:-dist}"
RELEASE_DIR="release"

if [ ! -d "$DIST_DIR" ]; then
  echo "Dist directory '$DIST_DIR' not found. Build first (make build or make build-linux-amd64)." >&2
  exit 1
fi

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

echo "Packaging binaries from $DIST_DIR into $RELEASE_DIR"

for f in "$DIST_DIR"/*; do
  [ -f "$f" ] || continue
  fname=$(basename "$f")
  # derive a release name
  relname="mp3download-${fname}"
  # ensure .exe extension included in filename for windows
  zipname="$RELEASE_DIR/${relname}.zip"

  echo "Creating $zipname (includes README.md and LICENSE if present)"
  files_to_add=("$f")
  [ -f README.md ] && files_to_add+=("README.md")
  [ -f LICENSE ] && files_to_add+=("LICENSE")

  # create the zip (strip paths)
  if command -v zip >/dev/null 2>&1; then
    zip -j "$zipname" "${files_to_add[@]}" >/dev/null
  else
    # fallback to using python to create zip
    python3 - <<PY
import sys, zipfile
zf = zipfile.ZipFile(sys.argv[1], 'w', compression=zipfile.ZIP_DEFLATED)
for fn in sys.argv[2:]:
    zf.write(fn, arcname=fn.split('/')[-1])
zf.close()
PY
    "$zipname" "${files_to_add[@]}"
  fi
done

echo "Generating SHA256 checksums"
pushd "$RELEASE_DIR" >/dev/null
shasum -a 256 *.zip > SHA256SUMS.txt
popd >/dev/null

echo "Packaging complete. Artifacts in $RELEASE_DIR"
