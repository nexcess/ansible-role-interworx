# ansible-role-interworx

Ansible role that installs the InterWorx control panel on an EL host and activates its license.

Point it at a freshly provisioned server and it fetches and runs the vendor installer, installs
`interworx-cli`, activates the license, accepts the EULA, sets default nameservers if you supply
any, proves the panel answers a login, and generates an API key if the host has none. On a host
that already has the InterWorx RPM, the install steps skip themselves — including license
activation.

For architecture, the task-by-task install flow, and test/lint commands, see
[AGENTS.md](AGENTS.md).

## Requirements

- **EL7.** `meta/main.yml` still declares EL 6 and 7, but the post-install service-recovery block
  uses `systemctl` and the `systemd` module, so EL6 is stale metadata. CI (Travis) exercises EL7
  only, in a CentOS 7 container.
- **systemd**, and outbound access to `updates.interworx.com`.
- **A root connection.** Only two tasks set `become: true`; the rest assume they are already
  privileged. Run the role as root or with `become: true` at play level.
- **Fact gathering and a default IPv4 route on the target.** The verification runs `uri` on the
  target itself: a POST to `https://{{ ansible_default_ipv4.address }}:2443/nodeworx/?action=login`
  expecting a 302, then a GET of `/nodeworx/dns` with the returned cookie. So `gather_facts` must be
  on, `ansible_default_ipv4` must be populated, and the target must be able to reach *its own*
  default-IPv4 address on 2443. Skipped entirely when `iw_activate_license` is false.
- **A valid InterWorx license key**, unless `iw_activate_license` is false.

