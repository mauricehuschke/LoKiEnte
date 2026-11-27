# LoKiEnte — provisioning and verified agent workflows

[Deutsch](README.de.md)

Version: 2026.11.27.3 · Target: Windows x64 (PC, workstation or suitable VM) · Default language: English

## Desktop projects and provisioning diagnostics

The desktop shortcut starts a Windows GUI-subsystem launcher. PowerShell runs
without a console; project selection uses a dialog. It retains registered projects
and offers **Browse folder**, **Find Git projects**, **Clone repository** and
**Repair path**. Git discovery has explicit depth/directory limits and skips links
and generated dependency directories. Cloning accepts HTTPS/SSH repository URLs
without embedded credentials, or a local repository, and requires a new destination
directory. Existing destinations are preserved. Git's credential manager/SSH agent
handles authentication. A failed partial clone is retained for inspection.

**Repair path** reconnects a registered project to its new folder. The original
LoKiEnte task/checks files, custom workspace settings and registration identity are
retained; old paths in the managed workspace are updated. Index/workspace backups
are made before writes. Missing entries stay listed until repaired. Reopening or
reprovisioning a repaired project continues using its retained metadata.

Startup is confirmed only by a launch-specific handshake from the expected
LoKiEnte helper in the managed VS Code profile. A CLI installation list alone does
not establish a running extension. Kilo discovery waits for registration and
Workspace Trust before activation. Installed-but-unavailable, missing and activation
failures have separate diagnostics. The helper version is 0.3.1; fully close old
managed VS Code windows after updating from 0.2.6. No SQLite enablement state is edited.

**Output → LoKiEnte** receives launcher/editor console logs as well as the managed
toolchain logs. The native collector does not leave a terminal open. If normal
startup fails, the launcher attempts a diagnostics-only VS Code window; when VS Code
itself cannot open, a native error dialog points to `runtime/launcher-logs`.

`provisioning-report.json` schema 2 is written before the first setup operation and
updated incrementally. It includes bootstrap/version/package evidence, environment
and hardware inventory, parameters, timed actions/tests, native command arguments,
exit codes, stdout/stderr, exception locations/stacks, installed extension manifests,
configuration/state snapshots and this run's local logs. Completed partial acceptance
evidence survives a later launch failure. Prior reports are backed up. Very large
streams/logs are explicitly marked truncated and link to their full local log;
credentials are redacted. The report includes local paths and may contain private
configuration/task diagnostics: inspect it before sharing.

Provisioning acceptance uses native Windows applications and a synthetic local Git
clone. **Docker and Hyper-V are not required or started.** The optional offline-VM
feature is separate and is never an acceptance prerequisite. A skipped, blocked or
failed case is never presented as a passed test.

## Verify the installed toolchain

Provisioning now asks **Run the real VS Code/Kilo/LM Studio acceptance? [Y/n]**.
Enter runs it; `n` skips it. Use `-RunAcceptanceTest` to run without this question,
or `-SkipAcceptanceTest` to skip explicitly. These switches are mutually exclusive
and are not retained for the next update. A skipped test means **unverified**.

The test opens a separate VS Code test window. Trust its synthetic workspace when
asked, and confirm the completed response in the actual Kilo chat at the end.
It checks installed dependencies, both Kilo runtimes, tool imports/search and a
real file-read/model-response round trip for every configured model. Dual mode
also correlates a real webview request through the router to LM Studio. Enabled
indexing adds actual embedding inference and LanceDB write/search checks.
Full repository indexing remains a separate workload.

Open **Output → LoKiEnte** for component-tagged successes, failures and connection
state changes. The channel combines available managed VS Code/Kilo logs, router
events, model-controller logs and LM Studio server logs. Credentials are redacted;
prompt/response JSON and debug/trace payloads are excluded. It cannot recover
messages that a third-party process never logs. A reachable API alone is not an
inference PASS.

Results are local: `diagnostics/toolchain/latest.json` and `latest.junit.xml`, plus
a separate directory for each run. `PASS` requires all mandatory checks, including
the manual visual observation; `FAIL`, `BLOCKED` and `SKIPPED` never count as PASS.
Run again from the LoKiEnte sidebar (**Run toolchain acceptance**) or PowerShell 7:

```powershell
pwsh -NoProfile -File D:\LoKi\app\Test-Toolchain.ps1 -InstallRoot D:\LoKi
```


Use **Run E.T. model rule test** in the LoKiEnte sidebar to test a selected local model in your normal Windows session. It uses Kilo instructions and checks Kilo tool permissions. The optional Hyper-V check is separate.

The main editor shows a live **E.T. security report**. Select a case to compare expectations, prompts, the request payload and the observed result. Reopen it with **Show latest E.T. report** in the same window.

After the run, **Export JSON** saves the detailed evidence to a local file of your choice, including prompts and local paths. The network reference checks https://www.lokiente.dev/fit-test.txt for **Success**.

Every provisioning run registers the bundled example at `welcome/workflow-test`.
The [example guide](welcome-example/README.md) contains a ready-to-use Kilo test
request. Updates preserve existing example code; `New-WelcomeTestProject.ps1
-NewExample` creates a fresh attempt.

This package sets up LM Studio, a pool of local models, Kilo CLI and a dedicated
VS Code environment. Coding and review use separate roles by default; an additional
small-model role is optional. Each role can use a selected model, including the
same model for several roles. Predefined agents and reusable workflows cover
features, bug fixes, refactoring, review and architecture. Existing software is
detected and reused where suitable. Setup does not change existing repository files.

LoKiEnte opens a new window with isolated data and extensions. Its VS Code command
also passes `--disable-extension` for `GitHub.copilot` and `GitHub.copilot-chat`.
This affects only that window, preserving personal profiles and existing windows.
Previously registered projects receive these options on their next LoKiEnte launch.

Documentation is available in English and German as adjacent `.md` / `.de.md`
files. Provisioning, menus, errors and workflow status use English. Generated
agent instructions default to English; there is no runtime language switch.
Technical identifiers and saved installation paths remain compatible with updates.

### Managed VS Code and synchronization

