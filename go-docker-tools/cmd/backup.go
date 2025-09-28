package cmd

import (
	"fmt"
	"go-docker-tools/config"
	"go-docker-tools/internal"
	"os"
)

func BackupCommand(conf *config.Config, dockerHelper *internal.DockerHelper, logger *internal.Logger, args []string) {
       dryRun := false
       for _, arg := range args {
              if arg == "--dry-run" {
                     dryRun = true
              }
       }
       lock := internal.NewLockfileHelper(conf.BackupDir + ".lock")
       if !lock.TryLock() {
              logger.Println("Another backup is in progress.")
              internal.RunHook(conf.HookScript, "backup_locked")
              os.Exit(10)
       }
       defer lock.Unlock()

       internal.RunHook(conf.HookScript, "pre_backup")
       fmt.Println("[NOTIFY] Starting backup... (dry-run:", dryRun, ")")
       if dryRun {
              logger.Println("[DRY-RUN] Would perform backup and rotation.")
              fmt.Println("[DRY-RUN] Would perform backup and rotation.")
              os.Exit(0)
       }
       if err := internal.BackupVolumesHelper(conf, dockerHelper, logger); err != nil {
              logger.Println("Backup failed:", err)
              internal.RunHook(conf.HookScript, "backup_failed")
              os.Exit(11)
       }
       logger.Println("Backup completed successfully.")
       fmt.Println("[NOTIFY] Backup completed successfully.")
       internal.RunHook(conf.HookScript, "post_backup")
}