`meta/main.yml` declares `min_ansible_version: "2.0"`, but the tested combination is ansible
2.9.27 — see the toolchain note in [AGENTS.md](AGENTS.md#conventions) before upgrading.

## Example playbook

```yaml
- hosts: server
  become: true
  roles:
    - role: nexcess.interworx
      vars:
        iw_license_key: "YOUR-KEY-HERE"
        iw_master_email: "admin@example.com"
        iw_master_password: "{{ vault_iw_master_password }}"
        iw_ns1: "ns1.example.com"
        iw_ns2: "ns2.example.com"
```

`iw_license_key`, `iw_master_email`, and `iw_master_password` are all required together whenever
`iw_activate_license` is true; the role fails fast on the first task if any is empty. Setting any
`iw_ns*`, as above, makes every run report `changed` — see the DNS row below.

## Role variables

Defaults live in [defaults/main.yml](defaults/main.yml).

### License and account

| Variable | Default | Purpose |
|---|---|---|
| `iw_activate_license` | `true` | Set false to install without activating a license. Also skips the nameserver tasks, the login verification, and the theme install. |
| `iw_license_key` | `""` | InterWorx license key. Required unless `iw_activate_license` is false. |
| `iw_master_email` | `""` | Master NodeWorx user email. Required unless `iw_activate_license` is false. |
| `iw_master_password` | `""` | Master NodeWorx user password. Required unless `iw_activate_license` is false. |
| `iw_accept_eula` | `true` | Accepts the EULA by writing `firstrun="0"` (quotes included, matching InterWorx's ini style) to the `[iworx]` section of `/home/interworx/iworx.ini`. Without it, the first login prompts for acceptance. |

### Installer source and stack versions

| Variable | Default | Purpose |
|---|---|---|
| `iw_release_channel` | `"release"` | Channel to install from: `stable`, `release`, `release-candidate`, or `beta`. |
| `iw_install_script_url` | `https://updates.interworx.com/iworx/scripts/iworx-cp-install.sh` | Installer location. |
| `iw_install_script_loc` | `/tmp/iworx-cp-install.sh` | Where the installer is downloaded to. |
| `iw_use_alt_repo_file` | `false` | Rewrite the installer's yum repo URL before running it. |
| `iw_alt_repo_file_url` | `""` | Replacement repo-file URL. Only read when `iw_use_alt_repo_file` is true. |
| `iw_mysql_ver` | `"system"` | Passed to the installer's `-m` flag (e.g. `10.6`). |
| `iw_php_ver` | `"system"` | Passed to the installer's `-p` flag (e.g. `7.3`). |

### DNS

| Variable | Default | Purpose |
|---|---|---|
| `iw_ns1`, `iw_ns2`, `iw_ns3` | `""` | Default nameservers for new SiteWorx accounts (e.g. `ns1.nexcess.net`). Written to `iworx.ini` and set via `nodeworx`. Each `iworx.ini` write is skipped when its own variable is empty; all four DNS tasks also require `iw_activate_license`. The `nodeworx` call fires when *any* of the three is set and passes the empty ones through as empty `--nsN` values. It has no `changed_when`, so any run with an `iw_ns*` set reports `changed` every time — see [AGENTS.md](AGENTS.md#conventions). |

### CLI and API

| Variable | Default | Purpose |
|---|---|---|
| `iw_cli_pkg_state` | `"latest"` | Package state for `interworx-cli`. |
| `iw_generate_apikey` | `true` | Generate a NodeWorx API key if the host has none. The preceding `nodeworx ... listApikey` check runs regardless of this setting. |

### Base PHP symlink

| Variable | Default | Purpose |
|---|---|---|
| `iw_symlink_base_php` | `false` | Remove the base PHP packages and point `/usr/bin/php` at a specific build. |
| `iw_symlink_base_php_path` | `/opt/remi/php56/root/usr/bin/php` | Symlink target. |
| `iw_symlink_base_php_packages` | `php`, `php-devel`, `php-cli`, `php-pear` | Packages removed before the symlink is created. |

### Custom theme

Applied by [tasks/theme.yml](tasks/theme.yml), which runs only when `iw_use_custom_theme`,
`iw_theme_name`, `iw_theme_git_repo`, and `iw_activate_license` are all set. It runs with
`ignore_errors: true`, so a theme failure will not fail the play.

| Variable | Default | Purpose |
|---|---|---|
| `iw_use_custom_theme` | `false` | Enables the theme tasks. |
| `iw_theme_name` | `""` | Theme name, also set as the master user's theme. |
| `iw_theme_git_repo` | `""` | Git repo to clone the theme from. |
| `iw_theme_git_version` | `""` | Ref to check out. The task's `default('master')` only fires when the variable is *undefined*, and `defaults/main.yml` always defines it as `""` — so the `'master'` fallback never fires and the empty string is what reaches the `git` module. Always set this when you enable the theme: `ignore_errors: true` keeps a failed clone from failing the play, but it does *not* skip the rest of `theme.yml`, so the remaining tasks run against whatever the clone left on disk — you can end up with the repo's default branch installed instead of the ref you wanted. |
| `iw_theme_tmp_dir` | `{{ iw_homedir }}/tmp/{{ iw_theme_name }}` | Staging directory for the clone. The archive is written alongside it as `<dir>.zip`, then removed. |

### Paths and identity

| Variable | Default | Purpose |
|---|---|---|
| `iw_unix_user` | `"iworx"` | Owner applied to the three special theme HTML files copied under `iw_homedir`. |
| `iw_unix_group` | `"iworx"` | Group applied to those same files. |
| `iw_homedir` | `/usr/local/interworx` | InterWorx install root. |
| `iw_ssl_email` | `ssl-anchor@no-reply.net` | Unused — a leftover from a removed task. Setting it does nothing. |

## Testing

`./tests/test.sh` boots a CentOS 7 systemd container, runs `ansible-lint` over the role, runs the
full playbook, then re-runs it and asserts `changed=0`. Run it from the repo root. The only CI
config in the repo is `.travis.yml`, which runs `shellcheck` on the shim and then the shim itself.
See [AGENTS.md](AGENTS.md#commands) for the invocations and
[ref/test-harness.md](ref/test-harness.md) for how the shim works and the traps worth knowing
before your first run.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT

## Author

Paul Oehler <poehler@interworx.com>
