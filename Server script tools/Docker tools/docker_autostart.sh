#!/bin/bash

# Docker Autostart Script
# - Prevents duplicate instances using PID file
# - Sets up systemd service on first run
# - Tracks and restores running containers
# - Monitors Docker events and health
# - Logs errors and health status
# Configuration file path
# Default configuration values
# Load configuration if it exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/docker_autostart.conf"
. "$SCRIPT_DIR/lockfile.sh"
#lockfile path
 # LOCKFILE is sourced from config
#Script start
#identify the script process ID and avoid duplicates

    #acquire lock, exit if already running
    if ! acquire_lock "$LOCKFILE"; then
        echo "Another instance is already running. Exiting in 10 seconds..." | tee -a "$ERROR_LOG"
        xdg-open "$ERROR_LOG" &
        sleep 10
        exit 1
    fi
#cleanup for lockfile and child processes
cleanup() 
{
    release_lock "$LOCKFILE"
    #kill all child/background jobs spawned by this script
    jobs -p | xargs -r kill
    exit 0
}

#trap exit for cleanup
trap cleanup EXIT SIGTERM SIGINT SIGHUP
#create directory to store container list and set permission
sudo mkdir -p "$AUTOSCRIPT_DIR"
sudo chmod 700 "$AUTOSCRIPT_DIR"
#set up the systemd service
Description=Docker Autostart - Save and restore running containers
Requires=docker.service

[Service]
ExecStart=/usr/local/bin/docker_autostart.sh
Restart=always
User=root

[Install]
WantedBy=multi-user.target | sudo tee /etc/systemd/system/docker-autostart.service > /dev/null
if [ ! -f "$SYSTEMD_SERVICE" ]; then
    echo \
[Unit]
Description=Docker Autostart - Save and restore running containers
Requires=docker.service

[Service]
ExecStart=$BIN_PATH
Restart=always
User=root

[Install]
WantedBy=multi-user.target | sudo tee "$SYSTEMD_SERVICE" > /dev/null
    sudo systemctl daemon-reload
    sudo systemctl enable docker-autostart.service
    sudo systemctl start docker-autostart.service
fi
#container IDs handler variable
c_list="$CONTAINER_LIST"
#function to update the container list txt file
update_c_list() 
{
    clean_old_logs
    if ! docker ps -q > "$c_list" 2>>"$ERROR_LOG"; then
        echo "[$(date)] Error updating container list" >> "$ERROR_LOG"
        xdg-open "$ERROR_LOG" &
        check_error_rate
    fi
}
#Function to start saving containers
start_saved_containers() 
{
while read -r container; do
    if [[ "$container" =~ ^[a-zA-Z0-9]+$ ]]; then
        if ! docker start "$container" 2>>"$ERROR_LOG"; then
            clean_old_logs
            echo "[$(date)] Error starting container $container" >> "$ERROR_LOG"
            xdg-open "$ERROR_LOG" &
            check_error_rate
        fi
    clean_old_logs
    else
        clean_old_logs
        echo "[$(date)] Invalid container ID: $container" >> "$ERROR_LOG"
        xdg-open "$ERROR_LOG" &
        check_error_rate
    fi
done < "$c_list"
        rm -f "$c_list"
    fi
}
#handle shutdown
save_containers() 
{
    update_c_list
    exit 0
}
#catch shutdown/restart signal
trap save_containers SIGTERM SIGINT SIGHUP
if ! docker start "$container" 2>>"$ERROR_LOG"; then
start_saved_containers
#listen for Docker events and update the list
docker events --filter 'event=start' --filter 'event=stop' --format '{{.Status}}' | while read -r event; do
    update_c_list
                         echo "[$(date)] Invalid container ID: $container" >> "$ERROR_LOG"
#listen for Docker health_status events
docker events --filter 'event=health_status' --format '{{.Actor.Attributes.name}}: {{.Status}}' | while read -r health_event; do
done &
#periodically check health status of running containers
check_container_health() {
    for container in $(docker ps -q); do
        # Validate container ID before inspecting
start_saved_containers
            health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>>"$ERROR_LOG")
            if [ $? -ne 0 ]; then
                echo "[$(date)] Error inspecting health for container $container" >> "$ERROR_LOG"
                xdg-open "$ERROR_LOG" &
            fi
            name=$(docker inspect --format='{{.Name}}' "$container" 2>>"$ERROR_LOG" | sed 's/^\///')
    echo "[HEALTH EVENT] $health_event" >> "$HEALTH_LOG"
            if [ $? -ne 0 ]; then
                echo "[$(date)] Error inspecting name for container $container" >> "$ERROR_LOG"
                xdg-open "$ERROR_LOG" &
            fi
            echo "$(date): $name ($container) health: $health" >> "$HEALTH_LOG"
        else
            echo "[$(date)] Invalid container ID in health check: $container" >> "$ERROR_LOG"
            xdg-open "$ERROR_LOG" &
        fi
    done
}
#run health check every 5 minutes in the background
while true; do
    check_container_health
    sleep 300
done &