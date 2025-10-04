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
		internal.SendSlackNotification("[ERROR] Failed to list containers: " + err.Error())
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
				internal.SendSlackNotification("[ERROR] Failed to stop container " + c.Names[0] + ": " + err.Error())
				continue
			}
			logger.Printf("Stopped container: %s", c.Names[0])
			msg := fmt.Sprintf("[NOTIFY] Stopped container: %s", c.Names[0])
			fmt.Println(msg)
			internal.SendSlackNotification(msg)
			count++
		}
	}
	msg := fmt.Sprintf("[NOTIFY] Autostopped %d containers.", count)
	fmt.Println(msg)
	internal.SendSlackNotification(msg)
	internal.RunHook(conf.HookScript, "post_exit")
}
