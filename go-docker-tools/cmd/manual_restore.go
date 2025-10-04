package cmd

import (
	"bufio"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/FabulaNox/go-docker-tools/config"
	"github.com/FabulaNox/go-docker-tools/internal"
)

// ManualRestoreCommand lists available manual backups and restores from a selected one
func ManualRestoreCommand(conf *config.Config, dockerHelper *internal.DockerHelper, logger *log.Logger, args []string) {
	manualDir := filepath.Join(conf.BackupDir, "manual_backups")
	files, err := filepath.Glob(filepath.Join(manualDir, "manual_*.tar.gz"))
	if err != nil || len(files) == 0 {
		fmt.Println("[ERROR] No manual backups found.")
		internal.SendSlackNotification("[ERROR] No manual backups found.")
		os.Exit(1)
	}
	sort.Strings(files)
	fmt.Println("Available manual backups:")
	for i, f := range files {
		fmt.Printf("[%d] %s\n", i+1, filepath.Base(f))
	}
	var choice int
	if len(args) > 0 {
		// Allow restore by index or filename
		if n, err := fmt.Sscanf(args[0], "%d", &choice); n == 1 && err == nil && choice > 0 && choice <= len(files) {
			// valid index
		} else {
			// try filename match
			for i, f := range files {
				if strings.TrimSpace(args[0]) == filepath.Base(f) {
					choice = i + 1
					break
				}
			}
		}
	} else {
		fmt.Print("Enter backup number to restore: ")
		scan := bufio.NewScanner(os.Stdin)
		if scan.Scan() {
			fmt.Sscanf(scan.Text(), "%d", &choice)
		}
	}
	if choice < 1 || choice > len(files) {
		fmt.Println("[ERROR] Invalid selection.")
		os.Exit(2)
	}
	backupFile := files[choice-1]
	logger.Println("[USER] Manual restore started:", backupFile)
	fmt.Println("[NOTIFY] Restoring from manual backup:", backupFile)
	if err := internal.RestoreVolumesFromFile(conf, dockerHelper, logger, backupFile); err != nil {
		logger.Println("[ERROR] Manual restore failed:", err)
		fmt.Println("[ERROR] Manual restore failed:", err)
		internal.SendSlackNotification("[ERROR] Manual restore failed: " + err.Error())
		os.Exit(3)
	}
	msg := fmt.Sprintf("[NOTIFY] Manual restore completed: %s", backupFile)
	logger.Println("[USER] Manual restore completed:", backupFile)
	fmt.Println(msg)
	internal.SendSlackNotification(msg)
}
