# The ansible 2.9 constraint

For the role's conventions see [../AGENTS.md](../AGENTS.md#conventions).

The test image pins Python 2, ansible 2.9.27, and ansible-lint 4.2.0
([`Dockerfile`](../Dockerfile)). Anything newer than 2.9 does not run there, and several things
that look like cleanup are behavior changes. Read this before "modernizing" any task.

## What works and what doesn't

| Change | Verdict |
|---|---|
| FQCN module names (`ansible.builtin.*`) | Works. `tests/test.yml` already uses `ansible.builtin.yum_repository`. |
| Dropping a `# noqa` pragma | Lint fails. See the inventory below. |
| Dropping a `tags: [skip_ansible_lint]` | Lint fails on that task. |
| `include:` → `include_tasks:` | **Behavior change** — see below. |
| `include:` → `import_tasks:` | Preserves current behavior. |
| Anything requiring ansible ≥ 2.10 | Does not run in the image at all. |

## The `include:` at the end of `tasks/main.yml`

`- include: theme.yml` is the deprecated spelling. On 2.9 it auto-detects as a **static** include —
the filename is a literal, there is no loop, and its parents are static — so its four-clause
`when:` and its `ignore_errors: true` are copied onto every task in `theme.yml` and evaluated
per-task.

`import_tasks:` keeps that. `include_tasks:` does not: it forces a dynamic include, so the `when:`
is evaluated once for the include itself and tags stop being inherited by the included tasks. The
rename is eventually mandatory — `include` for tasks is gone in ansible-core 2.16 — so make it
deliberately, with a test run behind it, rather than as a lint cleanup.

## Lint-suppression inventory

Suppression is per-task. Preserve what a task already carries; don't add one out of habit.

| Where | Suppression | Why |
|---|---|---|
| `Check if Interworx is Installed`, `Detect installed Interworx version` | `tags: [skip_ansible_lint]` | Bare `rpm` calls |
| `Reset failed state on iworx services` | `tags: [skip_ansible_lint]` | Bare `systemctl` |
| `theme.yml`'s `Install Theme`, `Set Theme as Default` | `tags: [skip_ansible_lint]` | Bare `nodeworx` with neither `when:` nor `changed_when:` |
| `Alter Interworx Installer Repo File URL` | `# noqa 303` | `sed` via `shell` where `replace`/`lineinfile` would do |
| `Check Variables`, the three `iworx.ini` ns tasks, `Set Default NS`, two clauses of the theme include | `# noqa 602` | Comparison to an empty string; rule 602 matches per line |

The installer, `goiworx.pex`, and the two API-key tasks carry no suppression and lint clean without
one — but not for a single reason, and each reason is easy to break:

- **Rule 303** ignores them because `sh`, `goiworx.pex`, and `nodeworx` are not in ansible-lint
  4.2.0's known-module map.
- **Rule 301** ("commands should not change things if nothing needs doing") ignores them because each
  has a `when:` or a `changed_when:`. Remove those and the task needs a suppression — which is
  exactly why `theme.yml`'s two `nodeworx` tasks carry one.
- **Rule 305** ("use shell only when shell functionality is required") ignores the two API-key tasks
  only because their `>` folded scalar leaves a trailing newline in the command, and a newline counts
  as a shell metacharacter. Reflow either onto a single `shell:` line and 305 fires.

One more accident worth knowing: `Install Interworx CLI` escapes **rule 403** ("package installs
should not use latest") only because its `state` is the template `{{ iw_cli_pkg_state }}`, which
ansible-lint never renders. Hardcoding `state: latest` there adds a violation.
