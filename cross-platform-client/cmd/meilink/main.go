package meilink

import (
	"bufio"
	"context"
	"fmt"
	"net"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/meilink/client/internal/config"
	"github.com/meilink/client/internal/service"
	"github.com/meilink/client/internal/tunnel"
	"github.com/meilink/client/internal/web"
	"github.com/spf13/cobra"
)

const serviceName = "meilink"
const launchdLabel = "com.meilink.client"

var (
	cfgDir     string
	listenAddr string
)

var rootCmd = &cobra.Command{
	Use:   "meilink",
	Short: "Meilink cross-platform client for frp",
	Long:  "Meilink is a cross-platform client that manages frp tunnels via a web UI.",
}

var startCmd = &cobra.Command{
	Use:   "start",
	Short: "Start Meilink client in the foreground",
	RunE: func(cmd *cobra.Command, args []string) error {
		return runForeground()
	},
}

var runCmd = &cobra.Command{
	Use:   "run",
	Short: "Run as a system service entrypoint (foreground, signal-managed)",
	RunE: func(cmd *cobra.Command, args []string) error {
		return runForeground()
	},
}

var stopCmd = &cobra.Command{
	Use:   "stop",
	Short: "Stop Meilink client (service first, then PID file)",
	RunE: func(cmd *cobra.Command, args []string) error {
		return stopClient()
	},
}

var restartCmd = &cobra.Command{
	Use:   "restart",
	Short: "Restart Meilink client",
	RunE: func(cmd *cobra.Command, args []string) error {
		return restartClient()
	},
}

var statusCmd = &cobra.Command{
	Use:   "status",
	Short: "Show Meilink client status",
	RunE: func(cmd *cobra.Command, args []string) error {
		return showStatus()
	},
}

var setupCmd = &cobra.Command{
	Use:   "setup",
	Short: "Interactive setup wizard",
	RunE: func(cmd *cobra.Command, args []string) error {
		return runSetup()
	},
}

var installSvcCmd = &cobra.Command{
	Use:   "install-service",
	Short: "Install as a system service (with auto-start on boot)",
	RunE: func(cmd *cobra.Command, args []string) error {
		return installService()
	},
}

var uninstallSvcCmd = &cobra.Command{
	Use:   "uninstall-service",
	Short: "Uninstall the system service",
	RunE: func(cmd *cobra.Command, args []string) error {
		return uninstallService()
	},
}

var versionCmd = &cobra.Command{
	Use:   "version",
	Short: "Show version",
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Println("meilink v1.1.0 (cross-platform)")
	},
}

var serveCmd = &cobra.Command{
	Use:   "serve",
	Short: "Run as a sidecar for the desktop GUI (auto-select port, write port file)",
	RunE: func(cmd *cobra.Command, args []string) error {
		return runSidecar()
	},
}

// Execute runs the CLI.
func Execute() error {
	rootCmd.PersistentFlags().StringVar(&cfgDir, "config-dir", "", "Meilink data directory (default: ~/.meilink)")
	startCmd.Flags().StringVar(&listenAddr, "listen", ":7400", "Web UI listen address")
	runCmd.Flags().StringVar(&listenAddr, "listen", ":7400", "Web UI listen address")
	rootCmd.AddCommand(startCmd, runCmd, stopCmd, restartCmd, statusCmd, setupCmd, installSvcCmd, uninstallSvcCmd, serveCmd, versionCmd)
	return rootCmd.Execute()
}

func getDataDir() string {
	if cfgDir != "" {
		return cfgDir
	}
	return service.HomeDataDir()
}

func ensureDataDir() string {
	dir := getDataDir()
	os.MkdirAll(dir, 0o700)
	return dir
}

func pidFilePath() string { return filepath.Join(ensureDataDir(), "meilink.pid") }

func writePIDFile() error {
	return os.WriteFile(pidFilePath(), []byte(fmt.Sprintf("%d", os.Getpid())), 0o600)
}

func removePIDFile() { os.Remove(pidFilePath()) }

func readPIDFile() (int, bool) {
	data, err := os.ReadFile(pidFilePath())
	if err != nil {
		return 0, false
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(data)))
	if err != nil || pid <= 0 {
		return 0, false
	}
	return pid, true
}