Provisioning sets `chat.disableAIFeatures=true` in the isolated user profile and
new/existing managed workspaces. It installs the local `lokiente.managed-startup`
VSIX helper, which opens Kilo's own view once per launcher window without starting
a task. It checks the launcher marker and profile path; personal VS Code windows
are unaffected. Set `lokiente.startup.openKilo=false` to keep your restored layout.
The Command Palette still offers **LoKiEnte: Open Kilo**.

`settingsSync.ignoredSettings` and `settingsSync.ignoredExtensions` are merged with
custom exclusions. Managed terminal, telemetry, update, Kilo autocomplete and AI
visibility settings stay local. Kilo, both Copilot extensions and the startup
helper do not sync their state. Personal editor settings are preserved; changed
settings are backed up. Conflicting explicit sync opt-ins are removed.

Sync remains optional. The recommended choice is **Extensions only**; leave all
other categories, including Settings, UI State and Profiles, unchecked. Use
**LoKiEnte: Configure Extension Sync** to open the official VS Code checklist.
The startup helper shows this guidance once after installation/update. You must
apply the checklist selection yourself; the public extension API cannot set or
verify these choices. Cancel an unfinished initial settings merge before doing so.
Local preferences and cloud settings are not replaced. Reprovisioning alone does
not resolve personal conflicts if Settings remains selected. The exclusion lists
also sync when settings sync is enabled; they cannot exclude themselves.
After updates, fully close all LoKiEnte windows and restart.

### Optional indexing: Off, OnDemand or Automatic

Indexing is **Off by default for every project**, including existing installations.
In Dual mode, provisioning asks for a start mode unless you pass `-IndexingMode`.
Press Enter for Off. Every provisioning run defaults to Off; a previously saved
Automatic choice is not silently inherited. The selected mode is saved for later
desktop-launcher starts.

| Option | Provisioning | Desktop launcher |
| --- | --- | --- |
| `Off` (default) | Disables indexing; no indexing dependency or embedding download/load. | Starts without indexing for all projects, including previously enabled ones. |
| `OnDemand` | Prepares LanceDB and the embedding model download; does not load the embedding model. | Asks whether to start indexing for this launch; Enter means No. |
| `Automatic` | Prepares dependencies and checks the embedding service. | Starts the embedding service automatically; Kilo indexes projects with existing consent. |

Use your usual coding-model options and add one of these flags:

```powershell
# Default: keep memory available for coding and review
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Provision-LoKiEnte.ps1 -ModelMode Dual -IncludeFastModel -AllowPartialGpuOffload -IndexingMode Off

# Prepare indexing, ask at each desktop launch
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Provision-LoKiEnte.ps1 -ModelMode Dual -IncludeFastModel -AllowPartialGpuOffload -IndexingMode OnDemand

# Start indexing automatically for projects you have enabled in Kilo
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Provision-LoKiEnte.ps1 -ModelMode Dual -IncludeFastModel -AllowPartialGpuOffload -IndexingMode Automatic
```

After changing modes, fully close all LoKiEnte VS Code windows and reopen the
desktop launcher. This is a setting for the shared LoKiEnte profile; a running
window does not receive another launch's environment. For OnDemand, close the
previous session before making a different choice. Kilo still requires one-time
project consent under **Settings > Indexing**. Existing consent is preserved;
Off overrides it. Automatic cannot grant that consent on your behalf. Wait for
**Complete** before relying on semantic search.

To skip the OnDemand question for one launch, run the installed launcher in
PowerShell 7 with `-StartIndexing` (replace the installation/project paths):

```powershell
pwsh -NoProfile -File D:\LocalAI\app\Start-LocalAI.ps1 -InstallRoot D:\LocalAI -ProjectPath D:\Projects\Example -StartIndexing
```

This switch cannot enable an Off installation: provision OnDemand or Automatic
first. Single model mode supports Off only. Off preserves downloaded models and
stored indexes. Switching to Off/OnDemand, or declining an OnDemand launch, unloads
only LoKiEnte's verified idle embedding instance; busy or ambiguous instances stop
the operation with an explanation. Close the previous session and retry.
File search, subagents, reviews and tests remain available without indexing.

### Local semantic indexing

Kilo and the embedding preflight use the local router's `/v1/embeddings` route.
It accepts only the managed model and 768 dimensions, omits that optional request
field before forwarding to LM Studio, and verifies count, indices and finite,
nonzero 768-dimensional response vectors. It does not truncate or resize vectors.
Authentication and loopback boundaries remain active. CPU embedding requests are
bounded and can proceed during coding requests; shutdown waits until work ends.
`runtime/embedding-status.json` preserves the last preflight result without tokens
or request text; later failures produce sanitized router event codes.

The CPU embedding preflight records `MemoryCheck` with the estimate, available RAM,
load budget, guardrail result and measured RAM after conservative load/inference.
For LOW confidence or absent guardrail text, the budget is the maximum of 1 GiB,
four times estimated memory and four times the verified model file size, plus
the unchanged 3 GiB reserve. Explicit LM Studio denial still blocks loading.
Actual CLI rejection remains Deferred; readiness requires the vector smoke test.
A breached reserve rolls back only the newly loaded, uniquely owned idle embedding
instance. Coding models and pre-existing embeddings are not unloaded by this check.
This policy does not alter coding/review model fit or GPU offload rules.

Dual mode with OnDemand or Automatic provisions LanceDB 0.26.2 and local
`nomic-embed-text-v1.5.Q4_K_M.gguf`. The model file is checked against its size and
SHA-256, downloaded if needed and stored without overwriting an existing file.
The embedding model runs with `--gpu off` alongside the active coding model; its
RAM requirement is estimated. Automatic setup/startup and accepted OnDemand
launches perform a real local embedding request producing two vectors. Computation and vector storage remain
local, with no cloud fallback.

If memory fit cannot be established, the model remains unverified by default.
Only `-AllowUnfitAttempt` permits an attempt without the package's memory reserves;
LM Studio's guardrails remain active. Failure to load or pass the embedding test
leaves the installation usable with a warning, but indexing is not ready. The next
LoKiEnte launch that requests indexing retries it. Corrupt model files, ambiguous ownership and authentication
errors remain explicit failures. Single mode does not currently provision indexing.

This integration was checked with Kilo VS Code extensions 7.8.28 and 7.8.30.
Version 7.8.30 is bundled as the frozen target. An already newer
version is checked for the required interfaces and settings during provisioning.
The separately installed Kilo CLI has its own version number.

