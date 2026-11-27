# Provisioning package validation

[Deutsch](VALIDATION.de.md)

## Automatic model options and Configure model reset - package 2026.11.27.6

The next target setup stopped after verifying existing model files: a manually
loaded LM Studio model had no surviving LoKiEnte ownership record after runtime
state was deleted. Configure now stops the known idle managed router, unloads
uniquely identified local LM Studio instances through bounded targeted REST calls
and verifies an empty loaded-model list before recommendation hardware measurement
and smoke tests. This is an explicit Configure operation; active local inference
may be interrupted. Model files and normal runner/controller ownership guards are
preserved. Missing explicit custom Single-model files still produce the manual
download instructions before disrupting a running model. Keep never resets models.

New switches pass through the PS5.1 bootstrap, JSON child request and PS7 setup:
UseRecommendedModelsBasedOnGPU selects current GPU/RAM recommendations without model
prompts (Configure, exact existing-file reuse and missing-file downloads);
SilentMode explicitly confirms the initial installation prompt for this invocation;
WorkspaceTrust prefers an owned previously trusted acceptance project in the same
work profile. Reports keep fresh run IDs while the project/workspace path stays
unchanged. VS Code must still confirm actual current trust; new/deleted profiles,
revocation and missing history may require the ordinary trust interaction. No
trust database or global security option is edited. The visible Kilo-response
check remains manual and is covered by cancellation/the overall deadline.
LM Studio catalog discovery is bounded to 30 checks. Confirmation origin, automatic
selection strategy/hardware and model-reset outcomes are recorded locally.

Local regressions: 92 JavaScript tests passed in the combined 13-file run.
The PowerShell group passed 27 suites; native Git clone and junction creation
remain BLOCKED by this development host. Additional existing model-selection and
bootstrap junction branches share that host restriction. New option tests passed
20 checks with actual hashes/files and a real JSON/PowerShell handoff; Configure
reset passed 23 checks reproducing the lost-ownership error, targeted unload,
post-unload evidence and unchanged normal ownership rejection. The production
launch suite passed 53 checks, including actual Git project reuse with a fresh
report ID. Model-pool lifecycle 51, native failure handling 29 and partial GPU
offload 14 checks passed; real setup integration proves automatic recommendations
reach the pool without prompts and Keep does not call the reset.

This candidate does not change a running installation/test on another computer.
Actual GPU/model unload, inference and GUI acceptance must be rerun there with
this exact package. Target acceptance remains UNVERIFIED; PR, main merge and
release wait for successful target evidence. Docker and Hyper-V are not required.

## Startup discovery, Output feedback and production-profile acceptance - package 2026.11.27.5

The next target diagnostics showed a trusted host, then BLOCKED acceptance in
under four seconds because Kilo was queried before discovery completed. The same
host activated Kilo about twelve seconds later. No model round trip ran. The
generated project lacked a Git repository/first commit. A third-party Swagger
Viewer document-change handler emitted 153 renderer errors while the already
finished test window continued forwarding logs. This upload contained diagnostics
and acceptance evidence, not a new provisioning report.

This candidate waits for Kilo discovery and records installed/visible extension
evidence separately. Its synthetic project gets an owned Git repository and
initial commit through real bounded Git commands, without inherited Git write
redirections, hooks or signing. User repositories are preserved. Kilo's worktree
manager requires a commit as its starting point.

Acceptance now uses the actual managed work profile and installed extension
directory. Desktop and test share their native collector, launch arguments,
environment builder and workspace generator. Already-open managed windows block
the launch. Configuration/source file hashes, explicit effective settings, exposed
user/workspace scopes and the saved versus running Kilo configuration must match.
Inherited default object keys remain allowed. Extensions visible in the actual
host are recorded. The sidebar command asks to close its window, then starts the
same native acceptance through a hidden runner.

Identical recent VS Code warning/error blocks, including stack continuations,
are compressed per source with silent counters and original source paths. Distinct
errors remain visible; original logs retain all occurrences. This breaks Output
feedback without changing the third-party extension. Completion is announced after
the report is saved, background forwarding stops in that test window, and a
completed run is not replayed after an Extension Host reload. Cancellation and
the overall deadline block acceptance, terminate its native child and retain
command evidence. They cannot establish a late inference PASS.

Local evidence: 89 JavaScript cases passed in the combined 13-file regression
run. The PowerShell run passed 22 suites; native local Git clone and junction
creation remain BLOCKED by the development host's Windows restrictions. The new
production-launch regression passed 28 checks with actual Node/Git/files/workspace
preparation and a synthetic GUI boundary, including early editor exit. Native
collector exit status is written atomically using bounded temporary paths. The
additional bootstrap suite is BLOCKED at junction creation on this host. The controlled document-change feedback
test becomes quiescent while forwarding distinct new errors. Replaying the supplied
renderer log compresses 153 Swagger messages to its two distinct blocks, suppressing
170 duplicate warning/error blocks (3,643 lines) across that source.

Real VS Code/Kilo/LM Studio and visual acceptance on the target PC are still
UNVERIFIED. No Docker or Hyper-V is required. Reprovision this branch's generated
installer, close the managed windows and rerun the native test. PR, main merge
and release remain gated on successful target evidence.

## Target report follow-up - package 2026.11.27.4

The supplied Windows run of build 2026.11.27.3 finished with warnings. Its live
acceptance recorded one host PASS and eight BLOCKED cases because Workspace Trust
was not granted. Kilo/UI inference was not executed in that acceptance run.
The other provisioning smoke checks passed for three models; coder-high remained
deferred. The deliberate no-model CLI capability probe was the only nonzero
native command. A missing registered project directory is a separate repair warning.

Corrections in this build:
- Launch the installed startup helper 0.3.2 in an ordinary, isolated VS Code
  window, replacing the extension-development/test launch. Trust remains enabled;
  the user can open Manage Workspace Trust, has ten minutes to decide, and the
  incremental report/console identifies the waiting phase. No trust database or
  global security setting is edited.
- Compare the LM Studio total-minus-GPU allocation against host RAM, and the GPU
  allocation against VRAM, retaining the 3 GiB/1 GiB reserves. Both single-model
  and pool paths use the same check. Invalid or low-confidence estimates still
  cannot authorize a normal load. The reported hardware/estimate combination is
  covered by a synthetic regression; real loading must be retested on the target.
- Preserve scalar context/memory/boolean values in JSON rather than converting
  pipeline-decorated numbers to empty objects.
- Mark the exact negative capability probe EXPECTED_NONZERO_EXIT while retaining
  its exit code and streams. Actual model/runtime/authentication failures remain
  errors. Historical log replay retains its severity label without producing a
  new live error notification.

Local regression evidence: 70 JavaScript cases across the combined ten-file run
passed; model-pool lifecycle 51, partial GPU offload/memory boundaries 14,
single-model fit 6, native model failures 29, CLI compatibility 16, CPU embedding
47, report serialization 13 and acceptance policy 25 checks passed. The initial
broad native-deadline check exceeded its limit under load; process startup now
uses the same command budget, and the unchanged seven-case native/config/logging
suite passed after that correction. Native Git clone and junction creation remain
BLOCKED by this agent host. Windows PowerShell 5.1 audit passed all 51 checks, including its extracted
capability-helper dependency. Final targeted diagnostics/startup checks passed
20 cases, including current startup errors versus dated historical backfill.
This fix is a candidate on its own branch. A new successful target run, including real Kilo
responses, is required before a PR, main merge or release.

