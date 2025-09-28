package cmd

import (
	"fmt"
	"go-docker-tools/config"
	"go-docker-tools/internal"
	"log"
)

// AutostartCommand starts containers marked for autostart in config or by label.
func AutostartCommand(conf *config.Config, dockerHelper *internal.DockerHelper, logger *log.Logger, args []string) {
	containers, err := dockerHelper.ListAllContainers()
	if err != nil {
		logger.Println("Failed to list containers:", err)
		return
	}
	count := 0
	for _, c := range containers {
		if c.Labels["autostart"] == "true" {
			err := dockerHelper.StartContainerByID(c.ID)
			if err != nil {
				logger.Printf("Failed to start container %s: %v", c.Names[0], err)
				continue
			}
			logger.Printf("Started container: %s", c.Names[0])
			count++
		}
	}
	fmt.Printf("Autostarted %d containers.\n", count)
}