Close all LoKiEnte windows, reopen the project, then open **Settings > Indexing**
in Kilo and enable indexing for that project after choosing OnDemand or Automatic. Kilo manages this permission per
project; the package does not edit its internal VS Code database. Only **Complete**
status and a successful semantic search establish that project indexing is ready.
Successful provisioning alone does not establish this.

Kilo observes `.gitignore` and `.kilocodeignore`; tool read permissions are not a
general index filter. Explicitly exclude sensitive files and credentials before
enabling indexing. The local index and its code excerpts are not automatically
encrypted. The installed Kilo version's OpenAI-compatible embedding request does
not distinguish the search/document prefixes recommended by Nomic. Optimal search
quality is therefore not guaranteed; file search and targeted reading remain useful.

After enabling indexing, run the search probe in [VALIDATION.md](VALIDATION.md). It uses
a small synthetic directory and checks an expected match plus exclusions through
both ignore files.

### Verified development

The [user guide](WORKFLOW.md) explains the first task and provides a complete
`checks.json` example. Key behavior:

- Enter requests directly in Kilo `shadow-chat`. `loki_start` starts the controlled
  workflow; `loki_status`, `loki_details` and `loki_cancel` expose progress, agent
  roles, requested role models, results and cancellation.
- `shadow-preparer` derives criteria, change types, exact files and suitable local
  test candidates. `shadow-preparation-reviewer` checks them independently before
  `checks.json` is backed up and updated. No JSON editing is required for each prompt.
- `writePaths` authorizes production files; `testWritePaths` authorizes tests only.
- A separate test author and independent test review precede implementation.
  Reviewed tests remain frozen during implementation.
- Fixed `acceptanceCriteria` IDs map to actual cases from newly generated JUnit/JSON
  reports. Process exit codes alone are insufficient.
- `changeTypes` requires additional checks: `security` requires security review;
  `ui`/`api` require integration tests and integration review. Planning, reviewers
  and path hints may expand this classification.
- Provisioning also updates registered projects. Existing commands remain;
  task-specific fields are renewed with provenance and hashes. Old exit-code-only
  checks need a reviewed structured replacement. Manual edits to automatic fields
  and missing prerequisites produce a specific `NEEDS_INPUT` conflict.

All roles run sequentially in the existing checkout. Test processes run under your
Windows account; their filtered environment is not an OS sandbox. Diff review,
functional acceptance, commit and push remain your responsibility.

### Build the installer from source

On the development machine, update the version above and run
`python .\Build-LoKiEnte.py 2026.11.23.3` from the repository root. The script
rebuilds the embedded payload and checksum. The target Windows PC still needs
only the generated PS1. A separate old ZIP is unnecessary for this process. The
provisioning report records the version and checksum of the installer actually used.

**Validation boundary:** executable parser, behavior and failure tests validate
the package. They do not establish a real installation on the target GPU machine.
Provisioning checks actual hardware, effective CLI configuration and, where loading
succeeds, real chat/tool responses. Untested models are explicitly marked and yield
`PROVISIONED_WITH_WARNINGS`, rather than a claim of complete model readiness.

## 1. Getting started

Download the current `Provision-LoKiEnte.ps1` to the Windows PC. This single file
contains the complete package, documentation and regression tests. An older separate
ZIP is not updated by this process and must not be treated as the same release.

Open **Windows PowerShell 64-bit** in the download directory using your normal
Windows account. An installer may display a Windows UAC prompt when needed.

### Read-only preflight

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Provision-LoKiEnte.ps1 -AuditOnly
```

The single PS1 supports this audit in Windows PowerShell 5.1 without first
installing PowerShell 7. It validates the embedded payload and runs the audit in
memory. It does not extract the package into an installation directory, install
software, start the local API, perform inference, or load/unload models.

The default installation root is the directory containing the PS1, not the shell's
working directory. Audit mode does not ask for a location or accept `y` as a location
choice. A legacy installation under `%LOCALAPPDATA%\ShadowLocalAI` is reported only
as a hint; specify its path explicitly to audit it. CLI operations may create their
own caches or background effects; the package does not promise otherwise. Public
package/model metadata requests need Internet access. API secrets are sent only to
the checked loopback endpoint, without following redirects.

The audit checks compatibility of `lms load --exact --local --estimate-only --yes`
without supplying a model. Only the expected missing-local-path error establishes
support; an unknown-option error does not. It performs no real estimate or load.
Empty `lms ls` / `lms ps` JSON arrays mean zero models in both PowerShell 5.1 and 7;
invalid JSON is an error rather than an empty result.

The audit covers:

- OS, CPU, RAM/VRAM and tool versions, npm metadata and required Kilo/LM Studio flags.
- VS Code's active CLI entry resolved from `bin/code.cmd`, without executing that
  batch file; curl and ripgrep availability.
- Parameters, project paths, installation identity and provisioning lock.
- Actual drives and hardware; saved runtime state and model instance ownership.
- Loopback listeners, REST authentication and router state.
- Exact model files and public npm/Hugging Face metadata. The model drive may
  differ from the installation drive; custom npm registries are not audited.

Audit JSON uses schema 2 with `checks`, `summary`, `status` and `exitCode`. Individual
checks report `PASS`, `WARN`, `FAIL`, `MISSING` or `SKIP`; failures are isolated so
other checks can finish, with bounded process timeouts.

| Result | Exit code | Meaning |
|---|---:|---|
| `BLOCKED` | 2 | An evidenced blocker was found. |
| `ATTENTION_REQUIRED` | 0 | Installable missing components or warnings remain. |
| `PRECHECK_PASSED` | 0 | No gaps were reported by these checks; this is not a completed installation. |

`inferenceVerified` is always false in audit mode. To retain the report:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Provision-LoKiEnte.ps1 -AuditOnly > .\LoKiEnte-Audit.json
```

### Provision or update

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Provision-LoKiEnte.ps1
```

`ExecutionPolicy Bypass` applies to this process only. It does not change global
policy or override Group Policy. The default root is the PS1 directory. An explicit
root is also supported:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Provision-LoKiEnte.ps1 -InstallRoot D:\LocalAI
```

If an old installation is found at another location, the menu offers:

