package internal

import (
	"encoding/json"
	"github.com/docker/docker/api/types"
	"os"
	"log"
)

func RestoreStateHelper(stateFile string, dockerHelper *DockerHelper, logger *log.Logger) (restored int, failed int, err error) {
	f, err := os.Open(stateFile)
	if err != nil {
		return 0, 0, err
	}
	defer f.Close()
	var containers []types.Container
	dec := json.NewDecoder(f)
	if err := dec.Decode(&containers); err != nil {
		return 0, 0, err
	}
	for _, c := range containers {
		if err := dockerHelper.StartContainerByID(c.ID); err != nil {
			logger.Printf("Failed to start container %s: %v", c.ID, err)
			failed++
		} else {
			logger.Printf("Started container %s", c.ID)
			restored++
		}
	}
	return restored, failed, nil
}
