//go:build windows

package frpc

import (
	"os/exec"
	"syscall"
)

// hideConsoleAttributes returns SysProcAttr that suppresses the console window
// when spawning a child process on Windows. Used by Process.Start to avoid a
// flashing black cmd window when frpc is launched.
func hideConsoleAttributes() *syscall.SysProcAttr {
	// CREATE_NO_WINDOW = 0x08000000
	return &syscall.SysProcAttr{CreationFlags: 0x08000000}
}

// applyPlatformAttrs is called by Process.Start to set platform-specific
// process attributes. On Windows we hide the console window; on other platforms
// the no-op stub in process_other.go is used.
func applyPlatformAttrs(cmd *exec.Cmd) {
	if cmd == nil {
		return
	}
	cmd.SysProcAttr = hideConsoleAttributes()
}
