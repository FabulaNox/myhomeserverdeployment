package cmd

import (
	"fmt"
	"log"
	"os"

	"github.com/FabulaNox/go-docker-tools/config"
	"github.com/FabulaNox/go-docker-tools/internal"
)

// ExitCommand stops all running containers marked for autostop in config or by label.
func ExitCommand(conf *config.Config, dockerHelper *internal.DockerHelper, logger *log.Logger, args []string) {
	dryRun := false
	for _, arg := range args {
		if arg == "--dry-run" {
			dryRun = true
		}
	}
	internal.RunHook(conf.HookScript, "pre_exit")
	fmt.Println("[NOTIFY] Starting exit... (dry-run:", dryRun, ")")
	containers, err := dockerHelper.ListAllContainers()
	if err != nil {
		logger.Println("Failed to list containers:", err)
		internal.RunHook(conf.HookScript, "exit_failed")
		os.Exit(31)
	}
	count := 0
	for _, c := range containers {
		if c.Labels["autostop"] == "true" && c.State == "running" {
			if dryRun {
				logger.Printf("[DRY-RUN] Would stop container: %s", c.Names[0])
				fmt.Printf("[DRY-RUN] Would stop container: %s\n", c.Names[0])
				count++
				continue
			}
			err := dockerHelper.StopContainerByID(c.ID)
			if err != nil {
				logger.Printf("Failed to stop container %s: %v", c.Names[0], err)
				continue
			}
			logger.Printf("Stopped container: %s", c.Names[0])
			fmt.Printf("[NOTIFY] Stopped container: %s\n", c.Names[0])
			count++
		}
	}
	fmt.Printf("[NOTIFY] Autostopped %d containers.\n", count)
	internal.RunHook(conf.HookScript, "post_exit")
}
