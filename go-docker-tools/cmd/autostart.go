package cmd

import (
	"fmt"
	"go-docker-tools/config"
	"go-docker-tools/internal"
	"log"
)

// AutostartCommand starts containers marked for autostart in config or by label.
func AutostartCommand(conf *config.Config, dockerHelper *internal.DockerHelper, logger *log.Logger, args []string) {
       dryRun := false
       for _, arg := range args {
	       if arg == "--dry-run" {
		       dryRun = true
	       }
       }
       internal.RunHook(conf.HookScript, "pre_autostart")
       fmt.Println("[NOTIFY] Starting autostart... (dry-run:", dryRun, ")")
       containers, err := dockerHelper.ListAllContainers()
       if err != nil {
	       logger.Println("Failed to list containers:", err)
	       internal.RunHook(conf.HookScript, "autostart_failed")
	       os.Exit(21)
       }
       count := 0
       for _, c := range containers {
	       if c.Labels["autostart"] == "true" {
		       if dryRun {
			       logger.Printf("[DRY-RUN] Would start container: %s", c.Names[0])
			       fmt.Printf("[DRY-RUN] Would start container: %s\n", c.Names[0])
			       count++
			       continue
		       }
		       err := dockerHelper.StartContainerByID(c.ID)
		       if err != nil {
			       logger.Printf("Failed to start container %s: %v", c.Names[0], err)
			       continue
		       }
		       logger.Printf("Started container: %s", c.Names[0])
		       fmt.Printf("[NOTIFY] Started container: %s\n", c.Names[0])
		       count++
	       }
       }
       fmt.Printf("[NOTIFY] Autostarted %d containers.\n", count)
       internal.RunHook(conf.HookScript, "post_autostart")
}