1. Use the selected destination.
2. Reuse the previous directory.
3. Copy the previous installation to the destination.

A valid installation identity does not prove that setup finished. Copying performs
preflight checks and returns to the menu on destination conflicts; it never merges
installations. Use option 1 for the correct existing destination. Enter the exact
location choice; a blanket `y` or noninteractive invocation cannot bypass it.

The root contains the managed application, private Kilo tooling and profile. Base
applications may remain in their existing global locations; some caches remain
outside the root. LM Studio's configured model directory is not changed.

Before copying, close managed windows, routers and tasks. Active processes/locks,
links and conflicting destinations stop the copy. The copy comparison refreshes
file metadata before comparing size/time so NTFS hard-link cache behavior does not
cause a false result. Source changes abort with size/time diagnostics. There is no
overwrite or merge. Unrelated files beside the PS1 remain untouched; conflicting
`app`, `runtime` or `tooling` content without a valid identity is rejected.

Staging requires space for the full copy. Only managed absolute paths in toolchain,
Kilo and workspace configuration are rewritten; arbitrary application settings,
ownership records and history are not rewritten. The original remains as a backup.
Do not run both copies at once. The copied report stays `INCOMPLETE` until setup
reaches `PROVISIONED` or `PROVISIONED_WITH_WARNINGS`.

Setup creates a desktop shortcut unless `-NoShortcut` is supplied. To register
an existing project during provisioning:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Provision-LoKiEnte.ps1 -InstallRoot D:\LocalAI -ProjectPath C:\Dev\MyProject
```

### Models and first-run requirements

Model selection supports grouped LM Studio IDs from `lms ls --variants --json`.
The selected variant must match its exact file path. Loading uses the exact local
ID/path and is verified before actions and after loading. Ambiguity stops the run;
retain the selected variant rather than silently substituting another quantization.

Choose `coder-high`, `coder-fast`, `review` and optionally `fast`. Recommendations
use currently free RAM/VRAM, file size, reserves and load estimates. They are not
benchmarks or guarantees of speed/quality. Confirm each role; the last selection
becomes the next run's default while hardware is measured again.

Missing model files are downloaded over HTTPS from pinned Hugging Face revisions
with SHA-256 verification. curl displays progress and retries/resumes after 30
seconds, without a total transfer deadline; Ctrl+C stops the attempt and retains
partial files. A hash mismatch stops rather than adopting the suspect file. Verified
downloads remain under `model-downloads` in the installation root. A second verified,
atomic copy goes to LM Studio's configured model directory without overwriting;
setup waits for LM Studio discovery. If both locations share a drive, allow space
for both copies; preflight accounts for this. `-SkipModelDownload` stops with manual
instructions when files are missing. A custom `-ModelKey` must be unambiguous.

If the LM Studio CLI is unavailable, setup reports `MANUAL ACTION REQUIRED`, exits
with code 1 and records `INCOMPLETE`. It does not automatically open the application,
wait for dialogs or resume. Completed steps remain. Open the displayed LM Studio
path, finish first-run setup/repair the CLI, then open a new terminal and rerun the
same command without `-AuditOnly`. No interruption occurs if the CLI is already
usable; setup does not approve application dialogs for you.

### Optional partial GPU offload

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Provision-LoKiEnte.ps1 -InstallRoot D:\LocalAI -IncludeFastModel -AllowPartialGpuOffload
```

With partial offload enabled, setup tries `max`, `0.8` and `0.6` GPU offload at the
requested context and smaller 16384/8192 fallbacks where applicable. It chooses the
first fit with a 1 GiB GPU reserve and 3 GiB RAM reserve over the estimated RAM
requirement. LM Studio's guardrails still apply. Without a fit, the model is deferred
unless `-AllowUnfitAttempt` explicitly allows an attempt outside those reserves;
this can still fail, hang or run out of memory. The shared context is the smallest
verified limit. Real smoke tests remain required. The option is saved, but later
runs estimate available resources again. Rejected models remain downloaded and
unverified. CPU offload may be slower; without the flag, only full offload is tried.

`-IncludeFastModel` adds the optional small read-oriented role. It does not establish
measured speed. Dual remains the coding/review pool mode; it does not mean parallel
model inference.

An optional single-model setup is available:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Provision-LoKiEnte.ps1 -InstallRoot D:\LocalAI -ModelMode Single
```

### Open a project

Use the desktop shortcut, or run:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File D:\LocalAI\app\Start-LocalAI.ps1 -InstallRoot D:\LocalAI
```

The menu lists known projects by number. `N` selects another existing directory;
create a new directory first if needed. `0` cancels before model startup. Quoted
paths and spaces are supported. Unreachable registrations remain listed; invalid
input can be retried. `-ProjectPath` bypasses the menu.

Registration preserves existing checks and does not initialize Git in your project.
Only the bundled Welcome example creates its own repository. An empty directory
can be opened, but write workflows require a Git root, an initial commit and valid
checks. The shortcut uses `-PauseOnError`; direct invocations pause only when that
flag is supplied. It starts PowerShell 7 with process-local policy bypass, subject
to Group Policy.

## 2. What is installed and configured

| Component | Behavior |
|---|---|
| PowerShell | Install/reuse version 7.4 or newer; retain Windows PowerShell 5.1. |
| Git, Node LTS, VS Code | Detect suitable existing installations; install missing components. |
| curl | Verify a usable local executable. |
| ripgrep | Provision version 15.1.0 from the official archive with checksum validation in the isolated cache; test CLI and extension use. |
| LM Studio | Reuse installation, authentication and configured model storage. |
| GGUF/GPU runtime | Reuse an appropriate runtime or install a compatible CUDA runtime; no GPU-driver changes. |
| Models | Select/download role models; explicitly warn about deferred verification. |
| Router | Serialize model requests and manage only owned model instances. |
| Kilo CLI | Preserve global configuration; use the private managed configuration and tooling. |
| VS Code Kilo extension | Install the approved prerelease extension into the dedicated extension directory. |
| Agents | Configure local roles, permissions, context/step limits and compaction models. |
| Workspaces | Keep generated workspace/task definitions outside existing repositories. |

This is not a universal installer for every language server or build system.
An existing ripgrep with an unknown checksum is preserved and reported as a
conflict. Official HTTPS downloads plus archive hashes do not constitute a separate
cryptographic publisher signature.

