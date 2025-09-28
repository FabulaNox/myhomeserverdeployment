package cmd

import (
	"fmt"
	"go-docker-tools/config"
	"go-docker-tools/internal"
	"os"
)

func BackupCommand(conf *config.Config, dockerHelper *internal.DockerHelper, logger *internal.Logger, args []string) {
	lock := internal.NewLockfileHelper(conf.BackupDir + ".lock")
	if !lock.TryLock() {
		logger.Println("Another backup is in progress.")
		return
	}
	defer lock.Unlock()

	if err := internal.BackupVolumesHelper(conf, dockerHelper, logger); err != nil {
		logger.Println("Backup failed:", err)
		os.Exit(1)
	}
	logger.Println("Backup completed successfully.")
	fmt.Println("Backup completed successfully.")
}
