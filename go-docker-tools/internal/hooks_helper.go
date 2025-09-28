package internal

import (
	"fmt"
	"os/exec"
)

// RunHook executes a hook script if the path is set (pre/post events)
func RunHook(hookPath string, event string) {
	if hookPath == "" {
		return
	}
	cmd := exec.Command(hookPath, event)
	output, err := cmd.CombinedOutput()
	if err != nil {
		fmt.Printf("[HOOK] %s failed: %v\nOutput: %s\n", hookPath, err, string(output))
	} else {
		fmt.Printf("[HOOK] %s executed for event %s.\n", hookPath, event)
	}
}
