package cmd

import (
	"fmt"
	"go-docker-tools/config"
	"go-docker-tools/internal"
	"log"
	"os"
)

// ExitCommand stops all running containers marked for autostop in config or by label.
func ExitCommand(conf *config.Config, dockerHelper *internal.DockerHelper, logger *log.Logger, args []string) {
	containers, err := dockerHelper.ListAllContainers()
	if err != nil {
		logger.Println("Failed to list containers:", err)
		os.Exit(1)
	}
	count := 0
	for _, c := range containers {
		if c.Labels["autostop"] == "true" && c.State == "running" {
			err := dockerHelper.StopContainerByID(c.ID)
			if err != nil {
				logger.Printf("Failed to stop container %s: %v", c.Names[0], err)
				continue
			}
			logger.Printf("Stopped container: %s", c.Names[0])
			count++
		}
	}
	fmt.Printf("Autostopped %d containers.\n", count)
}
