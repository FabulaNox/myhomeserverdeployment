package internal

import (
	"context"
	"github.com/docker/docker/api/types"
	"github.com/docker/docker/client"
)

type DockerHelper struct {
	cli *client.Client
}

func NewDockerHelper() (*DockerHelper, error) {
	cli, err := client.NewClientWithOpts(client.FromEnv)
	if err != nil {
		return nil, err
	}
	return &DockerHelper{cli: cli}, nil
}

func (d *DockerHelper) ListRunningContainers() ([]types.Container, error) {
	return d.cli.ContainerList(context.Background(), types.ContainerListOptions{All: false})
}

// StartContainerByID starts a container by its ID
func (d *DockerHelper) StartContainerByID(id string) error {
	return d.cli.ContainerStart(context.Background(), id, types.ContainerStartOptions{})
}

// ListAllContainers returns all containers (running and stopped)
func (d *DockerHelper) ListAllContainers() ([]types.Container, error) {
	return d.cli.ContainerList(context.Background(), types.ContainerListOptions{All: true})
}

// StopContainerByID stops a container by its ID
func (d *DockerHelper) StopContainerByID(id string) error {
	return d.cli.ContainerStop(context.Background(), id, nil)
}
