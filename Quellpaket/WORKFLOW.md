# Using LoKiEnte: from request to verified code

[Deutsch](WORKFLOW.de.md)

This guide describes the workflow introduced in package **2026.11.18.18**, with
English defaults from **2026.11.18.22**. It assumes familiarity with VS Code and
Git. Local AI assists with development and verification; functional acceptance
and commits remain your responsibility.

## 1. Open a project

Launch the desktop shortcut. Select a known project or another existing directory.
For a new project, create the directory and scaffold first. Write workflows require
the root of a Git repository with at least one commit.

VS Code opens both the sources and the associated LoKiEnte task directory.
Workspace files and configuration live outside your repository under
`<InstallRoot>\projects\<project-id>` and `workspaces`.

Select `shadow-chat` in Kilo and enter your request directly. Chat can read, advise
and start the controlled workflow through `loki_start`. Actual file changes take
place in its bounded agent phases. No separate task-file or JSON step is normally required.

The runner sends each role its task over standard input. The role can read its instructions even when the installation and its run logs are outside the allowed project directory.

If Git reports a missing `GIT_CONFIG_VALUE_0` before the first specialist starts, rerun provisioning with the current installer. Close all managed VS Code windows, reopen the desktop shortcut and submit the task again. The launcher preserves intentionally empty Git settings for Kilo and its child processes.

## 2. Describe a small task

Describe expected behavior, constraints and boundaries, for example:

> Add a reorder recommendation to the inventory logic: recommend reordering when
> stock is below the minimum. Equal or higher stock is sufficient. Cover boundary
> cases with tests; do not change the database or UI.

Kilo passes the complete request to `loki_start`. A read-only preparation agent
examines the project, existing tests and rules. It derives the workflow, acceptance
criteria `AC-1`, `AC-2`, …, change types and exact production/test files. Test commands
come from locally detected templates or existing checks; it cannot invent arbitrary shell commands.

If the preparer returns unreadable JSON, Kilo starts one fresh read-only preparation attempt. Both answers appear in the run directory. A second unreadable answer stops the task before any project change. A substantive rejection or a request for clarification is passed back to the user.

An independent **preparation review** checks alignment with the original request,
scope and test selection. Only after PASS is checks.json backed up and extended.
Unclear requirements, missing tools or conflicts stop the workflow with a specific
NEEDS_INPUT message. Clarify in Kilo and restart the amended request; checks are
never silently weakened.

Criteria are fixed at run start. The test author cannot change their IDs or count.
Mapping every ID alone does not prove complete functional coverage; independent
reviews remain necessary.

## 3. Automatic checks and custom requirements

checks.json stores the reviewed task and reusable project checks. Automatically
managed criteria, categories and paths are derived again for the next task.
Provenance, hashes and backups prevent silent overwrites of manual edits.
Complete custom checks remain mandatory; unknown fields and original commands
are preserved. On the first automatic task, older task-specific fields are
archived under `automation.importedTaskFields` and explicitly shown to the reviewer.

Detection covers built-in Node tests, locally installed Vitest, Jest and Playwright,
Python/pytest projects and TypeScript typechecks. Node, Vitest, Playwright and pytest
use JUnit; the Jest adapter converts actual assertion results into the JSON format
below. Preparation installs no packages. If pytest is missing, install it according
to the project instructions. Unknown build systems need a suitable custom check once.

Legacy plain npm test/exit-code checks remain stored. A detected structured replacement
is used only after independent comparison with their purpose. If no suitable replacement
exists, preparation stops. Merely renaming a check does not create test evidence.

All commands run in the project with your **user permissions**. Install project
dependencies first. Use local test data and noninteractive commands. Permanent
additional boundaries can be specified as exact path arrays in
`limits.allowedWritePaths` and `limits.allowedTestWritePaths`; preparation cannot expand them.

Optional reference example for a custom Node check. Normal Kilo tasks do not require
you to write this JSON manually. The test author may create the specified test file:

```json
{
  "schemaVersion": 2,
  "writePaths": ["src/stock.cjs"],
  "testWritePaths": ["tests/stock.test.cjs"],
  "changeTypes": ["other"],
  "acceptanceCriteria": [
    {"id": "AC-1", "description": "Recommend reordering below the minimum stock level, but not at or above it."}
  ],
  "regressionCheck": "tests",
  "checks": [
    {
      "name": "tests",
      "kind": "test",
      "reportFormat": "junit",
      "command": "node",
      "arguments": ["--test", "--test-reporter=junit", "--test-reporter-destination={report}", "tests/stock.test.cjs"],
      "timeoutSeconds": 120
    }
  ]
}
```