VS Code's active `cli.js` is resolved from `bin/code.cmd`, including old and newer
versioned layouts, without executing an unknown batch file. An unknown layout
stops. Extension detection uses `--list-extensions --show-versions` and the manifest;
it does not use `--locate-extension`, which VS Code 1.146.0 does not support.

Kilo help is checked using stdout, stderr and exit code. Kilo uses its platform binary without npm lifecycle hooks. Personal VS Code, Codex, Copilot
and Kilo configurations remain untouched: the managed profile has its own data,
extensions and Kilo sessions, and does not overwrite global Kilo configuration.

Kilo's inline/chat autocomplete uses a separate provider path. Three related
settings are disabled in the managed profile/workspaces, with backups and unrelated
settings preserved. This package does not configure local FIM completion. Manual
commands remain available and users can re-enable settings; this is not network
isolation. Setup does not change GPU drivers, firewall rules, WSL, Docker, logins
or project secrets, and does not trigger a reboot.

## 3. Models, memory and switching

Selection uses actual RAM/VRAM and LM Studio state, without a hosting-vendor tie.
Typical role suggestions include:

| Role | Model | Approximate file size | Intended use |
|---|---|---:|---|
| `coder-high` | Qwen3-14B Q4_K_M | 9.0 GB | Demanding chat, planning, architecture and implementation. |
| `coder-fast` | Qwen3.5-9B Q4_K_M | 5.63 GB plus projector | Lighter chat, research and implementation. |
| `review` | gpt-oss-20b MXFP4 | 12.1 GB | Separate review perspective. |
| Optional `fast` | Qwen3.5-9B Q4_K_M | 5.63 GB plus projector | Read-only chat/research. |

These are decimal file sizes, not VRAM requirements. Context and projectors require
additional memory; the large weights together exceed 20 GB. Model files remain
available on disk while GPU-loaded coding models switch sequentially. The default
router is `127.0.0.1:1235`, with LM Studio at `127.0.0.1:1234`.

Visible model names use `CODER HIGH`, `CODER FAST`, `REVIEW` and optional `FAST`.
The `lmstudio/*` and `shadow-router` aliases resolve only to controlled local
instance IDs, not arbitrary remote model names. Before each request, the controller
checks actual state. It unloads only an owned matching ID/file while idle; foreign
or busy instances remain protected. An inference slot is held through the end of
a streamed response, with a bounded queue. It is released after a tool request so
a native Kilo subagent can use another role model.

The requested default context is 32768, with controlled fallback to 16384 where
needed. The smallest verified pool limit is shared. Estimated/unverified fit does
not prove successful inference; compaction must fit every configured model. Model
parallelism is 1. Deferred models are visibly marked `[NOT YET VERIFIED]`. Dual
mode can retry verification on a request; failure returns an explicit error rather
than switching to cloud or another model. After freeing resources, retry without
reprovisioning. Single-mode fit failure stops unless `-AllowUnfitAttempt` permits
the deferred attempt. Labels regenerate at launch and can remain stale until the
next launch after a successful retry.

