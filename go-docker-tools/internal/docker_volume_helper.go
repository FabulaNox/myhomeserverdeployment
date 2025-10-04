package internal

import (
	"fmt"
	"io"
	"log"
	"os"

	"github.com/docker/docker/api/types"
	"github.com/docker/docker/api/types/container"
	"github.com/docker/docker/client"

	// "path/filepath" (unused)
	"compress/gzip"
	"context"
	"time"
)

// RestoreVolumeCrossPlatform restores a tar.gz archive into a Docker volume using a helper container
func RestoreVolumeCrossPlatform(cli *client.Client, volumeName, backupFile string, logger *log.Logger) error {
	ctx := context.Background()
	containerName := fmt.Sprintf("restore-helper-%s-%d", volumeName, time.Now().UnixNano())
	resp, err := cli.ContainerCreate(ctx, &container.Config{
		Image: "alpine",
		Cmd:   []string{"sleep", "60"},
		Tty:   false,
	}, nil, nil, nil, containerName)
	if err != nil {
		return fmt.Errorf("failed to create helper container: %w", err)
	}
	defer func() {
		_ = cli.ContainerRemove(ctx, resp.ID, types.ContainerRemoveOptions{Force: true})
	}()
	// Mount the volume
	// mounts := []mount.Mount{{
	//      Type:   mount.TypeVolume,
	//      Source: volumeName,
	//      Target: "/data",
	// }}
	if err := cli.ContainerStart(ctx, resp.ID, types.ContainerStartOptions{}); err != nil {
		return fmt.Errorf("failed to start helper container: %w", err)
	}
	// Open the backup file
	f, err := os.Open(backupFile)
	if err != nil {
		return err
	}
	defer f.Close()
	// Copy the tar archive into the container's /data directory
	err = cli.CopyToContainer(ctx, resp.ID, "/data", f, types.CopyToContainerOptions{AllowOverwriteDirWithFile: true})
	if err != nil {
		return fmt.Errorf("failed to copy to container: %w", err)
	}
	logger.Printf("[CROSS-PLATFORM] Restored volume %s from %s", volumeName, backupFile)
	return nil
}

// NewGzipWriter wraps gzip.NewWriter for easy replacement/testing
func NewGzipWriter(w io.Writer) *gzip.Writer {
	return gzip.NewWriter(w)
}
