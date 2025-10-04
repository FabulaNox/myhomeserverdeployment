package cmd

import (
	"fmt"
	"log"
	"os"

	"github.com/FabulaNox/go-docker-tools/config"
	"github.com/FabulaNox/go-docker-tools/internal"
)

func RestoreCommand(conf *config.Config, dockerHelper *internal.DockerHelper, logger *log.Logger, args []string) {
	lock := internal.NewLockfileHelper(conf.StateFile + ".lock")
	if !lock.TryLock() {
		logger.Println("Another restore is in progress.")
		internal.SendSlackNotification("[ERROR] Another restore is in progress.")
		return
	}
	defer lock.Unlock()

	restored, failed, err := internal.RestoreStateHelper(conf.StateFile, dockerHelper, logger)
	if err != nil {
		logger.Println("Failed to restore state:", err)
		internal.SendSlackNotification("[ERROR] Failed to restore state: " + err.Error())
		os.Exit(1)
	}
	msg := fmt.Sprintf("Restore complete. Started: %d, Failed: %d.", restored, failed)
	logger.Print(msg)
	fmt.Println(msg)
	internal.SendSlackNotification("[NOTIFY] " + msg)
}
