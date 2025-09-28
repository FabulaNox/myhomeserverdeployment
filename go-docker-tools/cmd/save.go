package cmd

import (
	"fmt"
	"go-docker-tools/config"
	"go-docker-tools/internal"
	"os"
)

func SaveCommand(conf *config.Config, dockerHelper *internal.DockerHelper, logger *internal.Logger, args []string) {
	lock := internal.NewLockfileHelper(conf.StateFile + ".lock")
	if !lock.TryLock() {
		logger.Println("Another save is in progress.")
		return
	}
	defer lock.Unlock()

	containers, err := dockerHelper.ListRunningContainers()
	if err != nil {
		logger.Println("Failed to list running containers:", err)
		os.Exit(1)
	}
	if err := internal.SaveStateHelper(containers, conf.StateFile, logger); err != nil {
		logger.Println("Failed to save state:", err)
		os.Exit(1)
	}
	logger.Println("State saved successfully.")
	fmt.Println("State saved successfully.")
}
