#!/bin/bash
#
# Ansible role test shim.
#
# Usage: [OPTIONS] ./tests/test.sh
#   - distro: a supported Docker distro version (default = "centos7")
#   - playbook: a playbook in the tests directory (default = "test.yml")
#   - cleanup: whether to remove the Docker container (default = true)
#   - container_id: the --name to set for the container (default = timestamp)
#   - test_idempotence: whether to test playbook's idempotence (default = true)
#
# License: MIT
# Original from: https://gist.github.com/geerlingguy/73ef1e5ee45d8694570f334be385e181
# Original work copyright Jeff Geerling
# Modifications done by Stephen Dunne

# Exit on any individual command failure.
set -e

# Pretty colors.
red='\033[0;31m'
green='\033[0;32m'
neutral='\033[0m'

timestamp=$(date +%s)

# Allow environment variables to override defaults.
distro=${distro:-"centos7"}
playbook=${playbook:-"test.yml"}
cleanup=${cleanup:-"true"}
container_id=${container_id:-$timestamp}
test_idempotence=${test_idempotence:-"true"}
docker_image='nexcess/ansible-role-interworx'

## Build docker container
if [[ "$(docker images -q "${docker_image}:latest" 2> /dev/null)" == "" ]]; then
  printf "${green}Building Docker image: ${docker_image}${neutral}\n"
  docker build -t "nexcess/ansible-role-interworx:latest" - < Dockerfile
fi

## Set up vars for Docker setup.
# CentOS 7
if [ $distro = 'centos7' ]; then
  opts="--privileged --tmpfs /tmp --tmpfs /run --volume=/sys/fs/cgroup:/sys/fs/cgroup:ro --security-opt seccomp=unconfined -p 2443:2443"
fi

# Run the container using the supplied OS.
printf ${green}"Starting Docker container: ${docker_image}"${neutral}"\n"
docker run --detach --volume="$PWD":/etc/ansible/roles/role_under_test:rw --name $container_id $opts "${docker_image}:latest"

# give systemd time to boot
attempts=0
printf "${green}Checking if systemd has booted...${neutral}\n"
while ! docker exec "$container_id" systemctl list-units > /dev/null 2>&1; do
  if (( $attempts > 5 )); then
    printf "${red}Giving up waiting for systemd! Output below:${neutral}\n"
    docker exec "$container_id" systemctl list-units
    break
  fi
  printf "${green}Sleeping for 5 seconds...${neutral}\n"
  sleep 5
  attempts=$((attempts+1))
done

printf "\n"

printf ${green}"Installing dependencies if needed..."${neutral}"\n"
docker exec --tty $container_id env TERM=xterm /bin/bash -c 'cd /etc/ansible/roles/role_under_test/; python tests/deps.py'
docker exec --tty $container_id env TERM=xterm /bin/bash -c 'if [ -e /etc/ansible/roles/role_under_test/tests/requirements.yml ]; then ansible-galaxy install -r /etc/ansible/roles/role_under_test/tests/requirements.yml; fi'

printf "\n"

## Run Ansible Lint
printf ${green}"Linting Ansible role/playbook."${neutral}"\n"
docker exec --tty $container_id env TERM=xterm ansible-lint -v /etc/ansible/roles/role_under_test/

printf "\n"

# Run Ansible playbook.
printf ${green}"Running command: docker exec $container_id env TERM=xterm ansible-playbook /etc/ansible/roles/role_under_test/tests/$playbook"${neutral}
docker exec $container_id env TERM=xterm env ANSIBLE_FORCE_COLOR=1 ansible-playbook /etc/ansible/roles/role_under_test/tests/$playbook

if [ "$test_idempotence" = true ]; then
  # Run Ansible playbook again (idempotence test).
  printf ${green}"Running playbook again: idempotence test"${neutral}
  idempotence=$(mktemp)
  docker exec $container_id ansible-playbook /etc/ansible/roles/role_under_test/tests/$playbook | tee -a $idempotence
  tail $idempotence \
    | grep -q 'changed=0.*failed=0' \
    && (printf ${green}'Idempotence test: pass'${neutral}"\n") \
    || (printf ${red}'Idempotence test: fail'${neutral}"\n" && exit 1)
fi

# Remove the Docker container (if configured).
if [ "$cleanup" = true ]; then
  printf "Removing Docker container...\n"
  docker rm -f $container_id
fi
