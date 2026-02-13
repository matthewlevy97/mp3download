BINARY := mp3download
DIST := dist
PKG := ./...


.PHONY: all fetch-ffmpeg verify-assets build build-all clean dist

all: fetch-ffmpeg build-all

fetch-ffmpeg:
	@bash scripts/fetch_ffmpeg.sh

dist: build-all
	./scripts/package_release.sh $(DIST)
	@echo "Distribution files created in $(DIST)/"

# Verify that ffmpeg asset exists for a target (arg: TARGET_DIR)
verify-assets = test -f assets/ffmpeg/$(1)/ffmpeg || test -f assets/ffmpeg/$(1)/ffmpeg.exe

build: build-darwin-arm64 build-windows-amd64 build-linux-amd64

build-all: build

build-darwin-amd64:
	@echo "Building darwin/amd64..."
	@CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 go build -ldflags='-s -w' -o $(DIST)/$(BINARY)-darwin-amd64 ./

build-darwin-arm64:
	@echo "Building darwin/arm64..."
	@CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -ldflags='-s -w' -o $(DIST)/$(BINARY)-darwin-arm64 ./

build-linux-amd64: verify-ffmpeg-linux-amd64
	@echo "Building linux/amd64..."
	@CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags='-s -w' -o $(DIST)/$(BINARY)-linux-amd64 ./

build-windows-amd64:
	@echo "Building windows/amd64..."
	@CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -ldflags='-s -w' -o $(DIST)/$(BINARY)-windows-amd64.exe ./

verify-ffmpeg-linux-amd64:
	@test -f assets/ffmpeg/linux-amd64/ffmpeg || (echo "Missing ffmpeg for linux-amd64 in assets/ffmpeg/linux-amd64/ffmpeg" && exit 1)
	@echo "Verifying ffmpeg asset for linux/amd64..."
	@$(call verify-assets,linux-amd64) || (echo "Missing assets/ffmpeg/linux-amd64/ffmpeg — run 'make fetch-ffmpeg' or place binary manually" && exit 1)
	@echo "Building linux/amd64..."
	@CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags='-s -w' -o $(DIST)/$(BINARY)-linux-amd64 ./

build-linux-amd64:
	@echo "Building linux/amd64..."
	@CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags='-s -w' -o $(DIST)/$(BINARY)-linux-amd64 ./

clean:
	@rm -rf $(DIST)