To select the review model for Single mode:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Provision-LoKiEnte.ps1 -InstallRoot D:\LocalAI -ModelMode Single -PreferredModel GptOss20B
```

An already available custom model can use `-ModelKey` with `-SkipModelDownload`.
The key must identify exactly one local model.

The role mapping is not a benchmark proving that GPT-OSS is universally superior
at review. A different family can offer another perspective; a fresh Qwen validator
does not guarantee independent errors. Switching incurs loading/cache costs while
persistent Kilo chats remain available. Related implementation roles use the same
coder. The optional small role is not selected for every task; fewer parameters
do not prove better throughput. Measure on your hardware and actual tasks.
GUI helpers/compaction use the main model; strict-runner helpers use the active
phase model to avoid an unnecessary switch for titles or summaries.

## 4. Agents and reusable workflows

| Agent | Responsibility |
|---|---|
| `shadow-chat` | Primary chat using Coder High; starts and follows reviewed tasks. |
| `shadow-chat-fast` | Lighter chat using Coder Fast. |
| `shadow-plan` | Requirements, scope and plan. |
| `shadow-preparer` | Derive criteria, categories, files and local test candidates. |
| `shadow-preparation-reviewer` | Independently review the proposed task policy. |
| `shadow-explorer` | Read-only project research. |
| `shadow-architect` | Architecture proposals and constraints. |
| `shadow-frontend` | Bounded frontend implementation. |
| `shadow-backend` | Bounded backend implementation. |
| `shadow-test` | Author tests before implementation. |
| `shadow-test-reviewer` | Independently review tests and criterion mapping. |
| `shadow-integration` | Integration evidence for UI/API changes. |
| `shadow-security` | Security review for security-related changes. |
| `shadow-implementer` | Bounded production changes. |
| `shadow-reviewer` | Independent code review. |
| `shadow-validator` | Independent validation of actual evidence. |

The optional `fast` chat/explorer roles remain read-only and cannot approve work.
Ordinary Feature, Bugfix and Refactor tasks use Coder High. Additional VS Code tasks
marked `(Coder Fast)` use Coder Fast for implementation/frontend/backend roles.
Planning, separate review, validation and explicitly configured checks remain
mandatory. Selecting a model in free chat does not change the separate task runner's
model choice.

Previous `coder` selections become suggestions for `coder-high` on the next setup;
the old `fast` selection may seed `coder-fast`. Existing models and the embedding
index remain. After updating, close all LoKiEnte windows and open a new Kilo session:
old sessions may retain the removed `coder` alias. Built-in selectable Kilo agents
are disabled in the managed profile; internal helpers such as compaction remain.

The sidebar provides `/feature`, `/bugfix`, `/refactor`, `/review` and `/architecture`.
They pass the requested workflow to `shadow-chat`. Natural-language requests also
work without a slash command.

**The mandatory workflow starts from Kilo through the local `loki_start` tool.**
Chat itself receives no general file-write or shell permissions. The tool binds
the request to the registered project and invokes the fixed runner with
`-AutoPrepare -Workflow Auto`. Preparation and independent review must pass before
the test author and implementer receive bounded write permissions. Subagents cannot
start new LoKiEnte tasks. VS Code tasks remain an alternative for `task.md`, also
with `-AutoPrepare`. Custom task definitions survive updates.

### Workflow stages

Every automatic workflow starts with preparation → independent preparation review.
The subsequent quality stages are:

- **Feature:** criteria/plan → test author → test review → baseline tests →
  implementation → checks → review → required specialists → validation.
- **Bugfix:** criteria/cause → test author → test review → a specifically failing
  regression → fix → passing regression → review → required specialists → validation.
- **Refactor:** behavior invariants → test author → test review → passing baseline
  tests → refactoring → checks → review → required specialists → validation.
- **Review:** inspect the current working tree without implementation → checks →
  review → validation.
- **Architecture:** proposal without code changes → review against the codebase →
  validate existing evidence. Without relevant executable checks, no `VERIFIED`.

Findings allow at most **one correction round** by default. Checks and both reviewers
then run again. `-MaxCorrectionRounds` accepts 0–3 to bound agent loops. Every stage
also has step/time limits. Oversized requests or review packages are rejected rather
than silently dropping important evidence.

Roles and model mappings are declared in `app\AgentTemplates.ps1`, which generates
`kilo-managed\kilo.json`. Persistent changes belong in the template because setup
and launcher regenerate managed files. Previous versions are backed up; a package
update also backs up and replaces the template. Maintain additional roles/process
variants deliberately in your own versioned customization and test them against
the existing gates. This is not a general visual workflow engine.

The supplied rules and `shadow-chat` prompt now default to English. German rule
documentation is retained as `.de.md`; only the English rules are selected in the
active agent configuration. Generated `kilo-managed\LOCAL-AI-RULES.md` and the
configuration are renewed from source templates at launch.

## 5. Running a task

See [WORKFLOW.md](WORKFLOW.md) for preparation, complete schema 2, supported test
reports, VS Code tasks and failure handling. Provisioning updates each registered
project's managed `LOKI-WORKFLOW.md` and `LOKI-WORKFLOW.de.md`. New personal guides
are `GUIDE.md` and `GUIDE.de.md`; existing personal guides, including `ANLEITUNG.md`,
remain untouched. File-based task templates are provided as `task.md` / `task.de.md`;
existing user tasks are not translated or overwritten.

`TaskPreparation.ps1` collects a bounded file inventory, manifests and locally
available runners. It does not read `.env` files or execute project commands for
detection. Model proposals select candidate IDs only. `Run-ProjectCheck.mjs` runs
fixed Node/Vitest/Jest/Playwright/TypeScript templates without a shell or package
download. Python/pytest uses the local interpreter with JUnit. Missing project
dependencies are not installed. Unknown build systems may use existing manual
checks with structured reports. `limits.allowedWritePaths` and
`limits.allowedTestWritePaths` provide persistent additional boundaries.

The first automatic run archives old task-specific values under
`automation.importedTaskFields` and discloses them to preparation review. Custom
commands and unknown fields remain. Hashes prevent silent replacement of manually
edited automatic criteria/checks. Backup and publication occur only after PASS and
fresh verification of source state, inputs and the previous `checks.json`.

## 6. What VERIFIED means

A current source fingerprint, successful actual checks, complete mapping of fixed
criteria to passing cases, independent test review, code review and validation,
plus any required security/integration judgments are mandatory. Test files remain
locked during implementation; hash/scope checks detect changes before later checks.

A test report is evidence produced by executed project code. It does not establish
the authenticity of every assertion or functional completeness. Test review, code
review, validation and your acceptance remain necessary. Ignored files and external
state are outside the source fingerprint. `VERIFIED` applies only to the captured
revision; unresolved mandatory findings prevent it even when every process exits 0.

## 7. Chats, context and logs

The dedicated Kilo environment stores sessions under `runtime-profile`. Reopen them
through Kilo's session history for that managed profile. Personal Kilo/Copilot chats
are not automatically imported.

Automatic compaction uses the actual loaded context limit. Summaries are lossy:
long history on disk does not put every old message into the active model context.
Keep durable requirements in project instructions, SSOT and testable criteria.

Strict workflows start fresh sessions per stage. `runs\<timestamp-id>` retains the
request, plan, responses, check commands, outputs, session IDs, requested role models
and receipt. These records support inspection and subsequent work; they do not
simulate an unlimited shared context.

Kilo follows a background task through `loki_status`, showing actual phases, agent
roles, requested role models, states and tool activity. `loki_details` provides a
bounded report; `LOKI-STATUS.md` in the task directory mirrors the latest published
state. Controlled phases are external CLI sessions, not automatically native Kilo
task-child sessions or an Inspector graph. Native read-only chat subagents may
additionally have their own Kilo sessions.

Interrupting a status request does not stop the background task. Explicit cancellation
uses `loki_cancel`; only `CANCELLED` confirms termination of the owned process tree.
Existing changes remain. Only one controlled task per project may run at a time.
`NEEDS_INPUT` states missing prerequisites or conflicts instead of implying approval.

`WORKER_UNRESPONSIVE` stops automatic polling after 30 seconds without worker startup
or 120 seconds without a heartbeat. It confirms neither termination nor success;
the project lock remains. Inspect job logs and local processes rather than blindly
deleting the lock. `loki_status` may check again later and `loki_cancel` can still
record cancellation. Targeted recovery requires confirmed process termination or
a system restart.

## 8. Local processing and existing credentials

The model server and router bind to loopback. An existing publicly bound server
is not silently reconfigured; setup stops with an explanation. Main, helper,
subagent, memory and compaction models are constrained to the local provider and
selected catalogue. Unverified models are explicitly marked. Effective configuration,
including possible managed policy, is checked before CLI work; deviations fail.

Kilo telemetry is disabled for launched processes, as is VS Code telemetry in the
managed profile. OnDemand and Automatic in Dual mode prepare the local embedding service described above;
project indexing still requires Kilo's per-project enablement. Single mode leaves
indexing disabled. Agents can also use file search and targeted reading. Setup
requires Internet access for software and model downloads. “Local” means inference
on the Windows machine where LoKiEnte is installed; on a hosted VM this is the
hosting provider's infrastructure. The package is not network isolation and cannot
guarantee that every third-party application avoids update or metadata requests.

If your existing LM Studio server requires authentication, provide the token in
the process before starting setup or the launcher:

```powershell
$env:LOKIENTE_LM_API_KEY = 'YOUR_EXISTING_TOKEN'
# Updates retain the saved variable name unless explicitly changed.
```

Configuration and reports store only the environment variable name, not the LM
Studio API token. The router receives it through its process environment. For its
own controlled shutdown, the package also generates a random local control token
in `runtime\router-control.json`; this is not a model-provider credential. A desktop
shortcut does not inherit a variable set only in another terminal. In that case,
start the launcher from the same terminal. Existing authentication is not disabled.

## 9. Lovable and other projects

Connect the desired Lovable project to its GitHub repository and clone it to the
Windows PC, or use an existing clone. Authentication, organization, repository URL
and branch remain your project data. Register the local directory with the launcher.

A local clone may still access the same Supabase/cloud backend as the published
application. A Git branch does not create a separate database. The package therefore
does not migrate, deploy, merge or push project changes. Review changes through your
normal Git process before bringing them into the Lovable-synchronized branch.

Other Git projects are supported too. Their language runtimes, package-manager
versions and checks must match the project; the package does not claim to completely
configure unknown Python, Java, .NET or native build systems automatically.

## 10. Repeated runs, updates and common stops

Finish active AI tasks before updating. A normal rerun reuses suitable applications,
downloaded models and managed files. It checks every selected model again and stops
an owned router only when it has no active/queued work. Identical files are not
rewritten. Changed managed configuration is backed up. User tasks and project check
files are not reinitialized after their first creation.

Provisioning is also the update procedure. Use the same `-InstallRoot` and first
close that environment's VS Code windows and active tasks. Saved model configuration
provides defaults; explicit parameters take precedence.

All reachable registered projects are updated. `-ProjectPath` adds more directories.
Managed VS Code tasks and bilingual `LOKI-WORKFLOW` guides are refreshed. Missing
fields are added to old `checks.json` files after backing up the originals. Existing
commands, write authorizations, requests and custom workspace tasks remain. Managed
tasks receive `-AutoPrepare` and an additional `Workflow Auto` entry. Each request's
write scope is derived and independently reviewed, not installed as an unlimited
persistent permission. Unreachable directories remain in the index and report.

### Choose how development tools update

Set `-UpdatePolicy` once on the normal provisioning command. For example, run this from the installer folder for an existing installation at `D:\LoKi`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Provision-LoKiEnte.ps1 -InstallRoot "D:\LoKi" -UpdatePolicy lts
```

