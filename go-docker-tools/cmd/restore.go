package cmd

import (
	"fmt"
	"go-docker-tools/config"
	"go-docker-tools/internal"
	"os"
)

func RestoreCommand(conf *config.Config, dockerHelper *internal.DockerHelper, logger *internal.Logger, args []string) {
	lock := internal.NewLockfileHelper(conf.StateFile + ".lock")
	if !lock.TryLock() {
		logger.Println("Another restore is in progress.")
		return
	}
	defer lock.Unlock()

	restored, failed, err := internal.RestoreStateHelper(conf.StateFile, dockerHelper, logger)
	if err != nil {
		logger.Println("Failed to restore state:", err)
		os.Exit(1)
	}
	logger.Printf("Restore complete. Started: %d, Failed: %d.", restored, failed)
	fmt.Printf("Restore complete. Started: %d, Failed: %d.\n", restored, failed)
}
