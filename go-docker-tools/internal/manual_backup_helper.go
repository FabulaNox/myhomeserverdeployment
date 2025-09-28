package internal

import (
	"go-docker-tools/config"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
)

// BackupVolumesToFile backs up all volumes to a single tar.gz file
func BackupVolumesToFile(conf *config.Config, dockerHelper *DockerHelper, logger *log.Logger, backupFile string) error {
	cmd := exec.Command("docker", "run", "--rm", "-v", "/var/lib/docker/volumes:/volumes", "-v", filepath.Dir(backupFile)+":/backup", "alpine", "tar", "czf", "/backup/"+filepath.Base(backupFile), "-C", "/volumes", ".")
	return cmd.Run()
}

// RotateManualBackups keeps only the most recent n manual backups
func RotateManualBackups(dir string, keep int, logger *log.Logger) {
	files, err := filepath.Glob(filepath.Join(dir, "manual_*.tar.gz"))
	if err != nil || len(files) <= keep {
		return
	}
	type fileInfo struct {
		path string
		time int64
	}
	var infos []fileInfo
	for _, f := range files {
		fi, err := os.Stat(f)
		if err == nil {
			infos = append(infos, fileInfo{f, fi.ModTime().Unix()})
		}
	}
	sort.Slice(infos, func(i, j int) bool { return infos[i].time < infos[j].time })
	for i := 0; i < len(infos)-keep; i++ {
		os.Remove(infos[i].path)
		logger.Println("[USER] Removed old manual backup:", infos[i].path)
	}
}
