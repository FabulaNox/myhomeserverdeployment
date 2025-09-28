package internal

import (
	"encoding/json"
	"github.com/docker/docker/api/types"
	"os"
	"log"
)

func SaveStateHelper(containers []types.Container, stateFile string, logger *log.Logger) error {
	f, err := os.OpenFile(stateFile, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0600)
	if err != nil {
		return err
	}
	defer f.Close()
	enc := json.NewEncoder(f)
	if err := enc.Encode(containers); err != nil {
		return err
	}
	logger.Printf("Saved %d containers to %s", len(containers), stateFile)
	return nil
}
