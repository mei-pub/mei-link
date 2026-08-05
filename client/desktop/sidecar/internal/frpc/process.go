package frpc

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"
)

// Process manages the frpc binary lifecycle.
type Process struct {
	binPath string
	cmd     *exec.Cmd
	logger  *log.Logger

	// onOutputMu guards onOutput/onTermination against concurrent mutation
	// while Wait goroutines are still streaming lines.
	onOutputMu sync.RWMutex
	// OnOutput is invoked for each stdout/stderr line emitted by frpc. Lines
	// are trimmed; empty lines are skipped. The callback MUST NOT block on
	// the manager's mutex held by the same goroutine that calls Stop,
	// otherwise Stop -> Wait -> OnOutput can deadlock. Keep it fast and
	// forward to addEvent without re-entering the process lock.
	OnOutput func(line string)
	// OnTermination is invoked exactly once when the frpc process exits.
	// status is the OS exit code (0 for normal exit). It is called from a
	// background goroutine; callers needing main-thread semantics must
	// dispatch themselves. Mirrors Swift FrpcProcess.onTermination.
	OnTermination func(status int)

	// logFile is the file handle for frpc.log (kept open for the process
	// lifetime so stderr is also persisted on disk).
	logFile *os.File
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
	p.logFile = f
	p.logger = log.New(f, "", log.LstdFlags)

	// Capture stdout/stderr both to disk and to in-memory pipes so we can
	// stream lines to OnOutput without losing the disk copy.
	stdoutR, stdoutW := io.Pipe()
	stderrR, stderrW := io.Pipe()

	p.cmd = exec.CommandContext(ctx, bin, "-c", configPath)
	p.cmd.Stdout = io.MultiWriter(f, stdoutW)
	p.cmd.Stderr = io.MultiWriter(f, stderrW)

	// Detach from parent on Unix; hide window on Windows.
	applyPlatformAttrs(p.cmd)

	if err := p.cmd.Start(); err != nil {
		f.Close()
		p.logFile = nil
		_ = stdoutR.Close()
		_ = stdoutW.Close()
		_ = stderrR.Close()
		_ = stderrW.Close()
		return err
	}
	p.logger.Printf("frpc started, pid=%d", p.cmd.Process.Pid)

	// Spawn line scanners for stdout/stderr. Each forwards trimmed non-empty
	// lines to OnOutput.
	go p.scanLines(stdoutR)
	go p.scanLines(stderrR)

	// Spawn a Wait goroutine that invokes OnTermination exactly once when
	// the process exits. We own cmd.Wait here; Stop must NOT call it.
	go func() {
		err := p.cmd.Wait()
		// Close pipe writers so scanners EOF and exit.
		_ = stdoutW.Close()
		_ = stderrW.Close()

		status := 0
		if err != nil {
			if exitErr, ok := err.(*exec.ExitError); ok {
				status = exitErr.ExitCode()
			} else {
				status = -1
			}
		}
		p.logger.Printf("frpc exited, status=%d", status)
		p.onOutputMu.RLock()
		cb := p.OnTermination
		p.onOutputMu.RUnlock()
		if cb != nil {
			cb(status)
		}
	}()

	return nil
}

// scanLines reads from r line by line, forwards trimmed non-empty lines to
// OnOutput, and exits when r returns EOF (which happens when the pipe writer
// is closed, i.e. when the frpc process has exited).
func (p *Process) scanLines(r io.ReadCloser) {
	scanner := bufio.NewScanner(r)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		p.onOutputMu.RLock()
		cb := p.OnOutput
		p.onOutputMu.RUnlock()
		if cb != nil {
			cb(line)
		}
	}
	_ = r.Close()
}

func (p *Process) Stop(timeout time.Duration) error {
	if !p.IsRunning() {
		return nil
	}
	if timeout > 0 {
		done := make(chan struct{})
		go func() {
			_ = p.cmd.Process.Kill()
			close(done)
		}()
		select {
		case <-done:
		case <-time.After(timeout):
			_ = p.cmd.Process.Signal(os.Interrupt)
		}
	} else {
		_ = p.cmd.Process.Kill()
	}
	// Do NOT call cmd.Wait() here — the Wait goroutine spawned in Start
	// already owns it. Just drop our reference so IsRunning() returns false.
	p.cmd = nil
	p.closeLogFile()
	return nil
}

func (p *Process) StopImmediately() {
	if !p.IsRunning() {
		return
	}
	_ = p.cmd.Process.Kill()
	p.cmd = nil
	p.closeLogFile()
}

// closeLogFile closes the frpc.log handle if open. Called from Stop paths.
// The Wait goroutine writes to the logger (which wraps logFile) until the
// process actually exits; closing here is safe because by the time Stop is
// called we've already asked the OS to kill the process.
func (p *Process) closeLogFile() {
	if p.logFile != nil {
		_ = p.logFile.Close()
		p.logFile = nil
	}
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
