package internal

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/FabulaNox/go-docker-tools/config"
)

// SlackService holds singletons for Slack-triggered actions
type SlackService struct {
	Conf         *config.Config
	Logger       *log.Logger
	DockerHelper *DockerHelper
}

var slackService *SlackService

// InitSlackService initializes the SlackService singletons
func InitSlackService(conf *config.Config, logger *log.Logger, dockerHelper *DockerHelper) {
	slackService = &SlackService{
		Conf:         conf,
		Logger:       logger,
		DockerHelper: dockerHelper,
	}
}

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

// SlackCommandHandler handles Slack slash commands and interactive actions
func SlackCommandHandler(w http.ResponseWriter, r *http.Request) {
	// Parse form for slash command or interactive payload
	r.ParseForm()
	if payload := r.FormValue("payload"); payload != "" {
		// Interactive action (button click)
		handleSlackInteraction(w, payload)
		return
	}
	// Slash command
	command := r.FormValue("command")
	// text := r.FormValue("text") // not used
	user := r.FormValue("user_name")
	switch {
	case strings.Contains(command, "backup"):
		go func() {
			SendSlackNotification(fmt.Sprintf(":floppy_disk: Manual backup requested by %s", user))
			if slackService != nil {
				err := BackupVolumesToFile(slackService.Conf, slackService.DockerHelper, slackService.Logger, slackService.Conf.BackupDir+"/manual_slack_"+fmt.Sprintf("%d", time.Now().Unix())+".tar.gz")
				if err != nil {
					SendSlackNotification(":x: Slack manual backup failed: " + err.Error())
				} else {
					SendSlackNotification(":white_check_mark: Slack manual backup completed.")
				}
			}
		}()
		respondEphemeral(w, "Manual backup started!")
	case strings.Contains(command, "restore"):
		go func() {
			SendSlackNotification(fmt.Sprintf(":package: Manual restore requested by %s", user))
			if slackService != nil {
				// Find latest manual backup
				files, _ := filepath.Glob(slackService.Conf.BackupDir + "/manual_*.tar.gz")
				if len(files) == 0 {
					SendSlackNotification(":x: No manual backups found for restore.")
					return
				}
				sort.Strings(files)
				latest := files[len(files)-1]
				err := RestoreVolumesFromFile(slackService.Conf, slackService.DockerHelper, slackService.Logger, latest)
				if err != nil {
					SendSlackNotification(":x: Slack manual restore failed: " + err.Error())
				} else {
					SendSlackNotification(":white_check_mark: Slack manual restore completed.")
				}
			}
		}()
		respondEphemeral(w, "Manual restore started!")
	case strings.Contains(command, "restart"):
		if slackService != nil {
			containers, err := slackService.DockerHelper.ListRunningContainers()
			names := []string{}
			if err == nil {
				for _, c := range containers {
					if len(c.Names) > 0 {
						names = append(names, c.Names[0])
					}
				}
			}
			blocks := buildRestartBlocks(names)
			respondBlocks(w, blocks)
		} else {
			respondEphemeral(w, "Docker not initialized.")
		}
	default:
		respondEphemeral(w, "Unknown command. Try /backup, /restore, or /restart.")
	}
}

func handleSlackInteraction(w http.ResponseWriter, payload string) {
	// Parse interactive payload
	var data map[string]interface{}
	if err := json.Unmarshal([]byte(payload), &data); err != nil {
		respondEphemeral(w, "Failed to parse interaction.")
		return
	}
	// Example: handle restart button
	actions, _ := data["actions"].([]interface{})
	if len(actions) > 0 {
		action, _ := actions[0].(map[string]interface{})
		if action["action_id"] == "restart_all" {
			go func() {
				SendSlackNotification(":arrows_counterclockwise: Restarting all containers (requested from Slack)")
				if slackService != nil {
					containers, err := slackService.DockerHelper.ListRunningContainers()
					if err == nil {
						for _, c := range containers {
							_ = slackService.DockerHelper.StopContainerByID(c.ID)
							_ = slackService.DockerHelper.StartContainerByID(c.ID)
						}
						SendSlackNotification(":white_check_mark: All containers restarted.")
					} else {
						SendSlackNotification(":x: Failed to list containers for restart: " + err.Error())
					}
				}
			}()
			respondEphemeral(w, "Restarting all containers!")
			return
		}
		if action["action_id"] == "restart_one" {
			container := action["value"].(string)
			go func() {
				SendSlackNotification(fmt.Sprintf(":repeat: Restarting container %s (requested from Slack)", container))
				if slackService != nil {
					containers, err := slackService.DockerHelper.ListRunningContainers()
					if err == nil {
						for _, c := range containers {
							if len(c.Names) > 0 && c.Names[0] == container {
								_ = slackService.DockerHelper.StopContainerByID(c.ID)
								_ = slackService.DockerHelper.StartContainerByID(c.ID)
								SendSlackNotification(":white_check_mark: Container restarted: " + container)
								break
							}
						}
					} else {
						SendSlackNotification(":x: Failed to list containers for restart: " + err.Error())
					}
				}
			}()
			respondEphemeral(w, fmt.Sprintf("Restarting container %s!", container))
			return
		}
	}
	respondEphemeral(w, "Unknown action.")
}

// StartSlackServer starts the HTTP server for Slack integration
func StartSlackServer(addr string, conf *config.Config, logger *log.Logger, dockerHelper *DockerHelper) {
	InitSlackService(conf, logger, dockerHelper)
	http.HandleFunc("/slack", SlackCommandHandler)
	go func() {
		fmt.Printf("[SLACK] Listening for Slack commands on %s/slack\n", addr)
		if err := http.ListenAndServe(addr, nil); err != nil {
			fmt.Fprintf(os.Stderr, "[SLACK] HTTP server error: %v\n", err)
		}
	}()
}

func respondEphemeral(w http.ResponseWriter, msg string) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"response_type": "ephemeral", "text": msg})
}

func respondBlocks(w http.ResponseWriter, blocks []interface{}) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"response_type": "ephemeral",
		"blocks":        blocks,
	})
}

func buildRestartBlocks(containers []string) []interface{} {
	blocks := []interface{}{
		map[string]interface{}{
			"type": "section",
			"text": map[string]string{"type": "mrkdwn", "text": "*Restart containers:*"},
		},
		map[string]interface{}{
			"type": "actions",
			"elements": []interface{}{
				map[string]interface{}{
					"type":      "button",
					"text":      map[string]string{"type": "plain_text", "text": "Restart All"},
					"action_id": "restart_all",
				},
			},
		},
	}
	for _, c := range containers {
		blocks = append(blocks, map[string]interface{}{
			"type": "actions",
			"elements": []interface{}{
				map[string]interface{}{
					"type":      "button",
					"text":      map[string]string{"type": "plain_text", "text": "Restart " + c},
					"action_id": "restart_one",
					"value":     c,
				},
			},
		})
	}
	return blocks
}
