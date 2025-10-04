package cmd

import (
	"fmt"
	"os"

	"github.com/FabulaNox/go-docker-tools/config"
	"github.com/FabulaNox/go-docker-tools/internal"
)

func MainLogic() {
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
	// Command dispatch
	if len(os.Args) < 2 {
		fmt.Println("Usage: docker-tools <command> [flags]")
		os.Exit(1)
	}
	switch os.Args[1] {
	case "manual-restore":
		ManualRestoreCommand(conf, dockerHelper, logger, os.Args[2:])
	case "manual-backup":
		ManualBackupCommand(conf, dockerHelper, logger, os.Args[2:])
	case "bootstrap":
		BootstrapCommand(os.Args[2:])
	case "fixsocket":
		FixSocketCommand(os.Args[2:])
	case "deploy":
		DeployAutostartCommand(os.Args[2:])
	case "save":
		SaveCommand(conf, dockerHelper, logger, os.Args[2:])
	case "restore":
		RestoreCommand(conf, dockerHelper, logger, os.Args[2:])
	case "backup":
		BackupCommand(conf, dockerHelper, logger, os.Args[2:])
	case "autostart":
		AutostartCommand(conf, dockerHelper, logger, os.Args[2:])
	case "exit":
		ExitCommand(conf, dockerHelper, logger, os.Args[2:])
	case "setup":
		SetupCommand()
	default:
		fmt.Println("Unknown command:", os.Args[1])
		os.Exit(1)
	}
}
