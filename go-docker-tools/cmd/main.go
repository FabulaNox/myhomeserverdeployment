package cmd

import (
	"fmt"
	"os"
	"os/signal"
	"syscall"
)

func main() {
	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-sigs
		// Add any cleanup logic here if needed
		fmt.Println("\n[NOTIFY] Received interrupt. Exiting gracefully.")
		os.Exit(130)
	}()
	if len(os.Args) < 2 {
		fmt.Println("Usage: docker-tools <command> [flags]")
		os.Exit(1)
	}
	MainLogic()
}
