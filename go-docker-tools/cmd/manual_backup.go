package cmd

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"time"

	"github.com/FabulaNox/go-docker-tools/config"
	"github.com/FabulaNox/go-docker-tools/internal"
)

// ManualBackupCommand creates a user-initiated backup and manages manual backup rotation
func ManualBackupCommand(conf *config.Config, dockerHelper *internal.DockerHelper, logger *log.Logger, args []string) {
	manualDir := filepath.Join(conf.BackupDir, "manual_backups")
	if err := os.MkdirAll(manualDir, 0755); err != nil {
		logger.Println("[ERROR] Failed to create manual backup dir:", err)
		internal.SendSlackNotification("[ERROR] Failed to create manual backup dir: " + err.Error())
		os.Exit(1)
	}
	backupFile := filepath.Join(manualDir, fmt.Sprintf("manual_%s.tar.gz", time.Now().Format("20060102T150405")))
	logger.Println("[USER] Manual backup started:", backupFile)
	msg := fmt.Sprintf("[NOTIFY] Creating manual backup: %s", backupFile)
	fmt.Println(msg)
	internal.SendSlackNotification(msg)
	if err := internal.BackupVolumesToFile(conf, dockerHelper, logger, backupFile); err != nil {
		logger.Println("[ERROR] Manual backup failed:", err)
		fmt.Println("[ERROR] Manual backup failed:", err)
		internal.SendSlackNotification("[ERROR] Manual backup failed: " + err.Error())
		os.Exit(2)
	}
	logger.Println("[USER] Manual backup completed:", backupFile)
	msg = fmt.Sprintf("[NOTIFY] Manual backup completed: %s", backupFile)
	fmt.Println(msg)
	internal.SendSlackNotification(msg)
	// Rotate manual backups (keep last 5)
	internal.RotateManualBackups(manualDir, 5, logger)
}
