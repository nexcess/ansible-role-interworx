# Contributing

Ansible role that installs the InterWorx control panel on an EL host and activates its license.

## Development setup

You need Docker and `shellcheck`; everything else (ansible, ansible-lint, Python) is pinned inside
the test image. See [AGENTS.md](AGENTS.md#commands) for build/test/lint commands — not repeated
here.

Read [AGENTS.md](AGENTS.md#conventions) before your first change. Two things there will bite you
otherwise: the toolchain is pinned to ansible 2.9.27 / ansible-lint 4.2.0 and modern syntax fails
against it, and the `iw_is_inst.rc != 0` gate on install tasks is what makes the idempotence test
pass.

## Opening a PR

Work happens on a fork: push your branch to your own remote and open the PR against
`nexcess/ansible-role-interworx`. Use this repo's
[PR template](.github/PULL_REQUEST_TEMPLATE.md) — link the Jira ticket and describe how the change
was verified.

## Before you open a PR

- [ ] `./tests/test.sh` passes locally, including the idempotence re-run. This performs a real
      install and license activation, so it needs a working license: `tests/test.yml` pins
      `iw_license_key`/`iw_master_email`/`iw_master_password` as play vars, so substitute your own
      locally and keep that substitution out of the diff. If you could not run it, say so in the PR
      and why.
- [ ] `shellcheck tests/test.sh` passes
- [ ] Any new variable is `iw_`-prefixed, has a default in `defaults/main.yml`, and has a row in `README.md`
- [ ] Docs (`README.md`/`AGENTS.md`) updated if this changes how the role is built, run, or used
