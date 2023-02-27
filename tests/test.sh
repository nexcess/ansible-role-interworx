#!/bin/bash

# Pretty colors.
red=$(tput setaf 1)
green=$(tput setaf 2)
neutral=$(tput sgr0)

timestamp=$(date +%s)

# Allow environment variables to override defaults.
container_id=${container_id:-$timestamp}
docker_image='nexcess/ansible-role-interworx'


  #--volume="$PWD":/etc/ansible/roles/role_under_test:rw \
  #--security-opt seccomp=unconfined \
  #-p 2443:2443 \
  #--detach \
docker run \
  -it \
  --cgroup-parent=docker.slice \
  --cgroupns private \
  --tmpfs /tmp \
  --tmpfs /run \
  --tmpfs /run/lock \
  --name "$container_id" \
  "${docker_image}:latest"

# give systemd time to boot
attempts=0
printf "%-40s\n" "${green}Checking if systemd has booted...${neutral}"
while ! docker exec "$container_id" systemctl list-units > /dev/null 2>&1; do
  if (( attempts > 15 )); then
    printf "%-40s\n" "${red}Giving up waiting for systemd! Output below:${neutral}"
    docker exec "$container_id" systemctl list-units
    docker inspect "$(docker ps -l --format '{{json .}}' | jq -r '.ID')"
    break
  fi
  printf "%-40s\n" "${green}Sleeping for 5 seconds...${neutral}"
  sleep 5
  attempts=$((attempts+1))
done

docker exec "$container_id" systemctl list-units

if (( attempts == 5 )); then
  exit 1
fi

