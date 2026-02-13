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

  # Attempt to include a platform ffmpeg sidecar. Priority:
  # 1) dist sibling (e.g. dist/ffmpeg or dist/ffmpeg.exe)
  # 2) assets/ffmpeg/<dir> where <dir> matches the binary name
  # 3) any assets/ffmpeg/* candidate (prefer exact exe name for windows)

  ffname="ffmpeg"
  if [[ "$fname" == *.exe ]] || [[ "$fname" == *windows* ]] || [[ "$fname" == *win* ]]; then
    ffname="ffmpeg.exe"
  fi

  # check dist sibling
  if [ -f "$DIST_DIR/$ffname" ]; then
    echo "Including ffmpeg from $DIST_DIR/$ffname"
    cp "$DIST_DIR/$ffname" "$stage/$ffname"
    chmod +x "$stage/$ffname" || true
  else
    # search assets for a matching ffmpeg
    found=""
    if [ -d "assets/ffmpeg" ]; then
      for d in assets/ffmpeg/*; do
        [ -d "$d" ] || continue
        b=$(basename "$d")
        # prefer directory name that appears in the binary name
        if [[ "$fname" == *"$b"* ]]; then
          cand="$d/$ffname"
          if [ -f "$cand" ]; then
            found="$cand"
            break
          fi
        fi
      done
      # fallback: pick first available candidate matching ffname
      if [ -z "$found" ]; then
        for d in assets/ffmpeg/*; do
          cand="$d/$ffname"
          if [ -f "$cand" ]; then
            found="$cand"
            break
          fi
        done
      fi
    fi

    if [ -n "$found" ]; then
      echo "Including ffmpeg from $found"
      cp "$found" "$stage/$ffname"
      chmod +x "$stage/$ffname" || true
    else
      echo "No platform ffmpeg found for $fname (not including sidecar)"
    fi
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
