# Repository working rules

## Local checkout and Git CLI

- Work directly in the user's existing project directory. Before making changes,
  run `git rev-parse --show-toplevel`, `git status --short --branch` and
  `git branch --show-current` from that directory to confirm the checkout,
  existing changes and active branch.
- Make source edits, build generated files and run validation in this checkout.
  Do not substitute a second clone or another checkout unless the user requests it.
- Use the local `git` CLI for branches, staging, commits, tags, fetches, pulls
  and pushes. Stage the intended paths explicitly and review `git diff --cached`
  before committing. Preserve unrelated user changes.
- Do not create or update repository files, blobs, trees, commits, branches or
  tags through GitHub connectors, REST/GraphQL APIs, or the web editor. Remote
  publication must originate from a local Git commit pushed from this checkout.
- If Git metadata is read-only, Git authentication fails, or a required Git
  operation is blocked, report the exact blocker and the pending local changes.
  Do not bypass it by publishing through another interface. Do not claim that
  uncommitted or unpushed work is published.
- Keep the existing pull-request workflow for `main`. GitHub CLI, connectors or
  the browser may manage PR/release metadata, review and merge a pushed PR, and
  attach release assets built from the committed local sources; they must not
  replace local commits or Git pushes. Create and push release tags with `git`.
- After a PR merge, fetch and fast-forward the local target branch using the
  Git CLI in this same checkout. Verify that local `HEAD` matches the intended
  remote commit. Before declaring publication complete, run
  `git status --short --branch`, confirm that the intended changes are committed and pushed, and
  report any remaining local changes explicitly.
- Do not use resets, checkout/restore operations that overwrite local changes,
  or `git clean` to hide a dirty working tree. Preserve the work and explain
  what remains to be reconciled.

## Existing project requirements

For fixes based on target-machine reports, analyze the supplied logs first, work
on a dedicated fix branch and commit/push each tested candidate with the Git CLI.
Have the user rerun provisioning and acceptance on the target PC and repeat on
that branch until the required checks pass. Only then create the PR, merge into
`main` and publish a release. Failed, blocked, skipped or missing evidence is not
a successful target acceptance. Actual reports and runtime data stay local.

Follow `docs/development/README.md` and its German counterpart for builds,
validation and releases, and read `SECURITY.md` before committing or publishing.
Keep English/German documentation aligned. The generated installer
`Provision-LoKiEnte.ps1` belongs in the repository root alongside its checksum.