| Field | Meaning |
|---|---|
| `writePaths` | Exact production paths relative to repository root, with `/` separators. No globs. |
| `testWritePaths` | Exact paths for the test author, separate from writePaths. An empty array permits mapping existing tests only. |
| `acceptanceCriteria` | Unique IDs AC-1, AC-2, … and concrete descriptions. |
| `changeTypes` | One or more of security, ui, api, other. |
| `regressionCheck` | For Bugfix, the check whose specified regression cases must fail before the fix. |
| `checks[].kind` | test for behavior; integration for component interaction; static for typecheck/lint/build, for example. |
| `reportFormat` | For test/integration: junit or the JSON format below. Not needed for static checks. |

Each check requires a unique name, command, individual string arguments and an
integer timeout from 1 to 7200 seconds. At most twelve checks per task. Full acceptance
requires at least one test check; a successful build alone cannot cover behavior.

The runner replaces `{report}` in arguments with a fresh absolute path for that
check and phase. The same path is available as `LOKI_TEST_REPORT`. The test tool
must write its report there. Existing reports are never reused. Bundled adapters
are provisioned, but custom commands remain possible. The test author cannot
change either. Never use watch modes, installation, deployment or production
database commands as checks.

Project configuration, manifests/lockfiles, ignore files and credentials cannot
be approved as production files. Make any necessary changes yourself before the run.
Known test paths in writePaths are rejected; unusually named tests also belong
explicitly in testWritePaths.

## 4. What happens automatically

1. **Preparation and preparation review:** derive and independently review criteria,
   categories, file scope and local checks.
2. **Planning:** a read-only architect examines project rules, task and risks.
   Source changes and criteria are recorded.
3. **Test authoring:** shadow-test writes approved tests only, maps every criterion
   to concrete test IDs/check names, and names exact expected baseline failures.
4. **Test review:** shadow-test-reviewer examines tests in a fresh session before
   execution. Missing assertions, weakened existing tests, fabricated reports or
   unsafe side effects prevent execution.
5. **Baseline tests:** the runner executes checks. Bugfix requires actual failure
   of the specified regression cases. Features may allow declared new failures;
   Refactor requires a passing baseline.
6. **Implementation:** the coder edits production files only. Reviewed tests are
   protected through permissions and hash comparisons.
7. **Repeat checks and review:** tests run again; a separate reviewer assesses
   source state and actual change types.
8. **Required specialists:** security/integration reviews follow as required,
   each in a separate session.
9. **Validation:** another agent evaluates the functional significance of executed
   checks. The script also verifies criteria mappings and individual results.
   Only then can VERIFIED be issued.

Frontend/backend specialists may help sequentially during implementation. Only
one model generation runs at a time. Coder Fast changes implementation routing;
test review, code review and validation retain their own model assignments.

If a reviewed test must change, the task stops. Adjust the task/permissions if
needed and start a new run with test authoring and review again. A correction
round within the same run may change production only; at most one such round is allowed by default.

## 5. When specialist checks are mandatory

| Category | Examples | Required verification |
|---|---|---|
| security | Authentication, permissions, file access, external input, secrets, trust boundaries | Separate shadow-security with a passing verdict |
| ui | Interface, interaction, state | A mapped integration test result and shadow-integration |
| api | Interfaces, endpoints, component interaction | A mapped integration test result and shadow-integration |
| other | Internal logic without the above characteristics | Test review, code review and validation remain mandatory |

Your categories, planner/reviewer assessments and conservative path hints are
combined. Later classification may add checks but cannot weaken your classification.
If a reviewer discovers integration requirements after implementation and the
corresponding check is missing, the result is unverified. Add the check and restart.

Calling a unit test integration does not make it an integration test. The specialist
must examine its actual relationship to UI/API and executed cases. This semantic
classification remains a model judgment and can be wrong.

## 6. Supported reports

JUnit is evaluated through individual `<testcase>` elements. IDs are `classname::name`,
or just name when classname is empty. Duplicate IDs within a check are forbidden.
failure/error mean failed, skipped means skipped. XML DTDs and external entities
are rejected. Reports are limited to 16 MiB.

An approved custom test tool may alternatively write:

```json
{
  "schemaVersion": 1,
  "tests": [
    {"id": "stock::below-minimum", "status": "passed"},
    {"id": "stock::at-minimum", "status": "failed"},
    {"id": "optional-scenario", "status": "skipped"}
  ]
}
```

This illustrates structure, not a successful run. Values must come from actual
assertions. A custom reporter must not fabricate a blanket success list. Prefer
framework reporters where available. Change reporters outside the agent task.

