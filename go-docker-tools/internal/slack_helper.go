package internal

import (
	"fmt"
	"os"
	"net/http"
	"bytes"
)

// SendSlackNotification sends a message to a Slack webhook if SLACK_WEBHOOK_URL is set
func SendSlackNotification(message string) {
	webhook := os.Getenv("SLACK_WEBHOOK_URL")
	if webhook == "" {
		return
	}
	payload := fmt.Sprintf(`{"text": "%s"}`, message)
	resp, err := http.Post(webhook, "application/json", bytes.NewBuffer([]byte(payload)))
	if err != nil {
		fmt.Fprintf(os.Stderr, "[SLACK] Failed to send notification: %v\n", err)
		return
	}
	defer resp.Body.Close()
}
