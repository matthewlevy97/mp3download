# MP3Download

Small CLI tool to download audio from a YouTube URL and convert it to an
iPod-friendly MP3. The built Go executable embeds a platform-specific `ffmpeg`
binary (from `assets/ffmpeg/<os>-<arch>/`) and extracts it at runtime so the
delivered binary is self-contained.

Quick usage
-----------

Fetch ffmpeg assets, build, then run (example macOS):

```bash
make fetch-ffmpeg
make build
# example (pick the correct binary in dist/ for your platform)
./dist/mp3download-darwin-amd64 -url "https://www.youtube.com/watch?v=..." -o song.mp3
```

If you prefer to run without building first for quick testing:

```bash
go run . -url "https://www.youtube.com/watch?v=..." -o song.mp3
```

Notes on `ffmpeg` embedding
---------------------------

Download prebuilt static `ffmpeg` binaries for each platform you want to
support and place them under `assets/ffmpeg/<os>-<arch>/ffmpeg` (Windows files
should be named `ffmpeg.exe`). Example paths:

- `assets/ffmpeg/darwin-amd64/ffmpeg`
- `assets/ffmpeg/darwin-arm64/ffmpeg`
- `assets/ffmpeg/linux-amd64/ffmpeg`
- `assets/ffmpeg/windows-amd64/ffmpeg.exe`

The build process embeds whatever is present under `assets/ffmpeg/*/*` into the
binary. CI or your local build machine must stage the correct `ffmpeg` files
before `go build` is run.

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

- If `make build` fails, ensure `assets/ffmpeg/<os>-<arch>/ffmpeg` exists for
	your target; run `make fetch-ffmpeg` or place binaries manually.
- If MP3s don't appear on the iPod after copying, use iTunes/Finder or
	`gtkpod`/`rhythmbox` to import and sync — these update the device database.

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

