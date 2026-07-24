package frpc

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

// Process manages the frpc binary lifecycle.
type Process struct {
	binPath string
	cmd     *exec.Cmd
	logger  *log.Logger
}

func NewProcess(binPath string) *Process { return &Process{binPath: binPath} }

func (p *Process) BinPath() string {
	if p.binPath != "" {
		return p.binPath
	}
	p.binPath = ResolveBinPath()
	return p.binPath
}

func (p *Process) IsRunning() bool {
	return p.cmd != nil && p.cmd.Process != nil && p.cmd.ProcessState == nil
}

func (p *Process) PID() int {
	if p.IsRunning() {
		return p.cmd.Process.Pid
	}
	return 0
}

func (p *Process) Start(ctx context.Context, configPath string) error {
	if p.IsRunning() {
		return fmt.Errorf("frpc already running")
	}
	bin := p.BinPath()
	if _, err := os.Stat(bin); err != nil {
		return fmt.Errorf("frpc binary not found at %s: %w", bin, err)
	}

	logDir := filepath.Dir(configPath)
	logFile := filepath.Join(logDir, "frpc.log")
	f, err := os.OpenFile(logFile, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
	if err != nil {
		return err
	}
	p.logger = log.New(f, "", log.LstdFlags)

	p.cmd = exec.CommandContext(ctx, bin, "-c", configPath)
	p.cmd.Stdout = f
	p.cmd.Stderr = f

	// Detach from parent on Unix; hide window on Windows.
	if runtime.GOOS == "windows" {
		// On Windows, we'd want CREATE_NO_WINDOW, but that requires
		// golang.org/x/sys/windows. For now, skip platform-specific attrs.
	} else {
		// Setpgid detaches from terminal group on Unix.
		_ = p.cmd.Process
	}

	if err := p.cmd.Start(); err != nil {
		f.Close()
		return err
	}
	p.logger.Printf("frpc started, pid=%d", p.cmd.Process.Pid)
	return nil
}

func (p *Process) Stop(timeout time.Duration) error {
	if !p.IsRunning() {
		return nil
	}
	if timeout > 0 {
		done := make(chan struct{})
		go func() {
			p.cmd.Process.Kill()
			close(done)
		}()
		select {
		case <-done:
		case <-time.After(timeout):
			p.cmd.Process.Signal(os.Interrupt)
		}
	} else {
		p.cmd.Process.Kill()
	}
	p.cmd.Wait()
	p.cmd = nil
	return nil
}

func (p *Process) StopImmediately() {
	if !p.IsRunning() {
		return
	}
	p.cmd.Process.Kill()
	p.cmd.Wait()
	p.cmd = nil
}

// ResolveBinPath finds the bundled or sibling frpc binary.
func ResolveBinPath() string {
	if v := os.Getenv("MEILINK_FRPC_BIN"); v != "" {
		return v
	}
	exe, err := os.Executable()
	if err == nil {
		dir := filepath.Dir(exe)
		for _, c := range []string{filepath.Join(dir, "frpc"), filepath.Join(dir, "frpc.exe")} {
			if isExecutable(c) {
				return c
			}
		}
	}
	installPaths := []string{"/usr/local/bin/frpc", "/usr/bin/frpc", "/opt/meilink/bin/frpc"}
	if runtime.GOOS == "windows" {
		installPaths = append(installPaths,
			filepath.Join(os.Getenv("ProgramFiles"), "Meilink", "frpc.exe"),
			filepath.Join(os.Getenv("LOCALAPPDATA"), "Meilink", "frpc.exe"),
		)
	}
	for _, p := range installPaths {
		if isExecutable(p) {
			return p
		}
	}
	return ""
}

func isExecutable(path string) bool {
	info, err := os.Stat(path)
	if err != nil {
		return false
	}
	if runtime.GOOS == "windows" {
		return strings.HasSuffix(strings.ToLower(info.Name()), ".exe")
	}
	return info.Mode()&0o111 != 0
}
