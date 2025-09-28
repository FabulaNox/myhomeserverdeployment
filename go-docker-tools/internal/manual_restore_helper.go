package internal

import (
	"go-docker-tools/config"
	"log"
	"path/filepath"
)

// RestoreVolumesFromFile restores all volumes from a given tar.gz file (cross-platform)
func RestoreVolumesFromFile(conf *config.Config, dockerHelper *DockerHelper, logger *log.Logger, backupFile string) error {
       // For each volume, restore using the cross-platform helper
       // For simplicity, assume backupFile is for a single volume (as in manual restore)
       // If multi-volume, logic can be extended
       volName := filepath.Base(backupFile)
       // Remove .tar.gz and timestamp if present
       if idx := len(volName) - len(".tar.gz"); idx > 0 && volName[idx:] == ".tar.gz" {
	       volName = volName[:idx]
       }
       // Remove timestamp if present (e.g., vol_YYYYMMDDTHHMMSS)
       if i := len(volName) - 16; i > 0 && volName[i] == '_' {
	       volName = volName[:i]
       }
       err := RestoreVolumeCrossPlatform(dockerHelper.cli, volName, backupFile, logger)
       if err != nil {
	       logger.Printf("[ERROR] Manual restore failed for volume %s: %v", volName, err)
	       return err
       }
       logger.Printf("[USER] Manual restore (cross-platform) completed: %s", backupFile)
       return nil
}