## Provisioning diagnostics, native launcher and project repair - package 2026.11.27.3

This build adds incremental schema-2 reporting, bootstrap handoff evidence, redacted
native stdout/stderr and partial acceptance preservation. The desktop shortcut targets
a compiled Windows GUI executable; real child-process/argument/redaction tests verify
that the collector needs no console. A launch/version/profile handshake is required
before the desktop script claims VS Code startup. Kilo discovery handles delayed
registration and records installed manifests separately from active host extensions.

Target acceptance has no Docker/Hyper-V prerequisite. Its native dependency checks
include a synthetic local Git clone in addition to the installed Kilo/config/tools/search.
Project selection retains existing folders and adds bounded Git discovery, cloning
and repair with backups and preservation of task/checks/custom settings.

Relevant new tests: Test-ProvisionReport.ps1 (real files/process outputs),
Test-DesktopRunner.ps1 (real GUI-subsystem executable and child collector; synthetic
host handshake), Test-KiloStartup.mjs (simulated extension registry), Test-ProjectGit.ps1
(real Git and filesystem repair), Test-ProjectSelection.ps1 and Test-LauncherIcon.ps1.
The GUI dialog and real VS Code/Kilo/LM Studio inference still require target acceptance.

The native Git clone test is BLOCKED in this agent session because Windows denies
MSYS NtCreateDirectoryObject with 0xC0000022. Independent Git discovery/repair checks
continue against a separately initialized fixture and are not counted as successful
cloning. Existing junction tests are likewise blocked by access denial. Neither a VM
nor a container would turn these into evidence for the target machine; no such workaround
is used. Missing target-machine evidence remains explicitly unverified.

## Live toolchain acceptance and unified output - package 2026.11.27.2

Provisioning offers a live acceptance run after setup. Explicit RunAcceptanceTest
and SkipAcceptanceTest switches pass through the standalone bootstrap and request
handoff. Empty interactive input selects Run. Skipping records SKIPPED in both
JSON and JUnit and leaves provisioning with an unverified warning. FAIL exits 1;
BLOCKED exits 2; an explicit skip exits 0 without claiming verification.

The live runner uses the installed desktop VS Code and its real Extension Host
test interface, installed Kilo extension/bundled executable, prepared local-only
configuration and LM Studio. It checks extension dependencies, standalone and
embedded CLI configuration/tool imports/search, each configured model's actual
read-tool/final-answer round trip, and a real Kilo webview request. Dual-mode
router evidence correlates only a random nonce hash and response-match flag;
raw prompts and completions are not added to router events. A separate manual
visual observation confirms the actual chat response. Noninteractive, incomplete,
missing, failed or skipped evidence cannot produce a full PASS. Enabled indexing
also requires real embedding inference and a native LanceDB write/search probe;
this is not a full repository-indexing workload test.

The LoKiEnte Output channel merges available managed VS Code/Kilo logs, router
events, controller logs, local tool events and LM Studio server logs with source
and severity. Health checks report connectivity, not inference success. Tests
exercise redaction, bounded log replay, UTF-8 splits, rotation, HTTP failure and
recovery, malformed/oversized data, router nonce correlation, interrupted streams,
actual native subprocess deadlines and inherited output pipes. Startup UI unit
tests simulate VS Code; they are not live-host evidence.

Relevant suites: Test-ToolchainAcceptance.mjs, Test-ToolchainDiagnostics.mjs,
Test-RouterEvidence.mjs, Test-ToolchainNative.ps1, Test-ToolchainPolicy.ps1,
Test-ToolchainProvisioning.ps1, Test-VsCodeStartup.mjs, Test-VsCodeProfile.ps1,
Test-RouterLifecycle.ps1, Test-RipgrepIntegration.ps1 and Test-SelectionIntegration.ps1.
The installed live test is app/Test-Toolchain.ps1. Since build 2026.11.27.4 the
installed helper starts it in an ordinary window; vscode-tests/toolchain.cjs is
only the legacy development-host entry. Reports remain local under diagnostics/toolchain.

Local validation on 2026-11-27: the combined nine-suite JavaScript run passed
61 cases. The final startup-specific run additionally checks the sidebar-focus
deadline (11 cases). Acceptance policy/preparation passed 21 checks, provisioning
skip/report integration 13, native/config/LM Studio log wrappers 7, VSIX/profile
packaging 36 and router lifecycle 18. The Windows PowerShell 5.1 audit passed
51 checks; native model-command failure tests passed 25. Settings preservation,
selection/search integration, indexing policy/launch, CLI resolution, workflow
discovery, workspace guides and localization also passed. Kilo-import junction
preflight is BLOCKED by Windows access denial, not passed. The installer payload
is compared byte-for-byte with every package source and both public sources and
decoded payload are scanned with Gitleaks; these checks do not establish inference.

Target acceptance is still UNVERIFIED in this development environment: there is
no managed D:\LoKi installation/Kilo runtime here. An isolated real desktop-host
launch attempt produced no Extension Host report before its deadline; it is not
counted as passed. The affected installation on the other PC must run the new
installer/test and produce its own report. The existing bootstrap and Kilo-import junction tests
are blocked here by Windows junction-creation access denial; that check
was not weakened or declared passed.

## Bounded model switching and actionable errors - package 2026.11.27.1

The original native-command implementation was reproduced returning after
12.75 seconds despite a five-second deadline: a child inherited its output
handles after the CLI process exited. Output draining now shares the command
deadline and uses cancellable reads. Status/catalog queries and memory estimates
are limited to 60 seconds; actual model loads retain 900 seconds. An uncertain
load timeout blocks further router switches until a deliberate restart.

Regression suites exercise real subprocesses, inherited output handles, the
PowerShell controller, loopback HTTP, failure reports, aliases and installation
paths with spaces. LM Studio/GPU boundaries in lifecycle tests are simulated.
Unsupported architecture, memory refusal and other load failures remain distinct;
failed profiles require all chat/tool smoke checks again before verification.
Router health and metadata-only events expose loading, generation and errors.
Private exception details stay in the local controller report.

Relevant suites: Test-ModelLoadFailures.ps1, Test-ModelPool.ps1,
Test-SingleModelFit.ps1, Test-LmsCliCompatibility.ps1, Test-PartialGpuOffload.ps1,
Test-ModelVariants.ps1, Test-ManualModels.ps1, Test-Embedding.ps1,
Test-RouterLifecycle.ps1, Test-ModelAction.ps1, Test-ProvisionSettings.ps1,
Test-Localization.ps1, Test-ModelRouter.mjs and Test-EmbeddingRouter.mjs.
The manual-model suite previously assumed a top-level setup assignment; it now
inspects the actual model-configuration branch. Its original failure was also
confirmed against the unchanged source.

The reported affected installation is on a different PC. Successful manual
loading there does not prove managed context/offload settings or API access.
These regressions establish the corrected waits and error handling, not the
unobserved cause or successful real-model inference on that PC. No runtime or
model selection is changed automatically by this correction.

This document preserves the validation history and its original limitations.
Older sections describe the behavior and evidence of their stated release, not
necessarily the current defaults. Current usage is documented in [README.md](README.md).

## Local 9B model in the managed Kilo IDE

On 24 November 2026 a developer entered an ordinary feature request in the Kilo Code 7.8.30 sidebar of the managed VS Code workspace. LM Studio ran Qwen3.5 9B Q4_K_M locally with a 16,384-token context. Each row is a separate chat submission. No scripted model replies were used. The task was to add HEAD support to the existing summary API, preserve GET response headers and the health endpoint, and add integration coverage.