// processAlive reports whether a process with the given PID exists.
func processAlive(pid int) bool {
	if pid <= 0 {
		return false
	}
	proc, err := os.FindProcess(pid)
	if err != nil {
		return false
	}
	// Send signal 0 to check existence. On Windows os.FindProcess always
	// succeeds, so we additionally try a no-op via tasklist below.
	if runtime.GOOS == "windows" {
		out, err := exec.Command("tasklist", "/FI", fmt.Sprintf("PID eq %d", pid), "/NH").CombinedOutput()
		return err == nil && strings.Contains(string(out), strconv.Itoa(pid))
	}
	return proc.Signal(syscall.Signal(0)) == nil
}

func getManager() (*tunnel.Manager, *config.Manager, error) {
	dir := getDataDir()
	cfgMgr, err := config.NewManager(dir)
	if err != nil {
		return nil, nil, err
	}
	mgr, err := tunnel.NewManager(dir)
	if err != nil {
		return nil, nil, err
	}
	return mgr, cfgMgr, nil
}

// runForeground is the implementation for both `start` and `run`. It starts the
// web server + frpc, writes a PID file, and blocks on SIGINT/SIGTERM.
func runForeground() error {
	mgr, cfgMgr, err := getManager()
	if err != nil {
		return err
	}

	webServer := web.NewServer(mgr, cfgMgr, listenAddr)
	if err := webServer.Start(); err != nil {
		return fmt.Errorf("start web server: %w", err)
	}

	// Auto-start frpc if configured and settings.autoStart is on.
	if mgr.IsConfigured() {
		s := mgr.Settings()
		if s != nil && s.AutoStart {
			if err := mgr.Start(); err != nil {
				fmt.Fprintf(os.Stderr, "warning: auto-start failed: %v\n", err)
			}
		}
	}

	if err := writePIDFile(); err != nil {
		fmt.Fprintf(os.Stderr, "warning: cannot write PID file: %v\n", err)
	}
	defer removePIDFile()

	fmt.Printf("Meilink is running. Web UI: http://localhost%s\n", normalizeListen(listenAddr))

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	<-sigCh

	fmt.Println("\nShutting down...")
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	webServer.Stop(ctx)
	mgr.Stop()
	return nil
}

func normalizeListen(addr string) string {
	if strings.HasPrefix(addr, ":") {
		return addr
	}
	return addr
}

// runSidecar runs the HTTP API server on an auto-selected port (127.0.0.1:0)
// and writes the actual port to sidecar.port in the shared data directory.
// The desktop GUI reads the port file to discover the API endpoint.
func runSidecar() error {
	mgr, cfgMgr, err := getManager()
	if err != nil {
		return err
	}

	// Listen on 127.0.0.1 with an OS-assigned port.
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return fmt.Errorf("listen: %w", err)
	}
	actualPort := ln.Addr().(*net.TCPAddr).Port

	// Write the port file to the same directory the config manager uses
	// (so the Rust shell finds it in the shared/native config dir on macOS).
	dir := filepath.Dir(cfgMgr.FrpcConfigPath())
	portFile := filepath.Join(dir, "sidecar.port")
	if err := os.WriteFile(portFile, []byte(fmt.Sprintf("%d", actualPort)), 0o600); err != nil {
		return fmt.Errorf("write port file: %w", err)
	}
	defer os.Remove(portFile)

	webServer := web.NewServerWithListener(mgr, cfgMgr, ln)
	if err := webServer.Start(); err != nil {
		return fmt.Errorf("start web server: %w", err)
	}

	// Auto-start frpc if configured and settings.autoStart is on.
	if mgr.IsConfigured() {
		s := mgr.Settings()
		if s != nil && s.AutoStart {
			if err := mgr.Start(); err != nil {
				fmt.Fprintf(os.Stderr, "warning: auto-start frpc failed: %v\n", err)
			}
		}
	}

	fmt.Printf("Meilink sidecar listening on 127.0.0.1:%d\n", actualPort)

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	<-sigCh

	fmt.Fprintln(os.Stderr, "sidecar shutting down...")
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	webServer.Stop(ctx)
	mgr.Stop()
	return nil
}

