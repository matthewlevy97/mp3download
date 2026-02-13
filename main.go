package main

import (
	"bufio"
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"

	"github.com/kkdai/youtube/v2"
)

// Note: ffmpeg is NOT embedded. The program prefers a sidecar `ffmpeg` next
// to the executable or a system `ffmpeg` on PATH. Do not add ffmpeg to
// `assets/ffmpeg/` because embedding is disabled by design.

func main() {
	flag.Usage = func() {
		fmt.Fprintf(flag.CommandLine.Output(), "Usage: %s [-url YOUTUBE_URL | -list links.txt] [-o output.mp3 | -o out/dir/]\n", os.Args[0])
		flag.PrintDefaults()
	}

	url := flag.String("url", "", "YouTube video URL")
	list := flag.String("list", "", "Path to file containing YouTube URLs (one per line)")
	out := flag.String("o", "", "Output MP3 path, or when used with -list, an output directory")
	concurrency := flag.Int("concurrency", runtime.NumCPU(), "Number of concurrent workers for download/convert when using -list")
	flag.Parse()

	// Support drag-and-drop: if a positional argument (file path) is provided
	// and -list is not set, treat the first positional arg as the list file.
	if *list == "" && flag.NArg() > 0 {
		candidate := flag.Arg(0)
		if fi, err := os.Stat(candidate); err == nil && !fi.IsDir() {
			*list = candidate
		}
	}

	// No temp-extracted ffmpeg is used anymore; sidecar or system ffmpeg is preferred.

	if *list != "" {
		// process list file
		f, err := os.Open(*list)
		if err != nil {
			log.Fatalf("failed to open list file: %v", err)
		}
		defer f.Close()

		outDir := *out
		if outDir == "" {
			outDir = "."
		}
		// ensure outDir exists
		if stat, err := os.Stat(outDir); err != nil || !stat.IsDir() {
			log.Fatalf("output must be a directory when using -list: %s", outDir)
		}

		// Read links
		var links []string
		scanner := bufio.NewScanner(f)
		for scanner.Scan() {
			link := strings.TrimSpace(scanner.Text())
			if link == "" || strings.HasPrefix(link, "#") {
				continue
			}
			links = append(links, link)
		}
		if err := scanner.Err(); err != nil {
			log.Fatalf("error reading list file: %v", err)
		}

		if len(links) == 0 {
			log.Println("no links found in list file")
			return
		}

		// Create a temporary directory to store downloads
		tempDir, err := os.MkdirTemp("", "mp3download-batch-*")
		if err != nil {
			log.Fatalf("failed to create temp dir: %v", err)
		}
		// ensure cleanup after all work
		defer os.RemoveAll(tempDir)

		// Ensure ffmpeg is extracted once for the process
		ff, err := extractFFmpegOnce()
		if err != nil {
			log.Fatalf("failed to extract ffmpeg: %v", err)
		}
		// ff is either a sidecar or system binary; do not remove it.

		// Concurrent downloads
		type dlResult struct {
			link   string
			path   string
			title  string
			artist string
			err    error
		}

		jobs := make(chan string)
		results := make(chan dlResult)

		var wg sync.WaitGroup
		workers := *concurrency
		if workers < 1 {
			workers = 1
		}

		// start download workers
		for i := 0; i < workers; i++ {
			wg.Add(1)
			go func() {
				defer wg.Done()
				client := youtube.Client{}
				for link := range jobs {
					path, title, artist, err := downloadVideoToDir(&client, link, tempDir)
					results <- dlResult{link: link, path: path, title: title, artist: artist, err: err}
				}
			}()
		}

		// feed jobs
		go func() {
			for _, l := range links {
				jobs <- l
			}
			close(jobs)
		}()

		// collect results
		go func() {
			wg.Wait()
			close(results)
		}()

		var downloaded []dlResult
		for r := range results {
			if r.err != nil {
				log.Printf("download failed for %s: %v", r.link, r.err)
				continue
			}
			downloaded = append(downloaded, r)
			log.Printf("downloaded: %s -> %s", r.link, r.path)
		}

		if len(downloaded) == 0 {
			log.Println("no successful downloads, exiting")
			return
		}

		// Convert concurrently (bounded by workers)
		convJobs := make(chan dlResult)
		convWg := sync.WaitGroup{}
		for i := 0; i < workers; i++ {
			convWg.Add(1)
			go func() {
				defer convWg.Done()
				for job := range convJobs {
					// derive output path in outDir
					base := sanitizeFileName(job.title)
					if base == "" {
						base = job.link
					}
					outPath := filepath.Join(outDir, base+".mp3")
					if err := convertToMP3(job.path, outPath, ff, job.title, job.artist); err != nil {
						log.Printf("conversion failed for %s: %v", job.link, err)
					} else {
						log.Printf("converted: %s -> %s", job.link, outPath)
					}
				}
			}()
		}

		for _, d := range downloaded {
			convJobs <- d
		}
		close(convJobs)
		convWg.Wait()

		// tempDir will be removed by defer
		return
	}

	if *url == "" {
		flag.Usage()
		os.Exit(1)
	}

	// If -o is not provided, pass empty string so downloadAndConvert
	// can derive the filename from the YouTube title.
	output := *out

	if err := downloadAndConvert(*url, output); err != nil {
		log.Fatalf("error: %v", err)
	}
}

