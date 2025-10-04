package cmd

import (
	"fmt"
	"log"
	"os"

	"github.com/FabulaNox/go-docker-tools/config"
	"github.com/FabulaNox/go-docker-tools/internal"
)

func SaveCommand(conf *config.Config, dockerHelper *internal.DockerHelper, logger *log.Logger, args []string) {
	lock := internal.NewLockfileHelper(conf.StateFile + ".lock")
	if !lock.TryLock() {
		logger.Println("Another save is in progress.")
		internal.SendSlackNotification("[ERROR] Another save is in progress.")
		return
	}
	defer lock.Unlock()

	containers, err := dockerHelper.ListRunningContainers()
	if err != nil {
		logger.Println("Failed to list running containers:", err)
		internal.SendSlackNotification("[ERROR] Failed to list running containers: " + err.Error())
		os.Exit(1)
	}
	if err := internal.SaveStateHelper(containers, conf.StateFile, logger); err != nil {
		logger.Println("Failed to save state:", err)
		internal.SendSlackNotification("[ERROR] Failed to save state: " + err.Error())
		os.Exit(1)
	}
	logger.Println("State saved successfully.")
	fmt.Println("State saved successfully.")
	internal.SendSlackNotification("[NOTIFY] State saved successfully.")
}
