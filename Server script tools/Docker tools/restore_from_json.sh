#!/bin/bash
# restore_from_json.sh: Restore a container from a backup JSON file and image tar using native Docker
# Usage: sudo ./restore_from_json.sh /usr/autoscript/container_details.json /usr/autoscript/image_backups

set -e

JSON_FILE="${1:-/usr/autoscript/container_details.json}"
IMAGE_DIR="${2:-/usr/autoscript/image_backups}"

if [ ! -f "$JSON_FILE" ]; then
  echo "[restore-from-json] ERROR: JSON file not found: $JSON_FILE" >&2
  exit 1
fi

count=$(jq length "$JSON_FILE")
echo "[restore-from-json] Found $count containers in backup."

for idx in $(seq 0 $((count-1))); do
  name=$(jq -r ".[$idx].ContainerName // .[$idx].Name // null" "$JSON_FILE" | sed 's#^/##')
  id=$(jq -r ".[$idx].Id // null" "$JSON_FILE")
  image=$(jq -r ".[$idx].Image // .[$idx].Config.Image // null" "$JSON_FILE")
  ports=$(jq -c ".[$idx].PortDependencies // []" "$JSON_FILE")
  tar_file="$IMAGE_DIR/${name}_${id}.tar"
  if [ ! -f "$tar_file" ]; then
    echo "[restore-from-json] WARNING: Image tar not found for $name ($id): $tar_file"
    continue
  fi
  echo "[restore-from-json] Loading image for $name from $tar_file using native Docker..."
  img_id=$(sudo DOCKER_HOST=unix:///var/run/docker.sock docker load -i "$tar_file" | grep 'Loaded image' | awk '{print $NF}')
  # Compose port args
  port_args=()
  for row in $(echo "$ports" | jq -c '.[]'); do
    host_port=$(echo $row | jq -r '.host_port')
    container_port_proto=$(echo $row | jq -r '.container_port')
    container_port=$(echo $container_port_proto | cut -d'/' -f1)
    proto=$(echo $container_port_proto | cut -d'/' -f2)
    if [ -n "$host_port" ] && [ -n "$container_port" ]; then
      port_args+=( -p "$host_port:$container_port/$proto" )
    fi
  done
  echo "[restore-from-json] Running: docker run -d --name $name ${port_args[@]} $image (native Docker)"
  if sudo DOCKER_HOST=unix:///var/run/docker.sock docker run -d --name "$name" "${port_args[@]}" "$image"; then
    # Automatically update JSON inventory after successful deployment
    if [ -f "$JSON_FILE" ]; then
      SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" )" && pwd)"
      source "$SCRIPT_DIR/docker_backup_restore.sh"
      add_container_to_json "$name"
    fi
  else
    echo "[restore-from-json] ERROR: Failed to start container $name with native Docker. Check Docker service status and logs." >&2
  fi
done

echo "[restore-from-json] Restore complete."