// downloadAndConvert is a skeleton placeholder for the full implementation.
// Step 2 will implement downloading via github.com/kkdai/youtube/v2 and
// Step 3 will embed and invoke ffmpeg to produce an MP3 file.
func downloadAndConvert(url, output string) error {
	client := youtube.Client{}

	video, err := client.GetVideo(url)
	if err != nil {
		return fmt.Errorf("failed to get video info: %w", err)
	}

	// If output not provided, derive from title
	if output == "" {
		title := sanitizeFileName(video.Title)
		if title == "" {
			title = video.ID
		}
		output = title + ".mp3"
	}

	// Prefer audio-capable formats (WithAudioChannels helper).
	audioFormats := video.Formats.WithAudioChannels()
	if len(audioFormats) == 0 {
		return fmt.Errorf("no audio formats found for video")
	}

	// Pick the first audio format (highest quality usually first).
	format := audioFormats[0]

	stream, _, err := client.GetStream(video, &format)
	if err != nil {
		return fmt.Errorf("failed to get stream: %w", err)
	}
	defer stream.Close()

	// Create temp file for the downloaded stream.
	ext := "mp4"
	if format.MimeType != "" {
		// try to guess extension from mime-type (basic)
		if format.MimeType == "audio/webm" || format.MimeType == "video/webm" {
			ext = "webm"
		}
	}

	tmpFile, err := os.CreateTemp("", "mp3download-*."+ext)
	if err != nil {
		return fmt.Errorf("failed to create temp file: %w", err)
	}
	// ensure closed before conversion
	defer os.Remove(tmpFile.Name())

	if _, err := io.Copy(tmpFile, stream); err != nil {
		tmpFile.Close()
		return fmt.Errorf("failed to write stream to file: %w", err)
	}
	if err := tmpFile.Close(); err != nil {
		return fmt.Errorf("failed to close temp file: %w", err)
	}

	absPath, _ := filepath.Abs(tmpFile.Name())
	fmt.Println("Downloaded stream to:", absPath)

	// Extract embedded ffmpeg for this platform (cached per process)
	ffmpegPath, err := extractFFmpegOnce()
	if err != nil {
		return fmt.Errorf("ffmpeg extraction failed: %w", err)
	}

	// Ensure output filename ends with .mp3
	if filepath.Ext(output) == "" {
		output = output + ".mp3"
	}

	// ensure parent dir exists
	if dir := filepath.Dir(output); dir != "." {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return fmt.Errorf("failed to create output directory: %w", err)
		}
	}

	// Convert to MP3 (iPod-compatible settings)
	if err := convertToMP3(tmpFile.Name(), output, ffmpegPath, video.Title, video.Author); err != nil {
		return fmt.Errorf("conversion failed: %w", err)
	}

	fmt.Println("Conversion complete — output:", output)
	return nil
}

// downloadVideoToDir downloads the youtube video (audio format) into destDir
// and returns the downloaded file path and metadata (title, author).
func downloadVideoToDir(client *youtube.Client, url, destDir string) (string, string, string, error) {
	video, err := client.GetVideo(url)
	if err != nil {
		return "", "", "", fmt.Errorf("failed to get video info: %w", err)
	}

	// Prefer audio-capable formats (WithAudioChannels helper).
	audioFormats := video.Formats.WithAudioChannels()
	if len(audioFormats) == 0 {
		return "", "", "", fmt.Errorf("no audio formats found for video")
	}
	format := audioFormats[0]

	stream, _, err := client.GetStream(video, &format)
	if err != nil {
		return "", "", "", fmt.Errorf("failed to get stream: %w", err)
	}
	defer stream.Close()

	ext := "mp4"
	if format.MimeType != "" {
		if format.MimeType == "audio/webm" || format.MimeType == "video/webm" {
			ext = "webm"
		}
	}

	base := sanitizeFileName(video.Title)
	if base == "" {
		base = video.ID
	}
	fname := fmt.Sprintf("%s.%s", base, ext)
	// ensure unique
	outPath := filepath.Join(destDir, fname)
	// if file exists, append a counter
	for i := 1; ; i++ {
		if _, err := os.Stat(outPath); os.IsNotExist(err) {
			break
		}
		outPath = filepath.Join(destDir, fmt.Sprintf("%s-%d.%s", base, i, ext))
	}

	tmpFile, err := os.Create(outPath)
	if err != nil {
		return "", "", "", fmt.Errorf("failed to create file: %w", err)
	}

	if _, err := io.Copy(tmpFile, stream); err != nil {
		tmpFile.Close()
		return "", "", "", fmt.Errorf("failed to write stream to file: %w", err)
	}
	if err := tmpFile.Close(); err != nil {
		return "", "", "", fmt.Errorf("failed to close file: %w", err)
	}

	return outPath, video.Title, video.Author, nil
}

