#!/bin/bash
#
# Ansible role test shim.
#
# Usage: [OPTIONS] ./tests/test.sh
#   - playbook: a playbook in the tests directory (default = "test.yml")
#   - cleanup: whether to remove the Docker container (default = true)
#   - container_id: the --name to set for the container (default = timestamp)
#   - test_idempotence: whether to test playbook's idempotence (default = true)
#
# License: MIT
# Original from: https://gist.github.com/geerlingguy/73ef1e5ee45d8694570f334be385e181
# Original work copyright Jeff Geerling
# Modifications done by Stephen Dunne

# Pretty colors.
red="$(tput setaf 1)"
green="$(tput setaf 2)"
neutral="$(tput sgr0)"

# Allow environment variables to override defaults.
playbook=${playbook:-"test.yml"}
cleanup=${cleanup:-"true"}
container_id=${container_id:-$(date +%s)}
test_idempotence=${test_idempotence:-"true"}
docker_image='nexcess/ansible-role-interworx'
retval=0

## Build docker container
if [[ "$(docker images -q "${docker_image}:latest" 2> /dev/null)" == "" ]]; then
  printf "%s\n" "${green}Building Docker image: ${docker_image}${neutral}"
  docker build -t "nexcess/ansible-role-interworx:latest" - < Dockerfile
fi

## Set up vars for Docker setup.
# cgroup mount must be rw and the namespace shared with the host so that
# CentOS 7's systemd can manage cgroups properly on a cgroups v2 host.
opts=(--privileged --cgroupns=host --tmpfs /tmp --tmpfs /run --volume=/sys/fs/cgroup:/sys/fs/cgroup:rw --security-opt seccomp=unconfined -p 2443:2443)

# Run the container using the supplied OS.
printf "%s\n" "${green}Starting Docker container: ${docker_image}${neutral}"
docker run --detach --volume="$PWD":/etc/ansible/roles/role_under_test:rw --name "$container_id" "${opts[@]}" "${docker_image}:latest"

# give systemd time to boot
attempts=0
printf "%s\n" "${green}Checking if systemd has booted...${neutral}"
while ! docker exec "$container_id" systemctl list-units > /dev/null 2>&1; do
  if ((attempts > 5)); then
    printf "%s\n" "${red}systemd never came up after $((attempts * 5))s; aborting.${neutral}"
    docker exec "$container_id" systemctl list-units || true
    docker exec "$container_id" ps -ef || true
    docker logs "$container_id" || true
    if [ "$cleanup" = true ]; then
      docker rm -f "$container_id" >/dev/null 2>&1 || true
    fi
    exit 1
  fi
  printf "%s\n" "${green}Sleeping for 5 seconds...${neutral}"
  sleep 5
  attempts=$((attempts + 1))
done

printf "%s\n" "${green}Installing dependencies if needed...${neutral}"
docker exec --tty "$container_id" env TERM=xterm /bin/bash -c 'cd /etc/ansible/roles/role_under_test/; python tests/deps.py'
docker exec --tty "$container_id" env TERM=xterm /bin/bash -c 'if [ -e /etc/ansible/roles/role_under_test/tests/requirements.yml ]; then ansible-galaxy install -r /etc/ansible/roles/role_under_test/tests/requirements.yml; fi'
printf "\n"

## Run Ansible Lint
printf "%s\n" "${green}Linting Ansible role/playbook.${neutral}"
docker exec --tty "$container_id" env TERM=xterm ansible-lint -v /etc/ansible/roles/role_under_test/
printf "\n"

# Dump interworx logs and key service status so failures aren't a black box.
# InterWorx runs its own apache instance separate from the system httpd; its
# logs live under /usr/local/interworx/var/log/.
dump_diagnostics() {
  printf "%s\n" "${red}Dumping diagnostic logs from container...${neutral}"
  docker exec "$container_id" bash -c '
    for f in /usr/local/interworx/var/log/iworx.log /usr/local/interworx/var/log/error.log; do
      if [ -f "$f" ]; then
        echo "=== $f (tail) ==="
        tail -200 "$f"
        echo
      fi
    done
    echo "=== systemctl list-units (key iworx services) ==="
    systemctl --no-pager --no-legend list-units "iworx*" "*mysql*" 2>&1 || true
    echo
    for svc in iworx iworxphp72-php-fpm; do
      echo "=== systemctl status -l $svc ==="
      systemctl status -l --no-pager "$svc" 2>&1 || true
      echo
      echo "=== journalctl -u $svc (last 100 lines) ==="
      journalctl --no-pager -u "$svc" -n 100 2>&1 || true
      echo
    done
    echo "=== iworx-horde investigation ==="
    echo "--- ls /usr/local/interworx/etc/php-fpm.d/ ---"
    ls -la /usr/local/interworx/etc/php-fpm.d/ 2>&1 || true
    echo "--- ls /usr/local/interworx/var/run/ ---"
    ls -la /usr/local/interworx/var/run/ 2>&1 || true
    echo "--- getent passwd | grep -i iworx ---"
    getent passwd | grep -i iworx || true
    echo "--- iworx-horde pool config ---"
    for f in /usr/local/interworx/etc/php-fpm.d/*horde*.conf; do
      [ -f "$f" ] && { echo "### $f ###"; cat "$f"; }
    done
    echo "--- rpm -qa | grep -i horde ---"
    rpm -qa | grep -i horde || echo "(no horde packages installed)"
    echo
    echo "=== ps -ef ==="
    ps -ef
  ' || true
}

# Run Ansible playbook.
printf "%s\n" "${green}Running command: docker exec $container_id env TERM=xterm ansible-playbook /etc/ansible/roles/role_under_test/tests/${playbook}${neutral}"
if ! docker exec "$container_id" env TERM=xterm env ANSIBLE_FORCE_COLOR=1 ansible-playbook "/etc/ansible/roles/role_under_test/tests/${playbook}"; then
  dump_diagnostics
  retval=1
fi
printf "\n"

if [ "$test_idempotence" = true ]; then
  # Run Ansible playbook again (idempotence test).
  printf "%s\n" "${green}Running playbook again: idempotence test${neutral}"
  idempotence=$(mktemp)
  docker exec "$container_id" env TERM=xterm env ANSIBLE_FORCE_COLOR=1 ansible-playbook "/etc/ansible/roles/role_under_test/tests/${playbook}" | tee -a "${idempotence}"
  printf "\n"
  if tail "$idempotence" | grep -q 'changed=0.*failed=0'; then
    printf "%s\n" "${green}Idempotence test: pass${neutral}"
  else
    printf "%s\n" "${red}Idempotence test: fail${neutral}"
    retval=1
  fi
fi

# Remove the Docker container (if configured).
if [ "$cleanup" = true ]; then
  printf "Removing Docker container...\n"
  docker rm -f "$container_id"
fi

exit "$retval"