// serviceAvailable reports whether the client is registered as a system service.
func serviceAvailable() bool {
	switch runtime.GOOS {
	case "windows":
		out, _ := exec.Command("sc", "query", "ex", "type=service", "state=all").CombinedOutput()
		return strings.Contains(string(out), serviceName)
	case "darwin":
		// launchd plist lives in ~/Library/LaunchAgents or /Library/LaunchAgents.
		home, _ := os.UserHomeDir()
		candidates := []string{
			filepath.Join(home, "Library", "LaunchAgents", launchdLabel+".plist"),
			filepath.Join("/Library", "LaunchAgents", launchdLabel+".plist"),
			filepath.Join("/Library", "LaunchDaemons", launchdLabel+".plist"),
		}
		for _, c := range candidates {
			if _, err := os.Stat(c); err == nil {
				return true
			}
		}
		return false
	default: // linux / systemd
		if _, err := exec.LookPath("systemctl"); err == nil {
			_, err := exec.Command("systemctl", "cat", serviceName).CombinedOutput()
			return err == nil
		}
		return false
	}
}

func stopClient() error {
	if serviceAvailable() {
		if err := stopSystemService(); err != nil {
			fmt.Fprintf(os.Stderr, "service stop failed, falling back to PID: %v\n", err)
		} else {
			fmt.Println("Meilink service stopped.")
			return nil
		}
	}
	// PID fallback
	pid, ok := readPIDFile()
	if !ok {
		fmt.Println("Meilink is not running (no PID file and no service).")
		return nil
	}
	if !processAlive(pid) {
		removePIDFile()
		fmt.Println("Meilink is not running (stale PID file removed).")
		return nil
	}
	if runtime.GOOS == "windows" {
		exec.Command("taskkill", "/PID", strconv.Itoa(pid), "/F").Run()
	} else {
		proc, _ := os.FindProcess(pid)
		proc.Signal(syscall.SIGTERM)
		// wait up to 5s
		for i := 0; i < 50; i++ {
			if !processAlive(pid) {
				break
			}
			time.Sleep(100 * time.Millisecond)
		}
		if processAlive(pid) {
			proc.Signal(syscall.SIGKILL)
		}
	}
	removePIDFile()
	fmt.Println("Meilink stopped.")
	return nil
}

func restartClient() error {
	if serviceAvailable() {
		if err := restartSystemService(); err != nil {
			return err
		}
		fmt.Println("Meilink service restarted.")
		return nil
	}
	// PID fallback: stop then start (start re-launches in foreground; the
	// caller would need to re-run start in a new terminal). For a true
	// background restart without a service, advise installing a service.
	if err := stopClient(); err != nil {
		return err
	}
	fmt.Println("Run 'meilink start' to launch again.")
	return nil
}

func stopSystemService() error {
	switch runtime.GOOS {
	case "windows":
		return runSvc("stop", serviceName)
	case "darwin":
		out, err := exec.Command("launchctl", "bootout", "gui/$(id -u)/"+launchdLabel).CombinedOutput()
		if err != nil && !strings.Contains(string(out), "No such") {
			return fmt.Errorf("launchctl bootout: %s: %w", out, err)
		}
		return nil
	default:
		return runSvc("stop", serviceName)
	}
}

func restartSystemService() error {
	switch runtime.GOOS {
	case "windows":
		return runSvc("stop", serviceName)
	case "darwin":
		if err := stopSystemService(); err != nil {
			return err
		}
		time.Sleep(time.Second)
		return launchctlLoad()
	default:
		return runSvc("restart", serviceName)
	}
}

func runSvc(action, name string) error {
	cmd := exec.Command("systemctl", action, name)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("systemctl %s %s: %w", action, name, err)
	}
	return nil
}

func showStatus() error {
	mgr, _, err := getManager()
	if err != nil {
		return err
	}

	// Service status takes precedence when registered.
	if serviceAvailable() {
		fmt.Println("Mode: system service")
		printServiceStatus()
	} else {
		pid, ok := readPIDFile()
		if ok && processAlive(pid) {
			fmt.Println("Mode: foreground")
			fmt.Printf("PID: %d\n", pid)
		} else {
			if ok {
				removePIDFile()
			}
			fmt.Println("Mode: stopped")
		}
	}

	fmt.Println()
	if !mgr.IsConfigured() {
		fmt.Println("Server config: not configured")
	} else {
		fmt.Println("Server config: configured")
	}
	fmt.Printf("frpc running: %v\n", mgr.IsRunning())
	fmt.Printf("Connected:    %v\n", mgr.IsConnected())
	tunnels := mgr.GetTunnels()
	fmt.Printf("Tunnels:      %d (%d enabled)\n", len(tunnels), countEnabled(tunnels))
	return nil
}

