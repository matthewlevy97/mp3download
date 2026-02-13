#!/usr/bin/env bash
set -euo pipefail

# Package built binaries in `dist/` into release ZIPs including README and LICENSE
# Usage: ./scripts/package_release.sh [dist_dir]

DIST_DIR="${1:-dist}"
# Use absolute release directory so zip creation from a staging dir succeeds
RELEASE_DIR="$(pwd)/release"

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
  relname="mp3download-${fname}"
  zipname="$RELEASE_DIR/${relname}.zip"

  echo "Creating $zipname (includes README.md, LICENSE and platform ffmpeg sidecar if available)"

  # staging dir to assemble release contents
  stage=$(mktemp -d)
  # Copy files into staging; failures for this package should not abort whole run
  set +e
  cp "$f" "$stage/"
  if [ -f README.md ]; then cp README.md "$stage/"; fi
  if [ -f LICENSE ]; then cp LICENSE "$stage/"; fi
  # create vendor subdir for ffmpeg and its runtime companions
  mkdir -p "$stage/vendor"

  platform_dir=$(echo "$fname" | sed -E 's/^mp3download-//' | sed -E 's/\.exe$//')

  cp -r "assets/ffmpeg/$platform_dir/" "$stage/vendor/" 2>/dev/null || true

  # If vendor does not contain the expected ffmpeg for this release, skip creating this release.
if [ ! -f "$stage/vendor/ffmpeg" ] && [ ! -f "$stage/vendor/ffmpeg.exe" ]; then
    echo "Skipping release for $fname: no ffmpeg present" >&2
    rm -rf "$stage"
    set -e
    continue
  fi

  # create zip from staged files (strip paths). if zip fails, log and continue.
  pushd "$stage" >/dev/null
  ziplog=$(mktemp)
  if command -v zip >/dev/null 2>&1; then
    zip -r -j "$zipname" . >"$ziplog" 2>&1
    rc=$?
  else
    python3 - "$zipname" <<'PY'
import sys, zipfile, os
zf = zipfile.ZipFile(sys.argv[1], 'w', compression=zipfile.ZIP_DEFLATED)
for root, dirs, files in os.walk('.'):
    for fn in files:
        zf.write(os.path.join(root, fn), arcname=fn)
zf.close()
PY
    rc=$?
  fi
  popd >/dev/null

  if [ $rc -ne 0 ]; then
    echo "Packaging failed for $fname (zip creation error). Output:" >&2
    if [ -f "$ziplog" ]; then
      sed -n '1,200p' "$ziplog" >&2 || true
    fi
    echo "Staged directory contents:" >&2
    ls -la "$stage" >&2 || true
    # attempt python fallback if zip existed but failed
    if command -v zip >/dev/null 2>&1; then
      echo "Attempting python fallback for $fname" >&2
      set +e
      pushd "$stage" >/dev/null
      python3 - "$zipname" <<'PY'
import sys, zipfile, os
zf = zipfile.ZipFile(sys.argv[1], 'w', compression=zipfile.ZIP_DEFLATED)
for root, dirs, files in os.walk('.'):
    for fn in files:
        zf.write(os.path.join(root, fn), arcname=fn)
zf.close()
PY
      pfl_rc=$?
      popd >/dev/null
      if [ $pfl_rc -eq 0 ]; then
        echo "Python fallback succeeded for $fname"
        rm -f "$ziplog"
        rm -rf "$stage"
        set -e
        continue
      else
        echo "Python fallback also failed for $fname (rc=$pfl_rc)" >&2
      fi
      set -e
    fi
    rm -f "$ziplog"
    rm -rf "$stage"
    continue
  fi

  rm -rf "$stage"
  set -e
done

echo "Generating SHA256 checksums"
pushd "$RELEASE_DIR" >/dev/null
if ls *.zip >/dev/null 2>&1; then
  shasum -a 256 *.zip > SHA256SUMS.txt
else
  echo "No zip files created; skipping SHA256SUMS generation."
fi
popd >/dev/null

echo "Packaging complete. Artifacts in $RELEASE_DIR"