Empty reports, zero executed tests, missing/skipped required cases, unexpected
baseline failures and failed final tests prevent VERIFIED. Unmapped skipped cases
remain visible. Expected baseline failures require exit code 1 and exactly the
previously named failing cases; import/syntax errors are not valid regression evidence.

## 7. Visible progress, starting and results

After loki_start, Kilo tracks the task with loki_status. Tool output shows phase,
agent role, requested model, state and current tool activity. loki_details returns
the bounded run report and events. LOKI-STATUS.md in the task directory provides
the same progress alongside chat. Displays come from actual run events.

Controlled phases run as separate external Kilo CLI sessions. They appear through
this status view, not automatically as native Kilo child tasks or a complete Inspector
graph. Native read-only chat subagents may have their own Kilo history. Roles,
activity and results are visible, not a complete internal reasoning process.

To cancel, explicitly ask Kilo to stop: loki_cancel terminates the owned process
tree; loki_status subsequently confirms CANCELLED. Cancelling a status query alone
does not stop a background job. Written changes are preserved for your diff review.

Alternatively, write a task in task.md and select **Terminal > Run Task** →
`Local AI: Automatic task with verification`. Specific tasks such as
`Local AI: Feature with verification`, Bugfix, Refactor and `(Coder Fast)` variants
also prepare checks.json automatically. The selected specific workflow remains
binding. Terminal tasks write events/evidence to the run directory; chat status
tools refer to jobs started through loki_start.

Review and Architecture remain read-only. Full review acceptance still requires
criteria and structured checks. Without checks, the maximum result is
REVIEWED_UNVALIDATED.

The terminal prints status and `runs\<run-id>\receipt.json`. This report contains
criteria, test session, test review, frozen test hashes, baseline/final results,
specialist verdicts and concrete rejection reasons.

| Status | Meaning |
|---|---|
| VERIFIED, exit 0 | All technical and agent-assisted verification conditions passed for this source state. |
| REVIEWED_UNVALIDATED, exit 2 | Read-only review without executable acceptance; not final code approval. |
| NOT_VERIFIED, exit 1 | Error, missing evidence or unresolved finding; inspect report. |
| NEEDS_INPUT in Kilo | Clarify a requirement/configuration change/missing prerequisite; no approval yet. |
| CANCELLED / FAILED in Kilo | Task cancelled or technical execution failed; inspect existing diff and evidence. |
| WORKER_UNRESPONSIVE in Kilo | Worker is not responding; automatic polling stops, process exit and result remain unconfirmed. |

More than 30 seconds in the startup queue or 120 seconds without a heartbeat
produces WORKER_UNRESPONSIVE. The project lock stays. Inspect logs and processes;
do not start another job or blindly remove the lock. Another query may show a
recovered worker; cancellation can still be recorded. Recover only after confirmed
process exit or a system restart, without treating recovery as task success.

Review the diff and application before committing. LoKiEnte creates no separate
worktree and makes no automatic commits/pushes. Existing changes are not reset.
Any changes after verification require another run.

Tests run under your Windows account. Sanitized environments and separate temp/profile
paths are not an OS sandbox. Project code/tests can still access files and networks.
Use approved commands, local data and no production credentials. Structured reports
alone do not prove meaningful or tamper-proof tests.

## 8. Update existing projects

Stop active tasks/windows and run the new provisioner with the existing installation
directory. Reachable registered projects, tasks and LOKI-WORKFLOW.md are updated.
Legacy checks.json files are backed up and extended. Previously authorized,
unambiguous test paths move from writePaths to testWritePaths on first migration.
Commands/custom fields remain. Managed VS Code tasks gain automatic preparation;
new requests can start directly in chat. Criteria, categories and suitable reports
are derived and reviewed for each task. Legacy exit-code-only checks do not
automatically become complete evidence.

Existing personal ANLEITUNG.md or GUIDE.md files remain untouched. The managed
LOKI-WORKFLOW.md describes the current workflow. German companions are supplied
as LOKI-WORKFLOW.de.md, GUIDE.de.md and task.de.md. Existing user task text is not
translated or replaced. Legacy managed German task labels are migrated without
duplicating them or deleting unrelated custom tasks.

Technical references: [Node reporters](https://nodejs.org/api/test.html#test-reporters)
and [Kilo agents](https://kilo.ai/docs/customize/custom-subagents). Approved versions
for your installation appear in the provisioning report.

## Welcome trial

Provisioning registers welcome/workflow-test. Select it in the launcher and paste
its README task into shadow-chat. Its intentionally faulty discount function needs
only Node.js without external packages. An initial commit already exists. Updates
preserve modifications; New-WelcomeTestProject.ps1 -NewExample creates a separate
fresh attempt. The test exercises the basic workflow with failing/passing tests;
security/integration roles are required only when applicable.
