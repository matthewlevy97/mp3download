# MP3Download

Small CLI tool to download audio from a YouTube URL and convert it to an
iPod-friendly MP3. The program prefers a sidecar `ffmpeg` next to the
executable or a system `ffmpeg` on `PATH`. Embedding of ffmpeg into the
Go binary is intentionally disabled; release zips include a platform
`ffmpeg` sidecar when available.

Quick usage
-----------

Fetch ffmpeg assets (optional), build, then run (example macOS):

```bash
make fetch-ffmpeg    # populates assets/ffmpeg/<platform>/
make build
# run the built binary (pick the correct file from dist/)
./dist/mp3download-darwin-amd64 -url "https://www.youtube.com/watch?v=..." -o song.mp3
```

If you prefer to run without building first for quick testing:

```bash
go run . -url "https://www.youtube.com/watch?v=..." -o song.mp3
```

ffmpeg sidecars and packaging
-----------------------------

This project ships release ZIPs that include a platform `ffmpeg` sidecar when
one is available in `assets/ffmpeg/<platform>/`. The runtime behavior is:

- If an `ffmpeg` (or `ffmpeg.exe` on Windows) is found next to the
	executable, it is used.
- Else if a system `ffmpeg` is on `PATH`, the system binary is used.
- Else the program exits with an instructive error asking you to provide
	a sidecar or install `ffmpeg` on `PATH`.

The helper `scripts/fetch_ffmpeg.sh` can download prebuilt FFmpeg archives and
install the platform binary and companion runtime files into
`assets/ffmpeg/<platform>/`. Important details:

- Windows binaries are installed as `ffmpeg.exe` and the script preserves the
	`.exe` extension.
- Companion runtime files (DLLs on Windows, `.so` on Linux, `.dylib` on macOS)
	are copied from the archive's ffmpeg folder into the same `assets/...`
	directory so release zips include required libraries.
- The script filters companion files by target platform to avoid mixing
	Windows DLLs into Linux folders and vice-versa.

When building locally or in CI, ensure `assets/ffmpeg/<platform>/` contains
the appropriate files before running `go build` or packaging steps. The
repository's `Makefile` provides `make fetch-ffmpeg` and `make dist` targets
to automate fetch+package.

Using a system `ffmpeg`
-----------------------

If a suitable `ffmpeg` is available on the system `PATH`, the program will
prefer that binary and skip extracting the embedded `ffmpeg`. Using a
preinstalled system `ffmpeg` is recommended for faster startup and reduced
disk usage — especially when processing large batches.

To check which `ffmpeg` will be used:

```bash
which ffmpeg || echo "no system ffmpeg found; embedded copy will be used if provided"
```

Performance and tuning
----------------------

This tool passes a few ffmpeg flags tuned for performance by default:

- `-threads N` where `N` is the number of logical CPUs (the encoder will
	utilize multiple threads where possible).
- `-nostdin` to avoid blocking on stdin.
- `-hide_banner -loglevel warning` to reduce console output noise.

For large batches consider:

- Installing a recent system `ffmpeg` (static build) and ensuring it's on
	your `PATH` so it's reused for each job instead of extracting an embedded
	copy.
- Increasing `-concurrency` (CLI flag) to tune the number of parallel
	download/convert workers. Keep in mind conversion is CPU-bound — if you
	see CPU saturation, lower concurrency or run conversions on a machine with
	more cores.
- Running the program where temporary storage is fast (SSD or tmpfs) to avoid
	disk I/O bottlenecks.

Encoding profile (iPod Nano 7th gen)
-----------------------------------

This tool encodes MP3s using parameters tuned for compatibility with iPod Nano
7th gen devices:

- Codec: `libmp3lame`
- Bitrate: 128 kbps (CBR)
- Sample rate: 44.1 kHz
- Channels: Stereo
- ID3 version: ID3v2.3 (widely supported)

These settings strike a balance between quality and device compatibility.

Transferring MP3s to an iPod Nano 7th gen
----------------------------------------

The simplest and most reliable method is to use the platform's music manager
(Finder on modern macOS, or iTunes on older macOS/Windows). Alternative tools
exist for Linux.

macOS (recommended)

1. Connect the iPod Nano via USB/Lightning.
2. Open Finder (or iTunes on older macOS). Select the connected iPod device.
3. Under the device's settings, enable "Manually manage music" (if available).
4. Drag and drop `song.mp3` from Finder into the device's Music area.
5. Eject the device before disconnecting.

Windows

1. Install and open iTunes.
2. Connect the iPod Nano via USB.
3. In iTunes select the device and enable "Manually manage music and videos".
4. Drag the MP3(s) onto the device in iTunes and eject when finished.

Linux (advanced)

The iPod Nano is not fully supported as a drop-in device on Linux by default.
Recommended approach is to use `gtkpod` or `rhythmbox` which understand the
iPod database format and will update the device's music database when syncing.

Example (gtkpod):

```bash
sudo apt install gtkpod    # or use your distro's package manager
gtkpod
# Import the MP3 and sync to the connected iPod
```

If the iPod mounts as a USB mass-storage device (shows under `/Volumes` or
`/media`), you can copy files directly, but many iPod models require their
database updated by a manager app — plain file copy may not make tracks
visible to the iPod's UI.

Practical command-line copy (only if the device supports simple file copy):

```bash
# macOS example when iPod mounts at /Volumes/IPOD
cp song.mp3 /Volumes/IPOD/Music/
sync
```

Troubleshooting
---------------

- If `make build` or `make dist` fails, run `make fetch-ffmpeg` to populate
	`assets/ffmpeg/`, or place platform-specific ffmpeg files manually.
- If release zips don't include a platform `ffmpeg`, verify that
	`assets/ffmpeg/<platform>/ffmpeg` (or `ffmpeg.exe` on Windows) exists and
	that companion runtime files (DLLs/.so/.dylib) are present when required.
- `make clean` removes `dist/`, `release/`, and `assets/` so you can start
	fresh: `make clean && make fetch-ffmpeg`.

Development notes
-----------------

- The downloader uses `github.com/kkdai/youtube/v2` for YouTube stream access.
- The runtime extracts an embedded `ffmpeg` binary and invokes it to perform
	conversion; make sure the embedded `ffmpeg` is a self-contained static
	binary compatible with the target platform.

Contributing
------------

Contributions welcome. If you add CI packaging or automatic `ffmpeg` fetchers,
make sure assets are staged before `go build` so the binaries are embedded.

