package internal

import (
	"go-docker-tools/config"
	"log"
	"os/exec"
)

// RestoreVolumesFromFile restores all volumes from a given tar.gz file
func RestoreVolumesFromFile(conf *config.Config, dockerHelper *DockerHelper, logger *log.Logger, backupFile string) error {
	cmd := exec.Command("docker", "run", "--rm", "-v", "/var/lib/docker/volumes:/volumes", "-v", backupFile+":/backup/restore.tar.gz", "alpine", "tar", "xzf", "/backup/restore.tar.gz", "-C", "/volumes")
	return cmd.Run()
}