// sanitizeFileName removes characters unsafe for filenames and trims length.
func sanitizeFileName(s string) string {
	s = strings.TrimSpace(s)
	// replace path separators and control chars
	s = strings.ReplaceAll(s, string(os.PathSeparator), "-")
	// remove characters commonly problematic in filenames
	bad := []string{"/", "\\", ":", "*", "?", "\"", "<", ">", "|"}
	for _, b := range bad {
		s = strings.ReplaceAll(s, b, "-")
	}
	// collapse spaces
	s = strings.Join(strings.Fields(s), " ")
	if len(s) > 200 {
		s = s[:200]
	}
	return s
}

// extractFFmpeg reads the embedded ffmpeg for the current GOOS/GOARCH,
// writes it to a temp file, makes it executable, and returns its path.
// extractFFmpeg is kept for compatibility; prefer extractFFmpegOnce.
func extractFFmpeg() (string, error) {
	return extractFFmpegOnce()
}

var (
	ffmpegOnce      sync.Once
	ffmpegPathCache string
	ffmpegErr       error
)

// extractFFmpegOnce extracts the embedded ffmpeg once per process and returns
// a path to the extracted binary. The file will be written to the system temp
// directory using a small content-derived name.
func extractFFmpegOnce() (string, error) {
	ffmpegOnce.Do(func() {
		// Prefer a vendor ffmpeg located in `vendor/` next to the executable (release ZIP)
		if exe, err := os.Executable(); err == nil {
			exeDir := filepath.Dir(exe)
			// 1) vendor/ffmpeg or vendor/ffmpeg.exe
			for _, name := range []string{"vendor/ffmpeg", "vendor/ffmpeg.exe"} {
				cand := filepath.Join(exeDir, name)
				if st, err := os.Stat(cand); err == nil && !st.IsDir() {
					ffmpegPathCache = cand
					return
				}
			}
			// 2) legacy sidecar next to exe
			for _, name := range []string{"ffmpeg", "ffmpeg.exe"} {
				cand := filepath.Join(exeDir, name)
				if st, err := os.Stat(cand); err == nil && !st.IsDir() {
					ffmpegPathCache = cand
					return
				}
			}
		}

		// Next prefer system ffmpeg on PATH
		if sysPath, err := exec.LookPath("ffmpeg"); err == nil {
			ffmpegPathCache = sysPath
			return
		}

		// No sidecar and no system ffmpeg found — instruct the user.
		ffmpegErr = fmt.Errorf("ffmpeg not found: place ffmpeg (or ffmpeg.exe on Windows) next to the executable or install ffmpeg on PATH")
		return
	})
	return ffmpegPathCache, ffmpegErr
}

func convertToMP3(inputPath, outputPath, ffmpegPath, title, artist string) error {
	// tuned for performance and compatibility: use multiple threads, quiet logs
	args := []string{"-y", "-hide_banner", "-loglevel", "warning", "-nostdin", "-i", inputPath, "-vn", "-codec:a", "libmp3lame", "-b:a", "128k", "-ar", "44100", "-ac", "2", "-threads", fmt.Sprintf("%d", runtime.NumCPU())}
	if title != "" {
		args = append(args, "-metadata", fmt.Sprintf("title=%s", title))
	}
	if artist != "" {
		args = append(args, "-metadata", fmt.Sprintf("artist=%s", artist))
	}
	args = append(args, "-id3v2_version", "3", outputPath)

	cmd := exec.Command(ffmpegPath, args...)
	// Ensure ffmpeg runs with its vendor dir as CWD so it can find companion libs
	if abs, err := filepath.Abs(ffmpegPath); err == nil {
		cmd.Dir = filepath.Dir(abs)
	}
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}