| Request | Last observed phase | Outcome |
| --- | --- | --- |
| `09b33099` | Workflow startup | Git rejected a missing inherited configuration value. No specialist started. Fixed in [PR #13](https://github.com/mauricehuschke/LoKiEnte/pull/13). |
| `7f225dc0` | `shadow-preparer` | The agent inspected the application and returned malformed JSON. The runner stopped before any write. [PR #14](https://github.com/mauricehuschke/LoKiEnte/pull/14) added a single read-only retry. |
| `6b370348` | `shadow-architect` | The retry produced a contract and an independent agent approved it. The planning prompt then named a missing AGENTS.md. The architect returned a plan, but its failed file read invalidated the phase. No implementation or feature tests ran. |
| `fd50cc55` | `shadow-preparer` (retry) | With the updated planning prompt installed, neither preparation attempt delivered an accepted contract. The runner stopped at the retry with zero feature checks executed. The working tree stayed clean. |

The independent baseline probe returned 405 for HEAD and 200 for GET. All four native sessions ended in `NOT_VERIFIED`. The furthest reached an approved contract and the architecture phase. The [separate successful reference run](https://github.com/mauricehuschke/LoKiEnte/blob/main/examples/support-board/head-verification.json) used scripted role replies, real Git checks and loopback HTTP tests. Six of eight tests passed before implementation and all eight passed afterwards. The [tour](https://lokiente.dev/#in-action) labels the two outcomes separately.

## Optional indexing start policy — package 2026.11.19.1

Indexing now defaults to Off, including existing projects and installations.
Provisioning offers Off, OnDemand and Automatic; an explicit `-IndexingMode`
skips the menu. OnDemand prepares dependencies without loading embeddings and
asks at each launcher start (default No). Automatic checks embeddings at setup
and launch, then respects Kilo's one-time project consent. Failed readiness keeps
Kilo indexing disabled for that launch. No internal VS Code consent database is
modified. See [README.md](README.md) for commands and session restart requirements.

Regression evidence:

- Indexing policy/migration: 32 checks; actual launcher configuration path: 8;
  model-selection setup integration: 5; CPU embedding and safe disable/unload: 47.
  Coverage includes legacy defaults, preserving consent while disabling the global
  indexer, no embedding initialization/download in Off, OnDemand deferral, explicit
  launch opt-in, failed readiness and refusing to unload busy or ambiguous models.
- The actual Kilo 7.8.30 indexer remained Disabled with zero embedding requests
  even after project consent was explicitly enabled against a synthetic backend.
  Its actual effective-config verifier accepted the complete generated Off profile
  without LanceDB installed. This verifies disabling; it is not a real-model
  inference or retrieval-quality result.
- All 33 Node router/startup/sync tests passed. The full 54-check reviewed workflow
  passed with real processes/Git and synthetic agent responses. Model pool (44),
  partial offload (8), router lifecycle (18), provisioning settings (6), workspace
  migration (14), localization (28), start commands (7), ripgrep setup (7), workflow
  discovery (13) and tool-import preflight (18) passed.
- Bootstrap/handoff: 42 checks; installation-location migration and audit each
  passed 51 checks under Windows PowerShell 5.1. No real application installation,
  model download or GPU inference is performed by these regression fixtures.

Target acceptance remains pending: close all LoKiEnte windows, reprovision the
existing installation, then check Off, OnDemand No/Yes and Automatic on a small
consented project. Confirm that Off starts without IDX errors or an embedding
load, OnDemand No stays inactive, and an enabled run reaches Complete when RAM
and LM Studio are ready. Existing extension-only sync and project quality checks
must continue to work. Main, releases and platform branches are unchanged.

## Conservative CPU embedding load — package 2026.11.18.26

The target report identified an embedding load blocked by LOW estimate confidence,
with no reported guardrail approval. The previous combined error could misleadingly
suggest a measured RAM shortage. The regression now covers that input with a
conservative budget and unchanged reserve, followed by actual load and inference
boundaries. The policy applies only to the hash-verified CPU embedding model.

The embedding suite passed 44 checks, including malformed estimates, colored/wrapped
CLI output, insufficient reserve, explicit guardrail denial, actual load rejection,
post-load and post-inference RAM pressure, and rollback restrictions for busy,
substituted and duplicate instances. Existing model-pool (44), partial-offload (8),
router-lifecycle (18) and selection-integration (3) regressions also passed.
LM Studio, model inference and memory measurements are mocked in these tests;
the actual target-machine indexing result still requires acceptance. The user
confirmed extension-only sync works; main and the published release remain unchanged.

## Embedding compatibility and extension-only sync — package 2026.11.18.25

This candidate is isolated from the stable release. The new embedding router and
sync-guide tests, together with the existing model-router and startup tests, passed
all 33 Node tests. PowerShell regressions cover embedding readiness and diagnostics,
router replacement, profile preservation, provisioning settings, launcher commands,
project selection, workspace migration, model pools and partial GPU offload.
All 14 selected PowerShell suites passed 334 checks, including the complete
54-check quality workflow, bootstrap (42), localization (28), entry scripts (4)
and installation-location migration under Windows PowerShell 5.1 (51). The tests
use synthetic agent responses and do not install applications or download models.
The installer contains all 98 source files byte-for-byte with a matching checksum.
Syntax checks passed for 67 PowerShell files, 14 Node files and the Python builder;
72 local Markdown links, two JSON files and six JSON examples were validated.

The actual Kilo 7.8.30 indexer reproduced the reported initialization message when
a synthetic local backend rejected `dimensions`. The same indexer reached Complete
through the new route, using real LanceDB 0.26.2 and synthetic 768-dimensional
embeddings. A direct backend accepting the field also completed. This demonstrates
the compatibility fix; it does not establish the cause on a machine without logs
or validate semantic retrieval quality with a real model.

The packaged startup helper 0.1.2 was installed and activated in an isolated
VS Code 1.146.0 profile with Kilo 7.8.30. Both LoKiEnte commands, the supported sync
configuration command and Kilo focus command were available, Kilo was active and
the managed AI visibility setting remained enabled. No signed-in account was used.
The helper opens the official checklist; the user must select Extensions only and
apply it. Tests verify guidance and failure handling, not a fictitious automatic
category change. Existing local preferences and remote account data are preserved.

Target-machine installation, real LM Studio embeddings/GPU inference, project-index
completion and signed-in extension-only synchronization remain acceptance checks.
Neither a successful preflight nor an opened sync dialog proves those outcomes.

## English defaults and German documentation — package 2026.11.18.22

40 independent PowerShell/Node suites passed after the language update. The complete
quality workflow passed all 54 checks; bootstrap passed 42, including the Windows
PowerShell 5.1 handoff. Agent responses and GPU/LM Studio boundaries remain synthetic;
these results do not replace target-machine installation, inference or GUI acceptance.

`tests/Test-Localization.ps1` adds 28 checks covering English defaults, German
companions, deployed language links, legacy task/folder migration, preservation of
custom tasks/settings/folders/guides, and Welcome README migration with backups.
Only an unchanged bundled German Welcome README is replaced by English. Customized
guides, example code and Git HEAD remain unchanged; missing German companions are added.

The active agent configuration references only the English rules. German rules and
task/Welcome templates remain readable alongside them. Provisioning menus, messages,
diagnostics and workflow status are English; native operating-system and third-party
output can still follow their own locale. No runtime language switch was added.

Authentication failures now carry a language-independent error marker. The 24-check
embedding suite includes HTTP 401/403 through the actual API wrapper and verifies
that authentication remains a blocking error without exposing response content.
The concurrent-file-publication regression checks the native I/O exception type
instead of a localized Windows message. Model selection passed 28 checks.

Additional validation: 65 PowerShell files and 9 Node files parsed successfully;
the Python builder parsed; all 16 public provisioning parameters are documented.
All 20 Markdown files form 10 adjacent language pairs; local links and six JSON
examples passed validation. Non-string PowerShell token changes are confined to
template loading, bilingual migration and the authentication marker.

The rebuilt standalone installer contains 86 files, compared byte-for-byte with
the source package, with matching SHA-256. Gitleaks and supplementary scans of
current files and the decoded payload found no credentials or private identifiers.
This statement covers file content, not a rewrite of historical Git author metadata.

## LoKiEnte logo and vendor-neutral naming — package 2026.11.18.21

39 independent PowerShell/Node test suites passed, covering bootstrap including
Windows PowerShell 5.1, Welcome, models, updates and the Kilo-chat-to-runner path
with synthetic model responses. Updates retain the saved API-token environment
variable name.

The new Windows `tests/Test-LauncherIcon.ps1` covers eight aspects: ICO sizes,
Windows decoding, saved shortcut properties, creation, repeated updates and
backup/renaming of matching old shortcuts. A shortcut with different launch
arguments remains. All shortcuts are created in temporary directories; the real
desktop is not modified. Six further checks confirm preservation of custom VS Code
settings, backups and customized terminal profiles when renaming the managed profile.
The PNG frames of all seven ICO sizes and exact byte equality between embedded
payload and source package were also checked.

Current files, images, extracted payload and historical content were inspected with
Gitleaks and additional private-identifier checks. No credentials or private
identifiers were found in the current files. A file-content scan does not replace
inspection of Git-history author metadata.

The title and visible messages use LoKiEnte. Vendor-specific hardware assumptions
were removed from descriptions; technical identifiers and existing paths remain
update-compatible. The package targets Windows x64 with its existing NVIDIA checks;
it is not a Linux/macOS installer. These regressions do not establish a fresh
installation or real model inference on additional hardware.

## Full package review — package 2026.11.18.20

The rerun covered all independent existing PowerShell and Node suites: bootstrap/
Windows PowerShell 5.1, selection, memory limits, router, dependencies, Kilo
configuration, complete quality workflow and chat-to-runner integration.
`Test-CoderWorkflow` aliases QualityWorkflow and is not counted twice.

Result: 38 independent suites passed. An outdated ripgrep setup harness was extended
for the new setup boundaries and rerun successfully; real registry/Welcome paths
have their own tests. The complete quality workflow passed all 54 checks.

Additional checks covered custom VS Code settings/terminal profiles during managed
updates (4), launch helpers with an explicit update target and literal paths (4),
and Welcome creation/retry after a simulated Git failure/preservation of edited
examples (14). Welcome publishes only a fully initialized Git repository. Git
redirections stop before file writes. Failed initializations remain in separate
diagnostic directories and do not block retrying the normal destination.

Custom checks, tasks and unmanaged settings remain. Managed agent configuration,
LoKiEnte tasks and designated profile settings are intentionally updated to the
package version, with backups. Unreachable projects remain registered and produce
warnings. Approved dependencies are updated; newer versions are not downgraded.

The installer ZIP payload and SHA-256 are compared against every source file. The
former separate ZIP is archived and not used by the installer. Models, installations
and user projects were not changed for these tests. Installation/model boundaries
are simulated; Git, Node, PowerShell and local HTTP processes actually run. Real
GPU/GUI acceptance uses the Welcome request on the target Windows PC.

## Automatic tasks and visible workflow — package 2026.11.18.18

New or extended checks:

- `tests/Test-TaskPreparation.ps1`: real temporary Git projects; candidate detection
  without executing project tools; new/existing check catalogues, task-specific
  renewal, backups, custom fields/commands, manual provenance conflicts, persistent
  boundaries and concurrent edits.
- `node tests/Test-TaskPreparation.mjs`: a real Node test producing JUnit, fixed
  arguments, path boundaries, missing frameworks, Jest assertion conversion and
  exact Playwright file filters for Windows and normalized paths.
- `node tests/Test-WorkflowTools.mjs`: local Kilo tools/background jobs; project
  binding, status, process boundaries, cancellation and failure paths.
- `tests/Test-KiloWorkflowEndToEnd.ps1`: tool request through bridge, background
  process and real runner through automatic configuration, eight separate agent
  roles and real red/green Node reports. Agent responses are synthetic; this tests
  the complete wiring.
- `tests/Test-WorkspaceGuide.ps1`: automatic tasks/current guides for new and
  existing registrations; preservation of custom tasks, commands and task files.
- `tests/Test-QualityWorkflow.ps1`: test authors, frozen tests and independent
  acceptance gates. Synthetic agent responses test control logic, not model quality.
- `tests/Test-WorkflowProgress.ps1`: output before process exit, simultaneous stderr
  reading, timeout, termination after callback failure and bounded events.
- `tests/Test-KiloWorkflowDiscovery.ps1`: tool registration, schemas and role-based
  permissions without inference; failures remain closed.
- `tests/Test-KiloToolImportPreflight.ps1`: detect foreign custom tools and altered/
  linked shims before import without modifying user files.

The following groups passed for this version:

| Suite | Passed |
|---|---:|
| Complete quality workflow with automatic preparation | 54 |
| Preparation / fixed framework adapters | 27 / 11 |
| Chat tools and worker / complete bridge-runner workflow | 12 / 14 |
| Progress stream / Kilo registry / import preflight | 9 / 13 / 18 |
| Acceptance contract and structured reports | 27 |
| Workspace/project migration | 12 |
| Kilo metadata / launch commands | 17 / 5 |
| Project selection / setup integration | 14 / 3 |
| Bootstrap including Windows PowerShell 5.1 and junction checks | 42 |

PowerShell/Node syntax checks passed too. Official Kilo CLI 7.8.30 loaded all four
tools with the generated configuration: available to main chat, denied to the
implementer. Complete effective configuration was checked without inference. An
independent code review found a duplicate-worker locking defect and missing model
information in status; both were corrected and covered by regressions.

Older counts below refer to earlier revisions. The complete bridge/runner test
passed 14 groups. Local framework adapters are testable without downloads. The Node
run uses real assertions; Jest is checked with representative assertion reports.
Vitest, Playwright and pytest additionally require a real project run.

Target-machine acceptance after reprovisioning:

1. Open a new and an existing registered Git project through the launcher; verify
   preservation of custom VS Code tasks and checks.
2. Enter a small request directly in `shadow-chat` without editing `task.md` or
   `checks.json`. Observe `loki_start`, preparation, independent preparation review
   and subsequent quality phases.
3. Check actual agent roles, requested role models and phases in `loki_status` and
   `LOKI-STATUS.md`. `loki_details` must refer to the matching report. External
   runner phases are not assumed to appear as native task-child sessions.
4. Submit a second request: new criteria/file paths, preserved custom checks and
   backed-up previous state must be inspectable.
5. In a separate trial, use an unclear request or missing test adapter: expect
   specific `NEEDS_INPUT` and no writing implementation phase.
6. Explicitly cancel an active trial and wait for `CANCELLED`. Source changes remain
   for diff review. `WORKER_UNRESPONSIVE` does not establish termination: after
   30 seconds without startup or 120 seconds without heartbeat, stop polling,
   inspect logs/processes and do not remove the lock without verification.

These steps do not replace functional acceptance or testing with real models,
the installed Kilo extension and target hardware.

## Quality workflow — package 2026.11.18.17

New executable checks:

- `tests/Test-AcceptancePolicy.ps1`: fixed criteria, concrete case mappings, JSON/
  JUnit, real Node JUnit, empty/skipped/missing cases, unexpected baseline failures,
  duplicate IDs and XML entities.
- `tests/Test-QualityWorkflow.ps1`, also accessible through `Test-CoderWorkflow.ps1`:
  real repositories/processes/assertions before and after implementation; controlled
  synthetic agent responses. Covers test author/review, High/Fast, write boundaries,
  frozen tests, fresh sessions, fixed criteria, mandatory security/integration,
  later risk escalation and invalid reports.
- `tests/Test-WorkspaceGuide.ps1`: new/existing workspaces, migration, custom
  commands and repeatable guide updates.

These tests do not turn simulated model/GUI behavior into hardware acceptance.
Run a small task with real models after provisioning. Following sections record
earlier test states and their original limits.

## Provisioning and updates — package 2026.11.17.16

Workspace migration tests cover a new directory, an existing registration, custom
settings/tasks and a temporarily unreachable registration. Version tests simulate
WinGet/npm and verify exact identity, approval, verification and preservation of
already newer releases. Real installation and the first Kilo run remain separate
acceptance steps on the Windows PC.

## Quality checks — package 2026.11.17.15

Windows tests use real Git, PowerShell and separate processes with synthetic agent
responses. They cover lock conflicts, write scope, no forwarding of a test secret
through an environment variable, and a check that fails before the fix and passes
afterwards. Model tests simulate memory and LM Studio responses. Router lifecycle
checks startup/reuse after a changed memory estimate over real loopback HTTP.

## Accept semantic search on the Windows PC

1. From the installation root in PowerShell 7, run `./app/New-ShadowIndexProbe.ps1`.
   It creates synthetic files only, under `diagnostics`, and prints the directory
   plus expected matches.
2. Open the directory through the desktop shortcut, enable local indexing for it
   in Kilo and wait for **Complete**.
3. Ask Kilo to use only `semantic_search` for “When should we order more stock?”
   Tool output must include `stock.ts` and the printed positive marker. A chat
   assertion or ordinary file-search match is not evidence.
4. Use the same tool separately for “lunar telescope green comet” and “desert weather
   station wind speed”. Neither ignored file nor its marker may appear in any tool
   output. Compare with PowerShell's output without copying markers into chat.
5. If exclusions fail, do not yet index real projects with sensitive files. Inspect
   ignore rules/the project's actual index and repeat with a new probe directory.

The provisioning report establishes the embedding endpoint. Search/exclusion
acceptance must happen in the actually installed Kilo interface.

## Launch menu — package 2026.11.17.14

Before model startup, the launcher offers known projects, another existing directory
and cancellation. Explicit `-ProjectPath` bypasses the menu. The shortcut passes
`-PauseOnError`.

Executed on Windows with PowerShell 7:

- `tests/Test-ProjectSelection.ps1`: 14 checks, including registration/reselection,
  Unicode/special characters, invalid input, unreachable folders, preservation of
  project files and launcher cancellation.
- `tests/Test-StartCommand.ps1`: 5 checks.
- `tests/Test-WorkspaceGuide.ps1`: 4 checks.
- `tests/Test-Bootstrap.ps1`: 39 checks, including native Windows junctions and
  audit handoff under Windows PowerShell 5.1.

Cancellation tests use inert runtime modules; they start neither models nor VS Code.
Desktop shortcut, GPU and complete startup still require target-machine verification.
The historical reports below do not replace it.

## Memory fit as a warning — 2026.11.17.13

In this historical release, an unproven LoKiEnte memory fit led to an explicitly
announced loading attempt without disabling LM Studio guardrails. If rejected,
model files remained and provisioning ended with `PROVISIONED_WITH_WARNINGS` and
exit 0. Unverified profiles were not reported as passed; a later request retried
loading and tests. Current opt-in behavior is described in the current README.

Regressions simulate insufficient memory, accepted/rejected loads, later recovery,
router failures, Single mode and the CPU embedding model. They do not establish
actual memory usage or LM Studio behavior on the target PC.

## Kilo extension 7.8.30 — 2026.11.17.12

The isolated 7.8.30 backend was checked with four model labels and the LoKiEnte
agents. It indexed a synthetic Python file to `Complete` using LanceDB 0.26.2 and
a simulated local embedding endpoint. Separate Kilo CLI 7.8.27 passed effective
configuration/agent checks. Backend file search/listing passed with verified Windows
ripgrep. Real LM Studio inference and indexing on the target remain separate checks.

## Separate coding profiles — 2026.11.17.11

Coder High/Fast are separately selectable router profiles. Names include role and
actual model; Coder Fast tasks retain independent review and validation. The embedding
endpoint/index are separate from this selection. In an isolated test, Kilo 7.8.28's
provider API returned all four role-labeled models; selectable built-in agents were
absent while internal helpers remained. Further tests cover pool migration,
router switching and the real review workflow with synthetic model responses.
The target UI and LM Studio still require verification.

## Local CPU embeddings and index configuration — 2026.11.17.10

`Test-Embedding.ps1` simulates LM Studio boundaries to check ownership, RAM reserve,
CPU load intent, reuse, vector responses and loopback configuration. Pool lifecycle
was rerun unchanged. LanceDB 0.26.2 was installed in an isolated test directory and
its native module loaded. Effective configuration was read with the Kilo 7.8.28
VS Code backend in an isolated profile; separate CLI 7.8.27 also passed. The same
backend indexed a synthetic Python file to `Complete` with LanceDB and a simulated
local embedding endpoint. This does not establish real target-machine inference/indexing.

## LoKiEnte windows and Copilot — 2026.11.17.9

New isolated windows receive `--disable-extension` for both GitHub Copilot extensions.
Other profiles/open windows are unchanged. Argument tests cover IDs, new-window
startup and isolated paths; effective disabling requires target verification. This
change neither enables semantic indexing nor fixes an evidenced reasoning issue.

## Kilo file search and project guide — 2026.11.17.8

Official ripgrep 15.1.0's Windows x64 archive and contained `rg.exe` have separate
pinned SHA-256 checks. Setup installs only into the isolated Kilo cache and performs
real Kilo grep/listing tests through the separate CLI and extension backend. Unknown
existing executables are not overwritten.

The official archive, executable and Kilo CLI 7.8.27 were tested locally through
both the native Windows binary and npm entry point against a synthetic source file.
Extension 7.8.28 was not executed in this release's test; setup checks it on target.
`Test-WorkspaceGuide.ps1` covers the new guide and unchanged reuse of existing tasks,
checks and guides.

## PowerShell 7 launch command — 2026.11.17.7

The printed launch command uses the detected PowerShell 7, process-local
`-ExecutionPolicy Bypass` and actual registered project paths. Without a project,
it prints a placeholder. The shortcut receives the same policy option; enforced
Group Policy remains. `Test-StartCommand.ps1` covers several projects, the placeholder
and a real child process under restricted execution policy with spaces, apostrophes
and PowerShell-special characters in arguments.

## Quoted smoke-test response — 2026.11.17.6

On the Windows PC, a correct tool call was followed by `"LOCAL_TOOL_OK"` rather than
an unquoted value. Chat/tool-return validation now accepts exactly the expected
text with or without outer double quotes and optional surrounding whitespace.
Extra explanation, wrong values/case and invalid calls remain errors. HTTP regressions
cover both accepted forms and rejection of extra text/wrong tool responses.

## Smoke-test tool choice — 2026.11.17.5

Target LM Studio rejected an object `tool_choice` with HTTP 400 and confirmed the
strings `none`, `auto`, `required`. A subsequent real `required` request returned
`report_value(17)`; `none` produced the expected final response. The smoke test uses
`required` and still checks tool name, unique ID, value 17 and final response.
A local HTTP regression checks the actual JSON request and rejects wrong responses.

## Large model files — 2026.11.17.4

Disk calculations use 64-bit integers for file size, partial progress and the zero
bound. `Test-LargeModelPreflight.ps1` runs real preflight with the 9,001,753,376-byte
Qwen3-14B file, both without and with a simulated 3.5 GB partial download. It prints
the checked numbers without creating or downloading large files.

## Model selection and additive downloads — 2026.11.17.3

The catalogue contains five pinned GGUF variants and required projectors. Repository
revision, size and SHA-256 of all eight files were checked against public Hugging
Face metadata at those revisions. Suggestions use free resources and conservative
file-size heuristics, not measured quality or guaranteed memory fit.

`Test-ModelSelection.ps1` covers role selection/confirmed reruns, changed hardware,
realistic memory figures, opt-out, network failures, partial resume, integrity errors
and existing-file protection, including concurrent destination access and junctions.
`Test-SelectionIntegration.ps1` runs the real setup branch in isolation;
`Test-ModelPool.ps1` covers other-model forwarding and switching without file deletion.
A real HTTPS Range resume was checked with a 1,756-byte public file. This is neither
a long-duration/speed test nor actual LM Studio registration of a new GGUF.

Bootstrap waits for setup without a total deadline. An additional child-held lock
prevents a second run after the starter exits. Audit checks saved selections or
shows nonbinding suggestions without downloading/switching models.

## Optional CPU offload — 2026.11.17.2

`Test-PartialGpuOffload.ps1` covers explicit activation, GPU-strategy order/persistence,
unchanged defaults, context fallback, GPU/RAM reserves, guardrails and matching
estimated/requested GPU options. LM Studio/GPU boundaries are simulated; performance,
CPU offload and real inference remain target-machine checks.

## LM Studio model variants — 2026.11.17.1

CLI commit `43d4b26` reports model IDs as `path` and file paths in variant-list
`indexedModelIdentifier`. Using output supplied by the Windows PC,
`Test-ModelVariants.ps1` checks all three exact files, legacy paths and rejection
of changed/missing/ambiguous variants. Audit checks the same mapping under PS5.1/PS7.
The file/selected variant is checked before and after loading; pending ownership
records preserve variant identity. Boundaries are simulated; these package tests
performed no real inference.

## Manual-action instructions — 2026.11.16.10

Missing models and required LM Studio first-run setup produce structured stdout
instructions rather than red error output. The report stays `INCOMPLETE`, contains
`manualAction`, and exits 1. Real errors still go to stderr. Executable setup harnesses
check separate model/file/source/next-step lines, complete reports, exit codes and
output channels.

## Manual model downloads — 2026.11.16.9

In this release, setup checked all selected local files before router/model actions.
Missing files caused a controlled stop listing only missing exact files and sources,
requiring manual LM Studio downloads and a rerun with the same parameters. Pool/
Single routines were invoked with downloading disabled. `-SkipModelDownload`
remained compatible. Audit listed missing profiles and sources.

`Test-ManualModels.ps1` covers Dual with/without the optional model, partial/complete
availability, Single/`ModelKey`, ambiguity and actual setup termination with an
`INCOMPLETE` report before router/model actions. LM Studio/GPU boundaries are
simulated; no models are downloaded by the test.

## VS Code CLI path — 2026.11.16.8

Windows VS Code 1.146.0's `bin\code.cmd` references a version-dependent subdirectory.
The resolver reads only the expected single invocation, never executes the batch
file, and uses that exact `cli.js` with its associated `Code.exe`. Older unversioned
layouts and installations without a batch file but with the classic CLI path remain
supported; unknown/ambiguous paths are rejected.

Actual `--version` was run against installed VS Code 1.146.0. Tests additionally
cover synthetic old/new layouts, malformed/ambiguous batch files, missing CLI files,
argument forwarding and read-only audit. No extensions were installed or personal
VS Code settings changed. That version's `--locate-extension` returned no path, so
bundled Kilo discovery uses `--list-extensions --show-versions` plus matching manifests
in the isolated directory. Ambiguity and missing binaries are rejected.

## Selection with an existing destination — 2026.11.16.7

The menu recognizes a valid destination identity and recommends option 1 without
claiming completed migration/provisioning. Option 3 checks identities/names before
confirmation; conflicts return to selection rather than merging/overwriting. Copy
also checks before publication, including conflicts arising after the menu.

## Kilo help output — 2026.11.16.6

On the Windows PC, redirected `kilo run --help` exited 0 with empty stdout and full
help on stderr. Setup now reads both while still requiring a successful exit and
all options. `Test-KiloHelp.ps1` covers stdout/stderr/mixed output, missing options,
nonzero exits and installed-CLI reuse without npm. A real child process emits help
on stderr too.

## NTFS copy verification — 2026.11.16.5

A real NTFS hard link reproduced stale directory size/time after writing through
another name while direct access returned current data. Copy verification now
refreshes metadata before inventory and final comparison.

`Test-InstallationLocation.ps1` adds four checks: successful copy despite stale
directory metadata, identical content, rejection of real changes with a concrete
path, and staging cleanup without modifying target files or restoring source data.
Tests use real temporary hard links and deliberately modify the source before the
final comparison.

## CLI compatibility and empty model lists — 2026.11.16.4

Vendor source for CLI commit `43d4b26` confirms hidden `--exact`/`--local` options.
Where needed, compatibility uses the controlled missing-path error, additionally
guarded by `--estimate-only`. Safety options remain in actual load commands.

- `Test-Audit.ps1`: 41 checks each under Windows PowerShell 5.1 and PS7, including
  hidden/missing options, unexpected probe success, counts for zero/one/two models
  and rejection of malformed JSON shapes.
- `Test-LmsCliCompatibility.ps1`: 16 checks for native exit codes, expected errors,
  model lists and unchanged server-status objects.
- `Test-ModelPool.ps1`: 30 checks; successful hidden-option setup and stopping before
  downloads/inference when support is actually missing.

CLI output/GPU/LM Studio are simulated; native child processes, JSON conversion and
file access are real. Rerun updated `-AuditOnly` on target. No real model was loaded.

## Directory selection and copying — 2026.11.16.3

`Test-InstallationLocation.ps1` under PS7/Windows PowerShell 5.1 covers PS1 directory
rather than terminal cwd, selection, confirmation only with `y`, no writing/installing
before confirmation, noninteractive cancellation and prompt-free audit. Copy tests
cover unchanged sources/application settings/model state, rewritten managed paths,
JSON array preservation, locks/active processes, conflicts, links and rollback of
partially published copies. All copies use temporary data.

From the chosen root:

```powershell
pwsh -NoProfile -File ".\app\tests\Test-InstallationLocation.ps1" -BootstrapPath ".\Provision-LoKiEnte.ps1"
powershell -NoProfile -File ".\app\tests\Test-InstallationLocation.ps1" -BootstrapPath ".\Provision-LoKiEnte.ps1"
```

## Manual LM Studio first run — 2026.11.16.2

`Test-LmStudioInitialization.ps1` covers forwarding an existing CLI, missing/empty
resolution and corrupt home configuration. An isolated child executes the real
setup section from CLI checks through error handling: a missing CLI exits 1 with
a saved `INCOMPLETE` report and instructions. App startup, polling and model/router
actions must not execute. No real LM Studio app or installer runs.

## Repair release 2026.11.16.1

These repairs supplement the prior release documented below. Tests used Windows,
PowerShell 7.6.10 and Windows PowerShell 5.1.26100.9818. No applications were installed
and no real models loaded/unloaded. GPU/LM Studio/public HTTP boundaries are simulated;
local HTTP, file access, processes and timeouts really run.

Bundled checks under `app\tests` after extraction:

| Test | Coverage |
|---|---|
| `Test-KiloMetadata.ps1` | String/array/object responses, missing/ambiguous data, prerelease/build versions, stopping before installation writes. |
| `Test-ModelPool.ps1` | Existing 22 pool checks plus 6 recovery checks: load intent, REST failure after loading, mismatched files, reuse and persisted ownership. |
| `Test-RouterLifecycle.ps1` | 17 checks with real Node processes, including HTTP 503 identity, busy-router protection and authenticated shutdown. |
| `Test-Audit.ps1` | Report/aggregation, hardware/model options, missing downloads, state/locks, token redaction, no provisioning calls, real timeouts and HTTP/redirect behavior under PS5.1/PS7. |
| `Test-Bootstrap.ps1` | 35 checks: arguments, extraction, backups, hashes, invalid paths, PS5.1 audit handoff, structured audit errors, timeouts and exit codes. |

From the chosen root after extraction, explicitly reference the updated PS1:

```powershell
pwsh -NoProfile -File ".\app\tests\Test-KiloMetadata.ps1"
pwsh -NoProfile -File ".\app\tests\Test-ModelPool.ps1"
pwsh -NoProfile -File ".\app\tests\Test-RouterLifecycle.ps1"
pwsh -NoProfile -File ".\app\tests\Test-Audit.ps1" -BootstrapPath "C:\Downloads\Provision-LoKiEnte.ps1"
powershell -NoProfile -File ".\app\tests\Test-Audit.ps1" -BootstrapPath "C:\Downloads\Provision-LoKiEnte.ps1"
pwsh -NoProfile -File ".\app\tests\Test-Bootstrap.ps1" -BootstrapPath "C:\Downloads\Provision-LoKiEnte.ps1"
```

These tests do not check target-installed LM Studio/Kilo or its real GPU. Full
installation and initial GUI/agent use remain necessary target acceptance.

## Historical report for the earlier release

The following results/lists belong to the prior release. Its complete test collection
was in the old separate ZIP, not the current repair-test scope listed above.

Recorded 13 November 2026 (UTC), package 2026.11.14.1. Tests ran on Debian Linux with
portable PowerShell 7.6.6 verified against the official SHA-256. Real Kilo checks
used `@kilocode/cli` 7.8.27 in a separate test directory. These test tools are not
part of target-machine installation.

### Result

All checks below passed. This confirms the exercised script logic, configuration
and failure handling, not a full Windows installation or model inference on the
target GPU. Actual provisioning requires chat/tool smoke tests. First GUI use and
a small real project task remain target acceptance steps.

| Check | Scope | Result |
|---|---|---|
| PowerShell syntax | Package parsing with PowerShell 7.6.6 | No syntax errors |
| Bootstrap/PowerShell handoff | 32 cases with real temporary files/processes | Passed |
| Native processes/managed files | 9 named cases | Passed |
| Review gate | 19 cases with real temporary Git repositories | Passed |
| Complete task workflow | 8 scenarios with real processes and synthetic agents | Passed |
| Existing projects/workspaces | 5 preservation/repetition conditions | Passed |
| Real Kilo configuration | Actual parser/effective configuration, 21 declared agents | Passed |
| Real local Kilo API connection | Without token and with test token against local HTTP | Both passed |
| LM Studio control flow | Mocked initial install, memory fallback, reuse/failures | Passed |

### Extension to multiple local models

The multi-model release adds an explicit pool, local HTTP router and role-specific
Kilo models to the previously tested single-model variant. It also had no real GPU run.

| Extension check | Scope | Result |
|---|---|---|
| Pool/ownership register | 22 targeted cases, real PowerShell/file locks, simulated LM/GPU | Passed |
| HTTP/SSE router | 23 cases with real local connections/processes | Passed |
| Router start/reuse | 15 conditions with real Node/HTTP | Passed |
| Multi-model configuration | 22 conditions, including real CLI/full config verification | Passed |
| Role-aware task runner | 2 complete scenarios with different model arguments/context limits | Passed |
| Real Kilo CLI through shipped router | 5 scenarios: coder, reviewer, small chat, GPT-OSS-style reasoning/tool round trip, native subagent delegation | Passed |

The last test uses **actual Kilo CLI 7.8.27 and the shipped router**, backed by a
synthetic LM endpoint and simulated controller. It establishes that coder → review
subagent → coder requests different routes, preserves tool-call data and carries
reasoning through a tool round trip. It does not establish intelligence or GPU behavior.

Qwen metadata uses `reasoning_content`; GPT-OSS uses LM Studio's documented
`reasoning`. Both were checked with real SDK requests and synthetic responses.
Actual target model templates/output formats still need functional verification.

### Covered multi-model failures

The router accepts only provisioned aliases/local endpoints, preserves fragmented
SSE tool arguments and serializes requests until generation ends. Redirects are
rejected. Malformed responses, incomplete streams, wrong controller results and
unknown models fail. Queue/load/generation timeouts and client cancellation are
tested. Ambiguous controller timeout blocks further switches rather than overtaking
a possibly active load.

Lifecycle checks confirm reuse of a matching busy router without a model switch.
Foreign services and busy routers with differing configuration remain. Only a
definitely self-started process that never becomes ready is terminated on failure.

The controller protects foreign/active models, checks ID/path before every owned
unload, limits inference to one slot and shares the tested minimum context. An
ambiguous legacy v1 instance is conservatively not adopted. Additional files are
reused on rerun.

### Additional executable tests

- `tests/Test-ModelPool.ps1`
- `tests/Test-ModelRouter.mjs`
- `tests/Test-RouterLifecycle.ps1`
- `tests/Test-MultiModelConfiguration.ps1`
- `tests/Test-MultiModelRunner.ps1`
- `tests/Test-MultiModelKilo.js` and `Prepare-MultiModelProbe.ps1`

Run the router test from the extracted package with `node tests/Test-ModelRouter.mjs`.
Real Kilo tests require explicit paths to PowerShell and the Kilo test installation;
those test tools are not bundled.

### Bootstrap and error propagation

32 checks established complete ZIP preflight, unchanged reruns, correct backups,
SHA-256 checks, literal arguments and JSON handoff. Path traversal, duplicate targets,
file/directory collisions and reparse links in target/backup directories are rejected.
Inventory with simulated CIM responses created no installation directory.

A real child-process test initially found a lost inner setup exit code. Handoff now
propagates it; tests for 0 and 23 pass. Another test reproduced following an existing
link outside the root; complete preflight now prevents it. Native Windows junctions
and Windows PowerShell 5.1 were not executed in this historical Linux test.

### Processes and existing files

The actual process helper preserves empty arguments, spaces, quotes, Unicode,
newlines and shell-special characters. stderr with exit 0 remains successful.
Nonzero exit fails or is returned unchanged when explicitly allowed. Both streams
are read concurrently; tests used 200 KB on each. Timeout terminates an overlong
process. `.cmd`, `.bat` and `.ps1` are not launched as if native executables.

Changed managed files are backed up. Different existing content is not overwritten
without a backup target. Unchanged reruns neither rewrite nor add backups. Workspace
tests preserve project source, `AGENTS.md`, VS Code settings, custom tasks/check
commands and existing registrations when another project is added.

### Review and validation

A positive control produced `VERIFIED`, exit 0. The gate denied it for missing,
failed or cancelled checks, failed implementation, specialist tool errors, shared
reviewer sessions, stale fingerprints, unresolved findings and `FAIL`/`BLOCKED`.

Parsers reject tool output masquerading as approval, incomplete JSON, plain “PASS”,
an earlier rather than final response, wrong role/fingerprint and invalid session
IDs. Event-stream errors prevent later apparent approval. The validator must name
every executed check.

Fingerprints change for tracked files, Git index and nonignored untracked files.
Tests explicitly cover different index content despite identical worktree/status
output. Ignored files are intentionally excluded and the report states this limit;
`node_modules`, generated files and local environment files are not represented as
reviewed source.

Actual process results:

| Scenario | Status | Exit code |
|---|---|---:|
| Valid separate approvals and passing check | `VERIFIED` | 0 |
| No checks configured | `REVIEWED_UNVALIDATED` | 2 |
| Check failed | `NOT_VERIFIED` | 1 |
| Implementation process failed | `NOT_VERIFIED` | 1 |
| Delegated specialist reports tool error | `NOT_VERIFIED` | 1 |
| Reviewer uses stale fingerprint | `NOT_VERIFIED` | 1 |
| Source changes during verification | `NOT_VERIFIED` | 1 |
| Roles reuse the same session | `NOT_VERIFIED` | 1 |

Agent responses are synthetic; this tests external coordination, not model quality.

### Actual Kilo configuration and authentication

Real Kilo accepted generated configuration. Effective values matched the local
provider, selected model, 32768 context tokens and agent permissions. Full global/
agent permission comparison passed. The generator rejected a nonlocal API endpoint.

A test HTTP server bound only to `127.0.0.1`. Real Kilo called `/v1/chat/completions`
and returned its control response. Without a token, no API-key field was stored.
An obviously synthetic token produced the expected Bearer header; the server would
reject a missing/wrong token. Configuration stored only an environment-variable
reference. Linux could not faithfully test Windows-specific access to variables
set only in the user environment.

Tests use `KILO_TELEMETRY_LEVEL=off` and `experimental.openTelemetry=false`, also
shipped in configuration. This does not guarantee that all installed programs avoid
network activity; package/model downloads and public metadata requests are separate.

Three settings for automatic inline suggestions, their hotkey and chat autocomplete
were checked against the official manifest and set false in the managed profile/
workspaces. The separate autocomplete provider is therefore outside local chat
routing. The real GUI was not run; manual commands/user changes remain possible.

### LM Studio

Runtime contract tests simulate CLI/API responses. They cover empty first install,
one-time runtime/model download, controlled 32K→16K fallback, matching-instance reuse,
public-listener rejection, foreign-model preservation and wrong tool arguments.
No automatic unloading of foreign models was observed.

### Still requiring the actual Windows PC in that release

Windows PowerShell 5.1/ISE, WinGet, installers/UAC, shortcuts, GUI and NVIDIA GPU
had not been run under Windows in this historical test. Bootstrap was checked for
5.1-compatible constructs; parsing with PS7 does not replace execution on PS5.1.

Model quality, actual RAM/VRAM, speed and long-task reliability are not established.
Readiness requires a passing control response, real structured tool call and correct
handling of its return. A later `VERIFIED` receipt covers captured source/configured
checks, not universal correctness.

## Test files

Current executable tests are under `tests/`. Files mentioned in historical sections
may belong to earlier releases. Synthetic servers/agents do not establish real
model behavior on the target PC.

Vendor sources for telemetry and the checked event format:

- https://github.com/Kilo-Org/kilocode/blob/main/packages/kilo-telemetry/src/telemetry.ts
- https://github.com/Kilo-Org/kilocode/blob/main/packages/kilo-telemetry/src/client.ts
- https://kilo.ai/docs/code-with-ai/platforms/cli
- https://github.com/Kilo-Org/kilocode/blob/main/packages/opencode/src/cli/cmd/run.ts

## Repeat checks locally

From the repository root with PowerShell 7, Node and Git:

```powershell
pwsh -NoProfile -File .\Quellpaket\tests\Test-Bootstrap.ps1 -BootstrapPath .\Provision-LoKiEnte.ps1
pwsh -NoProfile -File .\Quellpaket\tests\Test-CoderWorkflow.ps1
pwsh -NoProfile -File .\Quellpaket\tests\Test-ProjectSelection.ps1
pwsh -NoProfile -File .\Quellpaket\tests\Test-WorkspaceGuide.ps1
pwsh -NoProfile -File .\Quellpaket\tests\Test-DependencyUpdates.ps1
pwsh -NoProfile -File .\Quellpaket\tests\Test-RouterLifecycle.ps1
pwsh -NoProfile -File .\Quellpaket\tests\Test-ModelPool.ps1
pwsh -NoProfile -File .\Quellpaket\tests\Test-SingleModelFit.ps1
pwsh -NoProfile -File .\Quellpaket\tests\Test-Embedding.ps1
node .\Quellpaket\tests\Test-ModelRouter.mjs
```

Also run a small real coding request and the semantic-search probe after provisioning.

## Welcome project — package 2026.11.18.19

`Test-WelcomeProject.ps1`: 11 checks passed using real Git and Node. Coverage: clean
initial commit without remote, reproducible calculation bug, automatic Node-JUnit
detection, preservation of modified files/HEAD during updates, fresh examples without
resetting the old one, both registrations, and rejection of an unknown existing
directory. `Test-SelectionIntegration.ps1`: 3 setup integration checks passed.
All 16 public bootstrap parameters were compared with the README table; PowerShell
syntax passed. Users run the real-model trial in Welcome after provisioning.

## Managed VS Code startup and Settings Sync — 2026.11.18.24

The profile migration tests cover new installations, existing personal preferences,
custom terminal profiles, backups, repeated provisioning, malformed input and
preservation of unrelated profiles. New tests verify 29 profile/VSIX assertions
and ten startup scenarios, including missing Kilo, activation failure, an explicit
startup opt-out, disposal during activation and inherited environment in a foreign
profile. Workspace migration tests verify the AI policy on new and existing workspaces.

A local VS Code 1.146.0 integration run installed the generated VSIX through the
real CLI alongside Kilo 7.8.30. Extension-host assertions verified effective AI
visibility configuration, sync exclusions, Kilo activation and the registered
sidebar-focus command; the real helper invoked that command successfully. This
isolated test used no user account, target GPU or model inference. Signed-in cloud
sync and final visual acceptance on the target machine remain separate checks.
The installer never edits the internal sync database or resolves cloud conflicts.
