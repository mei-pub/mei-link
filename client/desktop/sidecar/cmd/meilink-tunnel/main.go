// meilink-tunnel is a standalone tunnel engine binary that embeds frp as a
// library. It replaces the external frpc binary for clients that need a
// subprocess (macOS native Swift app, Docker container) while avoiding the
// antivirus false positives triggered by the well-known frpc binary name.
//
// It accepts the same frpc.toml configuration file format for backward
// compatibility, and exposes the same Admin API (HTTP on the configured
// webServer port) so existing client code can manage proxies without changes.
package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/fatedier/frp/pkg/config"
	"github.com/spf13/cobra"

	"github.com/meilink/desktop-sidecar/internal/engine"
)

var (
	configPath string
	version    = "dev"
)

var rootCmd = &cobra.Command{
	Use:   "meilink-tunnel",
	Short: "Meilink tunnel engine (embedded frp client)",
	Version: version,
	// When invoked without a subcommand (e.g. "meilink-tunnel -c frpc.toml",
	// matching frpc's CLI convention), default to running the engine.
	RunE: func(cmd *cobra.Command, args []string) error {
		return runEngine()
	},
}

var runCmd = &cobra.Command{
	Use:   "run",
	Short: "Run the tunnel engine",
	RunE: func(cmd *cobra.Command, args []string) error {
		return runEngine()
	},
}

func runEngine() error {
	if configPath == "" {
		return fmt.Errorf("--config is required (path to frpc.toml)")
	}

	// Load the frpc.toml file using frp's own parser for full compatibility.
	common, proxies, _, _, err := config.LoadClientConfig(configPath, false)
	if err != nil {
		return fmt.Errorf("load config %s: %w", configPath, err)
	}
	if common == nil {
		return fmt.Errorf("config %s has no common section", configPath)
	}

	cfg := engine.EngineConfig{
		ServerAddr:    common.ServerAddr,
		ServerPort:    common.ServerPort,
		AuthToken:     common.Auth.Token,
		TLSEnabled:    common.Transport.TLS.Enable != nil && *common.Transport.TLS.Enable,
		AdminAddr:     common.WebServer.Addr,
		AdminPort:     common.WebServer.Port,
		AdminUser:     common.WebServer.User,
		AdminPassword: common.WebServer.Password,
		StorePath:     common.Store.Path,
		LogLevel:      common.Log.Level,
	}

	eng := engine.New(cfg)
	if err := eng.SetProxies(proxies); err != nil {
		return fmt.Errorf("set initial proxies: %w", err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Handle graceful shutdown on SIGINT/SIGTERM.
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		sig := <-sigCh
		fmt.Fprintf(os.Stderr, "meilink-tunnel: received %v, shutting down\n", sig)
		eng.Stop()
		cancel()
	}()

	fmt.Fprintf(os.Stderr, "meilink-tunnel: connecting to %s:%d\n", cfg.ServerAddr, cfg.ServerPort)
	if cfg.AdminPort > 0 {
		fmt.Fprintf(os.Stderr, "meilink-tunnel: admin API on %s:%d\n", cfg.AdminAddr, cfg.AdminPort)
	}

	if err := eng.Start(ctx); err != nil {
		return fmt.Errorf("start engine: %w", err)
	}

	// Block until the engine stops (context cancelled or frp exits).
	<-eng.Done()
	return nil
}

func init() {
	// Accept frpc-compatible shorthand: meilink-tunnel -c frpc.toml
	rootCmd.Flags().StringVarP(&configPath, "config", "c", "", "Path to frpc.toml configuration file")
	runCmd.Flags().StringVar(&configPath, "config", "", "Path to frpc.toml configuration file")
	_ = runCmd.MarkFlagRequired("config")
	rootCmd.AddCommand(runCmd)
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}
