#!/bin/bash
set -e

# Usage:
#   ./run_in_container.sh [OPTIONS] "COMMAND"
#
# Options:
#   --dangerously-allow-network-outbound   Allow unrestricted outbound network traffic inside the container.
#   --dangerously-allow-sudo              Allow sudo execution inside the container (via the 'sudonode' user).
#   --dangerously-allow-install           Allow both outbound network and sudo execution, and enable Docker-in-Docker.
#   --allow-docker-in-docker              Enable Docker-in-Docker (nested Docker daemon).
#   --work_dir <directory>                Specify the working directory to mount inside the container (default: current directory).
#
# Examples:
#   ./run_in_container.sh "echo Hello, world!"
#   ./run_in_container.sh --work_dir /path/to/project "ls -la"
#   ./run_in_container.sh --dangerously-allow-install --work_dir /path/to/project "npm install"
#   ./run_in_container.sh --allow-docker-in-docker "docker ps"

# Default the work directory to WORKSPACE_ROOT_DIR if not provided.
WORK_DIR="${WORKSPACE_ROOT_DIR:-$(pwd)}"
# By default, do not disable outbound firewall
ALLOW_OUTBOUND=false
# By default, do not allow sudo execution via sudonode
ALLOW_SUDO=false
# By default, do not enable Docker-in-Docker
ALLOW_DIND=false

# Parse optional flags:
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dangerously-allow-network-outbound)
      ALLOW_OUTBOUND=true
      shift
      ;;
    --dangerously-allow-sudo)
      ALLOW_SUDO=true
      shift
      ;;
    --dangerously-allow-install)
      # Allow both outbound network and sudo inside container
      ALLOW_OUTBOUND=true
      ALLOW_SUDO=true
      # Also allow Docker-in-Docker
      ALLOW_DIND=true
      shift
      ;;
    --allow-docker-in-docker)
      # Enable Docker-in-Docker (nested daemon)
      ALLOW_DIND=true
      shift
      ;;
    --work_dir)
      if [ -z "${2:-}" ]; then
        echo "Error: --work_dir flag provided but no directory specified."
        exit 1
      fi
      WORK_DIR="$2"
      shift 2
      ;;
    *)
      break
      ;;
  esac
done

WORK_DIR=$(realpath "$WORK_DIR")
# Determine docker exec user option: use sudonode if requested
if [ "$ALLOW_SUDO" = true ]; then
  echo "Allowing sudo execution inside container..."
  DOCKER_EXEC_USER_OPTION="-u sudonode"
else
  DOCKER_EXEC_USER_OPTION=""
fi

# Generate a unique container name based on the normalized work directory
CONTAINER_NAME="codex_$(echo "$WORK_DIR" | sed 's/\//_/g' | sed 's/[^a-zA-Z0-9_-]//g')"

# Define cleanup to remove the container on script exit, ensuring no leftover containers
cleanup() {
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
# Trap EXIT to invoke cleanup regardless of how the script terminates
trap cleanup EXIT

# Ensure a command is provided.
if [ "$#" -eq 0 ]; then
  echo "Usage: $0 [OPTIONS] \"COMMAND\""
  echo "Run a command inside a Docker container with optional configurations."
  echo "Use --help for more details."
  exit 1
fi

# Check if WORK_DIR is set.
if [ -z "$WORK_DIR" ]; then
  echo "Error: No work directory provided and WORKSPACE_ROOT_DIR is not set."
  exit 1
fi

## Kill any existing container for the working directory
cleanup

# Determine extra docker run options (e.g., privileged for Docker-in-Docker)
DOCKER_RUN_OPTS=""
if [ "$ALLOW_DIND" = true ]; then
  echo "Enabling nested Docker-in-Docker (privileged mode) in container..."
  # Run privileged and set Docker host for nested daemon
  DOCKER_RUN_OPTS="--privileged -e DOCKER_HOST=unix:///var/run/docker.sock"
fi

# Run the container with the specified directory mounted at the same path inside the container.
docker run $DOCKER_RUN_OPTS --name "$CONTAINER_NAME" -d \
  -e OPENAI_API_KEY \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  -v "$WORK_DIR:/app$WORK_DIR" \
  codex \
  sleep infinity

# If Docker-in-Docker enabled, start a nested Docker daemon inside the container
if [ "$ALLOW_DIND" = true ]; then
  echo "Starting Docker daemon inside container..."
  docker exec -u sudonode "$CONTAINER_NAME" bash -c \
    "sudo touch /var/log/dockerd.log && sudo chmod 666 /var/log/dockerd.log && \
     nohup sudo -n dockerd --host unix:///var/run/docker.sock --storage-driver vfs \
     > /var/log/dockerd.log 2>&1 &"
fi

## Initialize and configure the firewall inside the container
FIREWALL_CMD="sudo /usr/local/bin/init_firewall.sh"
# allow outbound network if requested
if [ "$ALLOW_OUTBOUND" = true ]; then
  echo "Allowing outbound network access inside container..."
  FIREWALL_CMD+=" --dangerously-allow-network-outbound"
fi
# relax forwarding when running Docker-in-Docker
if [ "$ALLOW_DIND" = true ]; then
  echo "Allowing Docker-in-Docker internal container forwarding..."
  FIREWALL_CMD+=" --allow-docker-in-docker"
fi

echo "Initializing firewall inside container..."
docker exec "$CONTAINER_NAME" bash -c "$FIREWALL_CMD"
# Execute the provided command in the container, ensuring it runs in the work directory.
# We use a parameterized bash command to safely handle the command and directory.

quoted_args=""
for arg in "$@"; do
  quoted_args+=" $(printf '%q' "$arg")"
done
docker exec $DOCKER_EXEC_USER_OPTION -it "$CONTAINER_NAME" bash -c "cd \"/app$WORK_DIR\" && codex --full-auto ${quoted_args}"