func printServiceStatus() {
	switch runtime.GOOS {
	case "windows":
		cmd := exec.Command("sc", "query", serviceName)
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		cmd.Run()
	case "darwin":
		cmd := exec.Command("launchctl", "list", launchdLabel)
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		cmd.Run()
	default:
		cmd := exec.Command("systemctl", "status", serviceName, "--no-pager")
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		cmd.Run()
	}
}

func countEnabled(tunnels []config.Tunnel) int {
	n := 0
	for _, t := range tunnels {
		if t.Enabled {
			n++
		}
	}
	return n
}

func runSetup() error {
	reader := bufio.NewReader(os.Stdin)
	fmt.Println("=== Meilink Setup Wizard ===")
	fmt.Println()

	var cfg config.ServerConfig
	cfg.ServerPort = 7000
	cfg.AdminPort = 7400
	cfg.AdminUser = "admin"
	cfg.AdminPassword = "admin"

	cfg.ServerAddr = prompt(reader, "Server address (VPS IP or domain): ")
	cfg.ServerPort = promptInt(reader, "Server port [7000]: ", 7000)
	cfg.AuthToken = prompt(reader, "Auth token: ")
	cfg.SubDomainHost = prompt(reader, "Sub-domain host (e.g. tunnel.yourdomain.com): ")
	cfg.TLSEnabled = promptBool(reader, "Enable TLS [Y/n]: ", true)
	cfg.AdminPort = promptInt(reader, "Admin API port [7400]: ", 7400)

	dir := getDataDir()
	cfgMgr, err := config.NewManager(dir)
	if err != nil {
		return err
	}
	if err := cfgMgr.SaveServerConfig(&cfg); err != nil {
		return err
	}

	fmt.Println()
	fmt.Println("Configuration saved!")
	fmt.Printf("Data directory: %s\n", dir)
	fmt.Println("Next: run 'meilink start' and open http://localhost:7400")
	return nil
}

func installService() error {
	exePath, err := os.Executable()
	if err != nil {
		return err
	}
	dataDir := getDataDir()
	fmt.Println("Installing Meilink as a system service...")
	fmt.Printf("  Executable: %s\n", exePath)
	fmt.Printf("  Data dir:   %s\n", dataDir)

	cfg := service.ServiceConfig{
		Name:        serviceName,
		DisplayName: "Meilink Tunnel Client",
		Description: "Cross-platform frp tunnel client with web management UI.",
		ExecPath:    exePath,
		Args:        []string{"run", "--config-dir", dataDir},
		WorkingDir:  dataDir,
	}
	if err := service.Install(cfg); err != nil {
		return err
	}
	fmt.Println("The service is enabled and will auto-start on boot.")
	return nil
}

func uninstallService() error {
	if err := service.Uninstall(serviceName); err != nil {
		return err
	}
	return nil
}

// launchctlLoad loads the per-user launchd plist after a restart.
func launchctlLoad() error {
	home, err := os.UserHomeDir()
	if err != nil {
		return err
	}
	plist := filepath.Join(home, "Library", "LaunchAgents", launchdLabel+".plist")
	if _, err := os.Stat(plist); err != nil {
		return nil // nothing to load
	}
	out, err := exec.Command("launchctl", "bootstrap", "gui/$(id -u)", plist).CombinedOutput()
	if err != nil {
		return fmt.Errorf("launchctl bootstrap: %s: %w", out, err)
	}
	return nil
}

// --- prompt helpers ---

func prompt(r *bufio.Reader, label string) string {
	fmt.Print(label)
	line, _ := r.ReadString('\n')
	return strings.TrimSpace(line)
}

func promptInt(r *bufio.Reader, label string, def int) int {
	s := prompt(r, label)
	if s == "" {
		return def
	}
	v, err := strconv.Atoi(s)
	if err != nil {
		return def
	}
	return v
}

func promptBool(r *bufio.Reader, label string, def bool) bool {
	s := strings.ToLower(prompt(r, label))
	if s == "" {
		return def
	}
	return s != "n" && s != "no"
}
