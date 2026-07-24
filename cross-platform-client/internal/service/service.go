package service

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/kardianos/service"
)

// ServiceConfig holds service registration parameters.
type ServiceConfig struct {
	Name        string
	DisplayName string
	Description string
	ExecPath    string
	Args        []string
	WorkingDir  string
	Env         map[string]string
}

// program adapts the kardianos service.Service interface. When installed as a
// system service, the OS launches our executable with the configured Args
// (e.g. ["run"]). Run() blocks for the lifetime of the service.
type program struct {
	cfg ServiceConfig
}

func (p *program) Start(s service.Service) error { return nil }
func (p *program) Stop(s service.Service) error  { return nil }
func (p *program) Run() error {
	// In service mode we never reach here because the OS re-invokes the
	// executable directly with Args (see main.go "run" subcommand). This
	// method only runs if kardianos falls back to an interactive/unsupported
	// mode, in which case we exec the configured command once.
	cmd := exec.Command(p.cfg.ExecPath, p.cfg.Args...)
	cmd.Dir = p.cfg.WorkingDir
	cmd.Env = os.Environ()
	for k, v := range p.cfg.Env {
		cmd.Env = append(cmd.Env, k+"="+v)
	}
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

// Install registers the application as a system service and starts it.
func Install(cfg ServiceConfig) error {
	exe, err := exec.LookPath(cfg.ExecPath)
	if err != nil {
		exe = cfg.ExecPath
	}

	svcConfig := &service.Config{
		Name:             cfg.Name,
		DisplayName:      cfg.DisplayName,
		Description:      cfg.Description,
		Executable:       exe,
		Arguments:        cfg.Args,
		WorkingDirectory: cfg.WorkingDir,
	}
	if cfg.Env != nil {
		svcConfig.EnvVars = make(map[string]string, len(cfg.Env))
		for k, v := range cfg.Env {
			svcConfig.EnvVars[k] = v
		}
	}

	s, err := service.New(&program{cfg: cfg}, svcConfig)
	if err != nil {
		return fmt.Errorf("create service: %w", err)
	}
	if err := s.Install(); err != nil {
		return fmt.Errorf("install service: %w", err)
	}
	if err := s.Start(); err != nil {
		fmt.Printf("warning: service installed but failed to start: %v\n", err)
	}
	fmt.Printf("Service %q installed and started.\n", cfg.Name)
	return nil
}

// Uninstall stops and removes the application from system services.
func Uninstall(name string) error {
	s, err := service.New(&program{}, &service.Config{Name: name})
	if err != nil {
		return fmt.Errorf("create service: %w", err)
	}
	_ = s.Stop()
	if err := s.Uninstall(); err != nil {
		return fmt.Errorf("uninstall service: %w", err)
	}
	fmt.Printf("Service %q uninstalled.\n", name)
	return nil
}

// IsInstalled checks whether the named service is registered.
func IsInstalled(name string) bool {
	s, err := service.New(&program{}, &service.Config{Name: name})
	if err != nil {
		return false
	}
	_, err = s.Status()
	return err == nil
}

// HomeDataDir returns the absolute ~/.meilink path.
func HomeDataDir() string {
	home, err := os.UserHomeDir()
	if err != nil {
		home = "."
	}
	return filepath.Join(home, ".meilink")
}
