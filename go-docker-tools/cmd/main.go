package cmd

import (
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/FabulaNox/go-docker-tools/config"
	"github.com/FabulaNox/go-docker-tools/internal"
)

func main() {
	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-sigs
		// Add any cleanup logic here if needed
		fmt.Println("\n[NOTIFY] Received interrupt. Exiting gracefully.")
		os.Exit(130)
	}()
	// Load config, logger, dockerHelper for Slack integration
	conf, err := config.LoadConfig()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to load config: %v\n", err)
		os.Exit(1)
	}
	logger := internal.NewLogger(conf.LogFile)
	dockerHelper, err := internal.NewDockerHelper()
	if err != nil {
		logger.Println("Failed to initialize Docker client:", err)
		os.Exit(1)
	}
	// Start Slack HTTP server in background
	internal.StartSlackServer(":8080", conf, logger, dockerHelper)

	if len(os.Args) < 2 {
		fmt.Println("Usage: docker-tools <command> [flags]")
		os.Exit(1)
	}
	MainLogic()
}
