**Ticket:** <!-- Hyperlink the issue, e.g. [ENG-2460](https://liquidweb.atlassian.net/browse/ENG-2460) — required, or state why there isn't one -->

## Why

<!-- What problem does this solve, or what requirement does it fulfill? One sentence is usually
enough if there's a ticket — it should contain the details. -->

## What

<!-- What changed? Bullet points of the approach taken. -->

### Blast radius

<!-- e.g. role tasks only / test harness only / Dockerfile + toolchain / new required variable
(breaking for existing playbooks) -->

### Deviations from spec

<!-- Bullet points: what, if anything, changed between the ticket's description and the final
implementation, and why. Delete this section if there's no spec to deviate from. -->

## Reading guide

<!-- Optional for a small change. For anything touching more than one file, map it for reviewers
before they read the diff. -->

| File | What to look at | Why |
|---|---|---|
| `` | … | … |

## Test plan

**Automated tests added/updated:**
- [ ] …

**Manual verification steps:**
1. …

<!-- If `./tests/test.sh` was not run, say why — a role change that hasn't been through the
container has not been tested. -->

## Deploy notes

<!-- Delete this section if not needed. -->

**New or renamed variables:** <!-- anything consuming playbooks must set or rename? -->
**Rollout order:** <!-- any sequencing required? -->
**Rollback:** <!-- how to revert if this breaks a provision? -->

## Checklist

- [ ] `shellcheck tests/test.sh` passes
- [ ] `./tests/test.sh` passes, including the idempotence re-run (`changed=0`) — or the Test plan says why not
- [ ] `ansible-lint` is clean, or any new `skip_ansible_lint` tag / `# noqa` pragma is justified in the diff
- [ ] New variables are declared in `defaults/main.yml` and documented in `README.md`
- [ ] Docs updated (`README.md`/`AGENTS.md`) if this changes how the role is used, built, or tested
- [ ] No secrets, tokens, license keys, or real customer data included
