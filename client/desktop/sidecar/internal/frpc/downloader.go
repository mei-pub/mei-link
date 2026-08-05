package frpc

import (
	"archive/tar"
	"archive/zip"
	"compress/gzip"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

const (
	FrpVersion = "v0.70.0"
	GitHubBase = "https://github.com/fatedier/frp/releases/download"
)

// Downloader handles downloading the correct frpc binary for the current platform.
type Downloader struct {
	client *http.Client
}

// NewDownloader creates a Downloader with a 60-second timeout.
func NewDownloader() *Downloader {
	return &Downloader{client: &http.Client{Timeout: 60 * time.Second}}
}

// EnsureFrpc checks if frpc exists at the expected location and downloads it if missing.
func (d *Downloader) EnsureFrpc(destDir string) (string, error) {
	osName := runtime.GOOS
	arch := runtime.GOARCH
	frpArch := arch

	binaryName := "frpc"
	if osName == "windows" {
		binaryName = "frpc.exe"
	}

	candidate := filepath.Join(destDir, binaryName)
	if info, err := os.Stat(candidate); err == nil && info.Mode().IsRegular() {
		return candidate, nil
	}

	ext := ".tar.gz"
	if osName == "windows" {
		ext = ".zip"
	}
	filename := fmt.Sprintf("frp_%s_%s_%s%s", FrpVersion[1:], osName, frpArch, ext)
	url := fmt.Sprintf("%s/%s/%s", GitHubBase, FrpVersion, filename)

	if err := os.MkdirAll(destDir, 0o755); err != nil {
		return "", err
	}
	tmpFile := filepath.Join(destDir, ".frpc-download.tmp")

	resp, err := d.client.Get(url)
	if err != nil {
		return "", fmt.Errorf("download frpc: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("download failed: HTTP %d", resp.StatusCode)
	}

	f, err := os.Create(tmpFile)
	if err != nil {
		return "", err
	}
	if _, err := io.Copy(f, resp.Body); err != nil {
		f.Close()
		return "", err
	}
	f.Close()

	if ext == ".zip" {
		if err := unzipFile(tmpFile, destDir); err != nil {
			os.Remove(tmpFile)
			return "", err
		}
	} else {
		if err := untarGzFile(tmpFile, destDir); err != nil {
			os.Remove(tmpFile)
			return "", err
		}
	}
	os.Remove(tmpFile)

	matches, _ := filepath.Glob(filepath.Join(destDir, "frp_*", binaryName))
	outPath := candidate
	if len(matches) > 0 {
		if err := copyFile(matches[0], outPath); err != nil {
			return "", err
		}
	} else if _, err := os.Stat(candidate); err == nil {
		outPath = candidate
	} else {
		return "", fmt.Errorf("cannot find %s in downloaded archive", binaryName)
	}

	if runtime.GOOS != "windows" {
		os.Chmod(outPath, 0o755)
	}
	return outPath, nil
}

func untarGzFile(tarGzPath, destDir string) error {
	f, err := os.Open(tarGzPath)
	if err != nil {
		return err
	}
	defer f.Close()

	gzr, err := gzip.NewReader(f)
	if err != nil {
		return err
	}
	defer gzr.Close()

	tr := tar.NewReader(gzr)
	for {
		header, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}

		name := header.Name
		parts := strings.SplitN(name, "/", 2)
		if len(parts) == 2 {
			name = parts[1]
		}

		target := filepath.Join(destDir, name)
		switch header.Typeflag {
		case tar.TypeReg:
			if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
				return err
			}
			out, err := os.OpenFile(target, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, os.FileMode(header.Mode))
			if err != nil {
				return err
			}
			if _, err := io.Copy(out, tr); err != nil {
				out.Close()
				return err
			}
			out.Close()
		case tar.TypeDir:
			if err := os.MkdirAll(target, 0o755); err != nil {
				return err
			}
		}
	}
	return nil
}

func unzipFile(zipPath, destDir string) error {
	r, err := zip.OpenReader(zipPath)
	if err != nil {
		return err
	}
	defer r.Close()

	for _, f := range r.File {
		name := f.Name
		parts := strings.SplitN(name, "/", 2)
		if len(parts) == 2 {
			name = parts[1]
		}

		target := filepath.Join(destDir, name)
		if f.FileInfo().IsDir() {
			if err := os.MkdirAll(target, 0o755); err != nil {
				return err
			}
			continue
		}

		if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
			return err
		}
		rc, err := f.Open()
		if err != nil {
			return err
		}
		out, err := os.OpenFile(target, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, f.Mode())
		if err != nil {
			rc.Close()
			return err
		}
		if _, err := io.Copy(out, rc); err != nil {
			out.Close()
			rc.Close()
			return err
		}
		out.Close()
		rc.Close()
	}
	return nil
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer out.Close()

	_, err = io.Copy(out, in)
	return err
}