| Policy | Target on installation and every subsequent provisioning run |
| --- | --- |
| `frozen` (default) | The exact tool targets bundled with this LoKiEnte release. An already newer working installation is retained. |
| `latest` | The highest eligible numeric release available through each supported package source. |
| `lts` | The highest eligible release in a supported LTS line for Node.js and PowerShell. Other tools follow `latest`. |

**Model maintenance for this run.** For an existing installation with matching model options, provisioning offers two choices. Press Enter or `1` to keep your Single or Dual configuration and indexing mode. Tools, agents and projects update. LoKiEnte skips model selection, downloads, changes to loaded instances and inference tests. Choose `2` to select or update models from the bundled catalog and test them again. Verified model files are reused. First-time setup and changed model parameters require configuration.

Append `-ModelAction Keep` or `-ModelAction Configure` to your usual command to choose explicitly for one run. In a newly opened LoKiEnte terminal, run `npm --version` to see the active npm. When needed, LoKiEnte installs its own Node-compatible npm under `tooling/npm-versions`. The same 48-hour rule applies. Kilo uses its Windows binary package. Its private installation disables npm lifecycle scripts and verifies the CLI afterwards.

The policy covers **VS Code, Kilo for VS Code (Windows x64), Kilo CLI, LM Studio, PowerShell 7, Git, Node.js, npm and curl**. Each target must be **at least 48 hours old**. WinGet targets must have the same manifest tree in the current catalog and a catalog revision at least 48 hours old. Kilo uses npm publication times and Marketplace build timestamps. If a new version is too young, the resolver selects the next eligible version. Missing catalog evidence or an unavailable exact package stops the run with an error.

The confirmed provisioning run records the choice in `update-policy.json` in the installation directory, including for retries. Omit the option to reuse it. Specify another value to switch. The provisioning report records the policy and target versions. Existing newer tools are kept, including when switching back to LTS or frozen. Old installations with custom `dependency-versions.json` pins that differ from the bundled targets require a one-time explicit policy choice to migrate.

These rules apply to LoKiEnte provisioning. Applications' own updaters are separate. Integration-specific ripgrep and LanceDB, model files and project libraries follow their existing management paths.

The installer manages LoKiEnte tooling. Project repository manifests and lockfiles
remain the project's responsibility. npm metadata accepts a single version string,
a one-element array or a version object; a missing `engines` field is valid.
Ambiguous/empty responses are rejected before installation, with StrictMode active.
The installed manifest must match the requested version.

Before a pool load, the package records a pending load intent. If verification then
fails, a rerun can recognize an exact local instance by ID and model file. This
establishes ownership only: idle state, actual configuration and relevant setup
smoke tests are still checked. Foreign models or different files are not adopted.
An interruption of an **older version without a recorded load intent** cannot gain
this evidence retroactively; you may need to deliberately unload that instance once
in LM Studio.

A known unready router returning HTTP 503 can be restarted once it reports no
active/queued work and the control evidence matches. Foreign or unauthenticated
services are not stopped. Extraction uses an exclusive provisioning lock. The lock
file's existence alone does not mean a run is active; the OS lock is released when
the process ends.

Failure reports include script name, line and error ID. After a process timeout,
downstream installers/services may still be running; inspect their state before
retrying. Manual edits to installed application files are backed up and replaced
by the embedded package on the next bootstrap. Use the updated standalone PS1,
not just a locally patched extracted file.

### A model loads in LM Studio but not in Kilo

Status/catalog queries and memory estimates have a 60-second deadline. A real
model load retains its 15-minute deadline. Both limits also cover output pipes
held open by child processes after the CLI exits. An uncertain load timeout
blocks further model switches until LM Studio is checked and LoKiEnte restarted.
Router health exposes the current alias and Loading/Generating phase, and its
latest error code; the event log records model-switch starts and readiness.

