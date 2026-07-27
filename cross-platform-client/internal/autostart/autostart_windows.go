//go:build windows

package autostart

import (
	"fmt"
	"os"
	"path/filepath"

	"golang.org/x/sys/windows/registry"
)

const registryValueName = "Meilink"

// currentExecutable returns the absolute path to the running binary.
func currentExecutable() (string, error) {
	exe, err := os.Executable()
	if err != nil {
		return "", err
	}
	abs, err := filepath.Abs(exe)
	if err != nil {
		return "", err
	}
	return abs, nil
}

func enable() error {
	exe, err := currentExecutable()
	if err != nil {
		return err
	}
	k, _, err := registry.CreateKey(registry.CURRENT_USER, `Software\Microsoft\Windows\CurrentVersion\Run`, registry.SET_VALUE|registry.QUERY_VALUE)
	if err != nil {
		return fmt.Errorf("open run key: %w", err)
	}
	defer k.Close()
	// Quote the path so spaces in the executable path don't break the command.
	return k.SetStringValue(registryValueName, `"`+exe+`" serve`)
}

func disable() error {
	k, err := registry.OpenKey(registry.CURRENT_USER, `Software\Microsoft\Windows\CurrentVersion\Run`, registry.SET_VALUE)
	if err != nil {
		return fmt.Errorf("open run key: %w", err)
	}
	defer k.Close()
	if err := k.DeleteValue(registryValueName); err != nil && err != registry.ErrNotExist {
		return err
	}
	return nil
}

func isEnabled() bool {
	k, err := registry.OpenKey(registry.CURRENT_USER, `Software\Microsoft\Windows\CurrentVersion\Run`, registry.QUERY_VALUE)
	if err != nil {
		return false
	}
	defer k.Close()
	val, _, err := k.GetStringValue(registryValueName)
	if err != nil {
		return false
	}
	return val != ""
}
