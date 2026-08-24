# Test harness

How `tests/test.sh` runs the role, and the traps that cost the most time. For the commands
themselves see [../AGENTS.md](../AGENTS.md#commands).

## What a run does

1. Builds `nexcess/ansible-role-interworx:latest` — **only if no image by that name exists.**
2. Starts it detached, `--privileged --cgroupns=host` with `/sys/fs/cgroup` mounted rw, the repo
   bind-mounted at `/etc/ansible/roles/role_under_test`, and `-p 2443:2443`.
3. Polls `systemctl list-units` until systemd answers, giving up after six 5-second sleeps.
4. Runs `tests/deps.py`, then `ansible-galaxy install -r tests/requirements.yml` if that file
   exists. Both are no-ops while `meta/main.yml` has `dependencies: []`.
5. Runs `ansible-lint -v` over the mounted role. **Its exit status is discarded** — see Traps.
6. Runs the playbook. On failure, calls `dump_diagnostics` and sets the exit code to 1.
7. Runs the playbook again and greps the tail for `changed=0.*failed=0` — the idempotence check.
8. Removes the container unless `cleanup=false`.

## What a run costs

This is not a unit-test loop. A full run performs a real InterWorx install and a real license
activation against the vendor's servers:

- `Install Interworx` is capped at `async: 1800`, and the shim runs the playbook twice — budget
  tens of minutes.
- The run needs outbound access to `updates.interworx.com`, including the internal
  `_internal/builds/...` yum path that `tests/test.yml` adds. It cannot proceed without it.
- `tests/test.yml` hardcodes the CI license key and master credentials as play vars, so a local run
  needs a working license substituted in. `Activate Interworx License` sets `failed_when: false`, so
  a failure surfaces at `Check Interworx License Activation Result`, a `debug` task with
  `failed_when: true` gated on a non-zero `goiworx` return — and that aborts the play wherever it
  runs. With no valid key, this is where a run dies.

## Environment variables

| Variable | Default | Effect |
|---|---|---|
| `playbook` | `test.yml` | Which playbook in `tests/` to run. |
| `cleanup` | `true` | Set `false` to keep the container after the run. |
| `container_id` | `$(date +%s)` | The container's `--name`. Set it to something memorable when debugging. |
| `test_idempotence` | `true` | Set `false` to skip the second playbook run. |

`docker_image` is hardcoded, not overridable.

## Traps

- **Run it from the repo root.** The build pipes `Dockerfile` from the current directory and the
  mount is `--volume="$PWD":...`, so running it from inside `tests/` mounts the wrong tree.
- **A stale image is reused silently.** Edit the `Dockerfile` and you must
  `docker build -t nexcess/ansible-role-interworx .` or `docker rmi` it yourself. CI never hits the
  auto-build path, because `.travis.yml` builds the image in `before_install`.
- **One container at a time**, because of the fixed `-p 2443:2443` publish.
- **Apple Silicon runs are emulated.** The image is `FROM --platform=linux/amd64`, so every run is
  slow — and the ~30s systemd boot budget in step 3 can expire before the role executes at all.
- **No inventory flag is needed.** The image bakes `/etc/ansible/hosts` with
  `localhost ansible_connection=local`, and `tests/test.yml` targets `hosts: all`.
- **Lint does not gate the run.** `tests/test.sh` has no `set -e`; only the first playbook run and
  the idempotence grep ever touch `retval`. `ansible-lint` violations print and the run still exits
  0, in CI too. Read the lint output yourself — don't infer from the exit code.
- **The second run is undiagnosed.** `dump_diagnostics` fires only for the first playbook run. The
  re-run's exit status is discarded; only the `changed=0.*failed=0` grep decides pass or fail. You
  still get the playbook's own output through `tee`, but not the container dump — re-run with
  `cleanup=false` to see the container state.
- **The repo already carries untracked run leftovers in `tests/`** (`iworx-install.log`,
  `.killconflicts`), and `.gitignore` covers only `tests/test.retry`. Check `git status` before
  committing.
- **`tests/deps.py` only works from the role root.** It opens `meta/main.yml` by relative path;
  `test.sh` `cd`s there first.

## Diagnostics on failure

`dump_diagnostics` tails `/usr/local/interworx/var/log/iworx.log` and `error.log`, lists `iworx*`
and `*mysql*` units, dumps `systemctl status` plus `journalctl` for `iworx` and
`iworxphp72-php-fpm`, inspects the `iworx-horde` pool config and `var/run/`, and prints `ps -ef`.

The php-fpm unit name there is hardcoded to `iworxphp72-php-fpm`, so on an InterWorx 8.x install it
dumps the wrong unit — the role itself selects `iworxphp82-php-fpm.service` at that version.

## Pinned external sources

These are the parts most likely to break before the role itself does:

- `Dockerfile` rewrites the CentOS 7 repos to `vault.centos.org` and EPEL to
  `archives.fedoraproject.org`, because CentOS 7 went EOL and the live mirrors return 410 Gone.
- `Dockerfile` pins `pip < 21.0`, `cryptography==3.3.2` (last release with Python 2 support), and
  force-reinstalls `pathlib`, which Python 3 bundles but these Python 2 packages still expect.
- `tests/test.yml` adds an `iworx-djbdns` yum repo pointing at an internal
  `updates.interworx.com/_internal/builds/...` path, to pull a djbdns RPM with a higher `DATALIMIT`.
  Without it `dnscache` dies with "not enough memory for cache of size" on some kernels.
- `tests/test.yml` touches `/etc/sysconfig/network`, which the container image lacks.