LoKiEnte uses a managed instance with its own context, GPU offload and single
inference slot. A successful manual load does not verify this configuration.
The installation directory is configurable; no particular drive or folder name
is required. Start the managed VS Code window through the LoKiEnte shortcut and
select one of its `[CODER HIGH]`, `[CODER FAST]` or `[REVIEW]` models.

Model-switch errors now distinguish memory refusal, unsupported architecture,
other load failures, a manually loaded external model, a busy instance, a public
server listener and denied API access. A failed model stays downloaded and
explicitly unverified. A later request retries the same profile and must pass
the chat and tool checks before it becomes verified again. Existing runtime
selections are preserved; a failed request does not download or switch runtimes.

After updating, close the managed VS Code windows, relaunch LoKiEnte and reproduce
the failure once. The latest controller failure is recorded locally at
`runtime/model-switch-failure.json`, with its time, alias, cause and script
location. Native command output remains in `runtime/pool-logs`. The HTTP response
contains fixed recovery instructions rather than private exception details.
The failure report can contain local paths; inspect it before sharing it.

For an existing installation, update the standalone installer and run it with
your usual installation path. `-ModelAction Keep` installs the updated scripts
while retaining the saved models and options. Check the new Kilo error and the
local report before changing model or memory settings.

| Message/condition | Next step |
|---|---|
| WinGet missing | Install/update Microsoft App Installer, then retry. |
| `lms.exe` missing | Open LM Studio and complete first-run setup; use the official CLI setup if needed. |
| Unsuitable existing Node/PowerShell/LM Studio | Update or repair that installation deliberately; it is not blindly replaced. |
| Foreign model loaded | Finish active work, deliberately unload it in LM Studio and retry. |
| No memory fit | Close GPU/RAM-heavy processes, use 16K context or a smaller profile. |
| Public listener or occupied port | Inspect the service; explicitly configure loopback or choose a free `-Port`. |
| No valid tool call | Inspect loading/template/runtime settings; do not force a success result. |
| Effective Kilo configuration differs | Check compatibility/managed policy; it is not bypassed. |
| `NOT_VERIFIED` | Read `receipt.json` and the concrete agent/check output, resolve findings and rerun. |
| `NEEDS_INPUT` | Resolve the specific question/prerequisite from `loki_details`, then restart the amended request. |

After configuration changes, close all managed-profile windows and reopen through
the launcher. After switching from Single mode, start a new Kilo session or explicitly
select the new local model in an old session: manual selections may persist per
session. Otherwise VS Code may reuse a running process and its old environment.
The first real GUI use must confirm that local models and roles reach the installed
extension. Setup and launcher check both the standalone CLI and the extension's
embedded CLI, but this does not replace visible GUI testing for future versions.

## 11. Installation layout and backup

- `app`: readable scripts, templates and documentation.
- `inventory.json`, `toolchain.json`, `provisioning-report.json`: detected state,
  selected tools and provisioning result.
- `runtime\model-pool.json`: verified models, context limits and endpoints.
- `runtime\model-ownership.json`: package-controlled model instance ownership.
- `runtime\router-events.jsonl`: router events without prompt, response or API-token content.
- `runtime\runtime-state.json`: optional Single-mode state.
- `kilo-managed`: generated roles, rules and slash commands.
- `runtime-profile`: managed Kilo configuration, cache and sessions.
- `vscode-data`, `vscode-extensions`: separate VS Code data and extensions.
- `projects`, `workspaces`, `workspaces.json`: requests, checks and external workspaces.
- `runs`: inspectable evidence for each task run.
- `workflow-jobs`: background Kilo jobs, events, status and cancellation signals.
- `projects\<project-id>\LOKI-STATUS.md`: visible progress of the latest published task.
- `backups`: prior versions of changed managed files.

Back up requirements, tasks, customized templates, sessions and receipts using
your normal backup process. The package does not automatically delete them. It has
no blanket uninstaller that removes shared tools or your models.

## 12. Primary references and validation limits

Implementation was checked against vendor documentation and CLI sources:

- [LM Studio CLI](https://lmstudio.ai/docs/cli)
- [Local load options](https://github.com/lmstudio-ai/lms/blob/main/src/subcommands/load.ts)
- [LM Studio REST model status](https://lmstudio.ai/docs/developer/rest/list)
- [Qwen model](https://lmstudio.ai/models/qwen/qwen3.8-27b)
- [Review model](https://huggingface.co/openai/gpt-oss-20b)
- [Optional small model](https://huggingface.co/Qwen/Qwen3.5-9B)
- [Model TTL/auto-evict](https://lmstudio.ai/docs/developer/core/ttl-and-auto-evict)
- [Exact unload](https://lmstudio.ai/docs/developer/rest/unload)
- [Exact GGUF files](https://huggingface.co/lmstudio-community/Qwen3.8-27B-GGUF/tree/main)
- [Kilo installation and extension channel](https://kilo.ai/docs/getting-started/installing)
- [Kilo CLI](https://kilo.ai/docs/code-with-ai/platforms/cli-reference)
- [Subagents](https://kilo.ai/docs/customize/custom-subagents)
- [Role permissions](https://kilo.ai/docs/customize/agent-permissions)
- [Reusable commands](https://kilo.ai/docs/customize/workflows)
- [Compaction](https://kilo.ai/docs/customize/context/context-condensing)
- [Role/helper models](https://kilo.ai/docs/code-with-ai/agents/model-selection)
- [Separate autocomplete path](https://kilo.ai/docs/code-with-ai/features/autocomplete)
- [Extension settings](https://github.com/Kilo-Org/kilocode/blob/main/packages/kilo-vscode/package.json)
- [VS Code CLI](https://code.visualstudio.com/docs/configure/command-line)
- [WinGet installation](https://learn.microsoft.com/en-us/windows/package-manager/winget/install)
- [Lovable Git sync](https://docs.lovable.dev/integrations/git-sync-overview)

Bundled tests use PowerShell 7 and real temporary processes/Git repositories while
simulating model responses and Windows/GPU boundaries. They test control behavior,
not model intelligence. [VALIDATION.md](VALIDATION.md) records executed checks and
their limits. Final Windows/GPU/VS Code acceptance happens on your target machine.
