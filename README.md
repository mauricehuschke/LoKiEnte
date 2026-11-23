# LoKiEnte — local AI development with VS Code, Kilo and LM Studio

[Deutsch](README.de.md)

<p align="center">
  <img src="assets/lokiente-preview.png" width="280" alt="LoKiEnte: a mischievous duck with a green Loki helmet and golden horns">
</p>

<p align="center">
  <a href="https://github.com/mauricehuschke/LoKiEnte/releases/latest/download/Provision-LoKiEnte.ps1"><img src="assets/badge-windows-download.svg" alt="Latest Windows download"></a>
  <a href="#quick-install-latest-release"><img src="assets/badge-provisioning.svg" alt="Provisioning guide"></a>
</p>

LoKiEnte sets up a local AI development environment on Windows: VS Code as your
editor, Kilo for your development requests, and LM Studio for models running on
your machine. Describe a change; separate agents plan, write tests, implement
and review the result.

**The focus is verifiable code quality.** Kilo derives acceptance criteria and
suitable test commands from your request and project. You can follow the workflow
and its results, and decide which changes to commit.

[Install](#quick-install-latest-release) ·
[First test task](#first-test-task) ·
[Update](#update-replace-the-installer-and-provision-again) ·
[Options](#all-provisioning-parameters-and-options) ·
[Help](#frequently-asked-questions)

## Requirements

- **Windows x64** on a PC, workstation or suitable VM. The installer does not
  support Linux or macOS.
- **Enough RAM, VRAM and disk space** for the selected models. Provisioning checks
  available resources and offers suitable profiles. Automatic GPU checks target
  NVIDIA; other GPUs and CPU-only systems are not validated as equivalent configurations.
- **Internet access** for installation and downloads. Models then run locally;
  your project tools may still need network access.
- A regular Windows user account. **Windows PowerShell 5.1 is enough to start**;
  the installer provisions the required tools and PowerShell 7.4 or newer.
- For your own code tasks: a Git repository with at least one commit, installed
  project dependencies and executable tests. The bundled Welcome test project
  lets you try the workflow without preparing your own project first.

Program output and generated agent instructions use English. German guides are
available alongside them as `*.de.md`; there is no runtime language switch.
Output from third-party programs follows their own locale.

## Quick install: latest release

Download the [latest release](https://github.com/mauricehuschke/LoKiEnte/releases/latest)
or its [standalone installer](https://github.com/mauricehuschke/LoKiEnte/releases/latest/download/Provision-LoKiEnte.ps1). The installer embeds the complete source
package; the GitHub source ZIP and a repository clone are not required.

### Download the installer and run it from its folder

1. Download [Provision-LoKiEnte.ps1](https://github.com/mauricehuschke/LoKiEnte/releases/latest/download/Provision-LoKiEnte.ps1)
   and save it in the folder where you want to keep LoKiEnte, for example
   `D:\LoKiEnte`. For an update, use your existing installation folder.
2. Open that folder in File Explorer, type `powershell` in the address bar and
   press Enter. This opens Windows PowerShell in the folder containing the PS1.
3. Copy **one** of the commands below, then review and confirm the installation
   directory and proposed model selection.

Without `-InstallRoot`, the installer uses **the folder containing the PS1** for
its managed environment. The download folder therefore becomes the installation
folder; use a dedicated, permanent directory. Base applications and LM Studio's
model files retain their own locations.

The current filename is `Provision-LoKiEnte.ps1`. If you previously used
`Provision-ShadowLocalAI.ps1`, replace that filename in your command. The new PS1
can update an existing installation in the same folder. If you keep the download
elsewhere, append `-InstallRoot "D:\LoKi"` to the command, replacing `D:\LoKi` with
your actual existing installation path.

#### Recommended starting point: Dual model pool

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Provision-LoKiEnte.ps1 -ModelMode Dual
```

Uses the role-based coding/review model pool and local router. Hardware checks
guide model selection; partial CPU/RAM offload is not enabled for a fresh setup.
`Dual` is also the default when the option is omitted. It does not mean that two
models perform inference simultaneously.

#### Dual pool with an additional Fast model

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Provision-LoKiEnte.ps1 -ModelMode Dual -IncludeFastModel
```

Also offers a small model for the optional read-oriented Fast role. This is
separate from the regular Coder Fast profile and needs additional model storage.
The name does not guarantee a measured speed improvement.

#### Dual pool with Fast model and partial GPU offload

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Provision-LoKiEnte.ps1 -ModelMode Dual -IncludeFastModel -AllowPartialGpuOffload
```

This is the combination used with the previous installer filename. It also allows
part of a model to run on CPU/RAM when full GPU offload does not fit. Consider it
when VRAM is limited but sufficient system RAM is available. Larger models may
become usable, but responses can be much slower; hardware checks still apply.

#### Simpler alternative: one coding model

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Provision-LoKiEnte.ps1 -ModelMode Single
```

Uses one coding model instead of the role-based model pool. Choose this for a
simpler model setup; it currently has no semantic indexing. Do not combine it
with `-IncludeFastModel` or `-AllowPartialGpuOffload`.

These combinations describe fresh setups. Updates retain unspecified saved model
options; explicitly changing `ModelMode` resets inherited model options. For
normal installation, leave `-AllowUnfitAttempt` off: it permits loading attempts
without proven memory reserves and is not a quality setting. See
[all options](#all-provisioning-parameters-and-options) for details.

For an automated download with checksum verification, use the following section.

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

### PowerShell (recommended, with checksum verification)

Open Windows PowerShell in a writable download directory and paste the entire
block. It resolves the latest published release once, downloads both files from
that same version, overwrites any files with the same names in the current
directory, verifies SHA-256, and starts provisioning. Change `InstallRoot` if needed.

```powershell
& {
    $ErrorActionPreference = 'Stop'
    $installRoot = "$env:LOCALAPPDATA\LoKiEnte"
    $release = Invoke-RestMethod 'https://api.github.com/repos/mauricehuschke/LoKiEnte/releases/latest'
    $base = "https://github.com/mauricehuschke/LoKiEnte/releases/download/$($release.tag_name)"
    Invoke-WebRequest "$base/Provision-LoKiEnte.ps1" -OutFile .\Provision-LoKiEnte.ps1 -UseBasicParsing
    Invoke-WebRequest "$base/Provision-LoKiEnte.ps1.sha256" -OutFile .\Provision-LoKiEnte.ps1.sha256 -UseBasicParsing
    $expected = ((Get-Content .\Provision-LoKiEnte.ps1.sha256 -Raw).Trim() -split '\s+')[0]
    if ($expected -notmatch '^[a-fA-F0-9]{64}$' -or (Get-FileHash .\Provision-LoKiEnte.ps1 -Algorithm SHA256).Hash -ne $expected) {
        throw 'Installer checksum verification failed. Do not run this download.'
    }
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Provision-LoKiEnte.ps1 -InstallRoot $installRoot
}
```

### Command Prompt (CMD, using Windows curl)

```bat
curl.exe --fail --location --output Provision-LoKiEnte.ps1 "https://github.com/mauricehuschke/LoKiEnte/releases/latest/download/Provision-LoKiEnte.ps1" && powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Provision-LoKiEnte.ps1 -InstallRoot "%LOCALAPPDATA%\LoKiEnte"
```

### GNU wget (if installed, run from CMD)

```bat
wget.exe -O Provision-LoKiEnte.ps1 "https://github.com/mauricehuschke/LoKiEnte/releases/latest/download/Provision-LoKiEnte.ps1" && powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Provision-LoKiEnte.ps1 -InstallRoot "%LOCALAPPDATA%\LoKiEnte"
```

Use `wget.exe` for GNU wget: `wget` in Windows PowerShell 5.1 is an alias for
`Invoke-WebRequest`, with different options. The CMD alternatives start only after
a successful download; use the recommended PowerShell block for checksum verification.
The checksum detects a damaged or mismatched download; it is not a digital signature.

Confirm the displayed installation directory with `y`, review the proposed model
profiles, and complete any requested LM Studio first-run setup. Run the same
command again if setup asks you to finish a first launch. Read the final report,
then launch the **LoKiEnte** desktop shortcut and select the Welcome test project.
`PROVISIONED_WITH_WARNINGS` means some features still need verification.

## First test task

1. After provisioning, launch the **LoKiEnte** desktop shortcut.
2. Select `welcome\workflow-test`. This is a separate example inside the
   installation directory; it does not require one of your applications.
3. Open its README, copy the included test request and paste it into Kilo's
   **`shadow-chat`** mode.
4. Follow preparation, test authoring, implementation and independent reviews
   in Kilo's tool cards or `LOKI-STATUS.md`.
5. Baseline tests must expose the deliberate discount calculation bug; final
   tests must pass. Inspect the Git diff and the report with status `VERIFIED`.

The [complete test request](Quellpaket/welcome-example/README.md) uses only
synthetic data. Updates preserve your changes to the example. For a fresh attempt,
run this in PowerShell 7; adjust the installation directory if you chose another:

```powershell
$installRoot = "$env:LOCALAPPDATA\LoKiEnte"
& "$installRoot\app\New-WelcomeTestProject.ps1" -InstallRoot $installRoot -NewExample
```

The example avoids changing your applications. It is not an OS sandbox: agents
and tests run under your Windows account.

## Everyday use

Open the desktop shortcut. Select a known project or another existing directory
in the PowerShell menu. LoKiEnte prepares local model access and opens the managed
VS Code workspace. For a new project, first create its directory and scaffold,
initialize Git and make an initial commit. Then select it. No additional Git worktree is created.

Choose `shadow-chat` in Kilo and describe the requested change, boundaries and
expected behavior. Kilo starts the reviewed workflow. Preparation derives criteria,
change types, exact file boundaries and suitable local tests. An independent
reviewer checks the proposal before checks.json is backed up and extended.
No manual JSON maintenance is needed for each task. Unclear requirements or a
missing test environment produce a specific clarification request.

Kilo status shows phase, agent role, assigned model and outcome. The task directory
also contains `LOKI-STATUS.md`. Ask “Show the details” or “Cancel the task” to request
a report or cancellation. Roles run as separate external CLI sessions; status is
not a native Kilo task tree. task.md and VS Code tasks remain optional alternatives
with the same automatic preparation.

The [complete user guide](Quellpaket/WORKFLOW.md) explains permissions, reports
and workflows. It is installed as `app\WORKFLOW.md` and as `LOKI-WORKFLOW.md` in each
registered task directory; German companion files have `.de.md` suffixes.

## Copilot, Kilo startup and Settings Sync

The desktop launcher opens Kilo automatically in the managed LoKiEnte window.
Built-in VS Code AI/Copilot features are hidden there. Your normal personal VS Code
environment is unchanged; the generated LoKiEnte workspaces carry the same AI policy.
After an update, fully close all LoKiEnte windows before using the desktop shortcut.

The bundled **LoKiEnte Managed Startup** extension opens Kilo once per window
startup. It runs only with the launcher's environment and matching isolated profile.
It does not submit prompts or run a task. To retain your restored layout instead,
set `lokiente.startup.openKilo` to `false` in the managed user settings. You can
still use **LoKiEnte: Open Kilo** from the Command Palette. If Kilo cannot open,
read the warning and the **LoKiEnte Startup** output channel.

**Recommended: sync extensions only and keep settings local.** This imports your
usual extensions without merging editor preferences from another environment.
Provisioning does not sign you in or silently change the account's sync categories.

1. Cancel an unfinished initial settings merge, if one is open.
2. Run **LoKiEnte: Configure Extension Sync** from the Command Palette. The updated
   startup helper also offers a one-time hint. It opens VS Code's own sync checklist.
3. Select **Extensions only** and deselect **every other category**, including
   **Settings**, **UI State** and **Profiles**. Apply the selection. When enabling
   Backup and Sync for the first time, use the same selection in its setup dialog.
4. Sign in yourself if needed. Existing local themes, formatter settings and terminal
   profiles stay local; your cloud settings are not replaced.

The helper cannot read or apply those category choices through VS Code's public
extension API. Opening the dialog does **not** mean the selection has been applied.
An existing settings conflict is resolved by excluding Settings from sync, not by
accepting an entire local or remote file. Reprovisioning alone cannot make that choice.

Managed settings and extension exclusions remain as additional protection if you
later choose to sync settings too. Kilo, the startup helper and both Copilot
extensions are excluded from extension sync; Kilo is updated by provisioning.
Personal settings and custom exclusions are preserved and changed settings backed
up under `backups/vscode-settings`. A later decision to sync personal settings can
still produce genuine conflicts. VS Code synchronizes its exclusion lists themselves;
they cannot be reliably isolated by adding them to their own ignore list.

### If local indexing fails to initialize

After updating, close all LoKiEnte windows and reopen the desktop launcher. In Dual
mode, Automatic provisioning/startup and an accepted OnDemand launch test the same
local embedding route and 768-dimensional
request used by Kilo. The router handles LM Studio versions that reject the optional
`dimensions` field, while validating the actual returned vectors. No cloud fallback
or automatic project-indexing consent is added.

`Disabled` or `OnDemand` with `SmokeTest: NotRun` is intentional while indexing
is off or waiting for a launch choice. Failed readiness also leaves indexing
disabled in Kilo for that launch; fix the cause and restart to retry.

If Kilo still reports **Failed to initialize**, check `runtime/embedding-status.json`
inside the installation folder for the last preflight result and the local router
endpoint. `runtime/router-events.jsonl` records sanitized error codes for subsequent
requests. Check LM Studio for model readiness or HTTP errors. A passed preflight
is not a completed project index: enable indexing for the intended project and wait
for **Complete**. Single mode still does not provision semantic indexing.

`Deferred` with `SmokeTest: NotRun` means the embedding model was not ready for an
API test. `result.MemoryCheck` distinguishes an actual RAM shortage from a low-
confidence estimate and LM Studio guardrail denial. For the verified CPU embedding
model, `LOW` or missing guardrail text uses a conservative load budget: at least
1 GiB, or four times the larger of the estimate and model file size. An additional
3 GiB must remain available. LM Studio still controls the actual load; explicit
denial blocks it. Readiness requires successful inference. If available RAM falls
below the reserve after a conservative load or inference check, only that newly
loaded, verified idle embedding instance is unloaded. Busy or ambiguous instances
are preserved and reported. No `-AllowUnfitAttempt` is needed for this path.

## How code verification works

1. Preparation and independent preparation review establish the verifiable task.
2. An architecture agent plans against your requirements.
3. A test author edits only approved test files.
4. An independent agent reviews those tests before execution.
5. The runner executes baseline tests; bugfixes must be concretely reproduced.
6. The implementer edits approved production files. Tests are locked for this phase.
7. Checks, code review and separate validation assess the result.
8. Security changes additionally require security review; UI/API changes require
   integration checks and a dedicated reviewer.

Acceptance criteria have fixed IDs and must be covered by actual reported test
cases. Exit code 0 without test evidence is insufficient. VERIFIED means the
conditions passed for that source state. Still inspect the diff and actual
behavior. Commit and push yourself. Models and tests do not guarantee correctness.

## Update: replace the installer and provision again

Stop active LoKiEnte tasks and close its VS Code windows. Re-run the PowerShell
block above from the directory containing your downloaded installer: it fetches
the latest release and **overwrites `Provision-LoKiEnte.ps1` and its checksum**.
Set `$installRoot` to the **exact existing installation directory** before running
it. For example, replace its assignment with:

```powershell
$installRoot = 'D:\LoKi'
```

For the default installation, keep `$env:LOCALAPPDATA\LoKiEnte`. The download
directory and installation directory do not have to be the same. Downloading alone
does not update an installation; running provisioning again does.

For example, this CMD command replaces the downloaded installer and updates an
existing installation at `D:\LoKi` (use the PowerShell block for checksum verification):

```bat
curl.exe --fail --location --output Provision-LoKiEnte.ps1 "https://github.com/mauricehuschke/LoKiEnte/releases/latest/download/Provision-LoKiEnte.ps1" && powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Provision-LoKiEnte.ps1 -InstallRoot "D:\LoKi"
```

No uninstall or `-UpdateManaged` switch is required. Provisioning updates managed
configuration, approved tool versions and reachable registered projects. Personal
project files, custom test commands and saved model options are preserved unless
explicitly overridden. Changing `ModelMode` explicitly resets inherited model options.
It does not independently upgrade the libraries of your application projects.
See [all parameters](#all-provisioning-parameters-and-options) and the
[complete user guide](Quellpaket/WORKFLOW.md) for details.

The latest link always follows the latest published release. A new commit on
`main` alone is not an installer update.

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

On Windows, `curl --version` reports the upstream version (for example, `8.23.0`). WinGet also tracks a package revision (for example, `8.23.0.9`). LoKiEnte checks the executable in the installed package. If verification fails, the error includes the detected version and executable path.

These rules apply to LoKiEnte provisioning. Applications' own updaters are separate. Integration-specific ripgrep and LanceDB, model files and project libraries follow their existing management paths.

## All provisioning parameters and options

These are the public parameters of `Provision-LoKiEnte.ps1`. Switches default to
off for a fresh installation. During updates, saved model options take precedence
over defaults when the parameter was not supplied explicitly.

| Parameter | Default / allowed values | Effect |
|---|---|---|
| `-InstallRoot` | Directory of the launched PS1; nonempty | Installation root. Use the same directory for updates. Base programs and LM Studio models retain their own storage locations. |
| `-AuditOnly` | Switch | Inspect prerequisites without installing package files or loading models. Existing CLI tools may initialize caches/services; public metadata is queried online. |
| `-ModelMode` | `Dual`; `Dual`, `Single` | Dual uses a role-based model pool and local router; it does not mean two coding models are loaded simultaneously. Single uses one coding model, currently without semantic indexing. |
| `-IndexingMode` | `Off`; `Off`, `OnDemand`, `Automatic` | Indexing start policy. If omitted, a Dual-mode menu defaults to Off, including updates. Only Off is supported in Single mode. |
| `-IncludeFastModel` | Switch | Offer an additional small Fast model in the Dual pool; valid only with Dual. Distinct from the regular Coder Fast profile. |
| `-AllowPartialGpuOffload` | Switch | Allow partial CPU/RAM offload in the pool. May enable larger models but can be much slower. |
| `-AllowUnfitAttempt` | Switch | Attempt loading without proven memory reserve. May cause load failures/OOM; LM Studio safeguards remain active. Not required for updates. |
| `-RouterPort` | `1235`; 1024–65535 | Local router port in Dual mode. Must differ from the LM Studio port. |
| `-PreferredModel` | `Auto`; `Auto`, `Qwen27B`, `GptOss20B` | Preferred model selection. Auto uses hardware and saved selection; the actual choice is confirmed. Explicit GptOss20B requires Single. |
| `-ModelKey` | Unset; string | Unique local modelKey or full model path from `lms ls --json`; Single only. Model must already exist. |
| `-ApiTokenEnvironmentVariable` | `LOKIENTE_LM_API_KEY` | Name of the environment variable containing the local API token, not the token itself. Never put secrets in parameters or project files. |
| `-ContextLength` | `32768`; 8192–65536 | Requested token context. Resource checks may select a smaller usable context. Larger contexts need more memory. |
| `-Port` | `1234`; 1024–65535 | Local LM Studio API port. |
| `-ProjectPath` | Empty string array | Register/update additional existing directories. Reachable registered projects update even without this parameter. Welcome test project is added automatically. |
| `-SkipModelDownload` | Switch | Do not download missing models; setup stops if required files are absent. Does not prevent other tool downloads/updates. |
| `-ModelAction` | `Keep`, `Configure` | Select model maintenance for this run. Enter keeps a matching existing installation. |
| `-UpdatePolicy` | `frozen` (default), `latest`, `lts` | Saved for this installation. All targets must be at least 48 hours old. |
| `-UpdateManaged` | Switch | Compatibility with older commands; currently no additional effect. Normal runs already update managed files/workspaces. |
| `-NoShortcut` | Switch | Do not create/refresh the desktop shortcut in this run. Does not delete an existing shortcut. |

Saved model options that can be retained: ModelMode, IncludeFastModel,
AllowPartialGpuOffload, AllowUnfitAttempt, RouterPort, PreferredModel, ModelKey,
ApiTokenEnvironmentVariable, ContextLength and Port. ProjectPath, AuditOnly,
SkipModelDownload, UpdateManaged and NoShortcut are not inherited as model options.
Dependency upgrades follow the saved `UpdatePolicy`.

For multiple project paths, invoke directly from PowerShell to preserve the array:

```powershell
& .\Provision-LoKiEnte.ps1 -InstallRoot 'D:\LoKi' -ProjectPath @('D:\Projects\AppA', 'D:\Projects\AppB')
```

If execution policy is restricted, first open a new shell with
`powershell.exe -NoProfile -ExecutionPolicy Bypass`. PowerShell 7 can explicitly
disable saved switches, for example `-IncludeFastModel:$false` in a direct call.
CmdletBinding also adds common parameters: Verbose, Debug, ErrorAction,
WarningAction, InformationAction, ErrorVariable, WarningVariable,
InformationVariable, OutVariable, OutBuffer and PipelineVariable (plus
ProgressAction in PowerShell 7). These do not change model options.
WhatIf/Confirm are not supported; the `y` prompt authorizes provisioning.

## Frequently asked questions

**Why does a write task still not start after an update?**
Legacy checks.json files receive structural additions; the new task is prepared
automatically. Custom checks remain. Old exit-code-only tests need an independently
reviewed structured replacement. Missing tools or manually modified managed fields
produce NEEDS_INPUT. The original state is retained in a backup.

**Why does LoKiEnte report an external Kilo tool?**
Kilo can load custom JavaScript/TypeScript tools from its user profile even with
external plugins disabled. LoKiEnte checks imports and stops on conflicts. The
message identifies the file; back it up and move it out of the specified tool
directory yourself if needed. LoKiEnte does not delete or overwrite these tools.

**Which tests are detected?**
Node tests and locally installed Vitest, Jest and Playwright runners are offered
with suitable report adapters. Python/pytest and TypeScript typechecks are also
supported. Preparation installs no missing dependencies. Configure a custom check
once for other toolchains. A successful typecheck alone does not replace behavioral tests.

**Can I edit the same project while a task runs?**
Avoid this. LoKiEnte locks parallel workflows and verifies source state. Editor or
other process changes may invalidate evidence; they are not rolled back automatically.

**Why was VERIFIED not issued?**
The terminal prints the receipt.json path. It records missing cases, invalid
reports, failed checks or unresolved findings. Changing tests requires a new run
with another test review.

**What does WORKER_UNRESPONSIVE mean?**
Automatic polling stops after 30 seconds without worker startup or 120 seconds
without a heartbeat. The task may still run; its project lock stays. Inspect job
logs and processes before recovery. Do not blindly delete the lock or start another task.

**Is semantic code search immediately ready?**
Indexing defaults to Off. Provision OnDemand or Automatic in Dual mode, start
indexing through the launcher, then enable it once per project in Kilo and wait
for Complete. Verify it using the [search probe](Quellpaket/VALIDATION.md).

**Are test processes isolated?**
They receive sanitized environment variables and separate temporary/profile paths
but run under your Windows account and can access files and networks. Use approved
commands and local test data without production credentials.

## More documentation

- [Complete user guide and workflows](Quellpaket/WORKFLOW.md)
- [Welcome test request](Quellpaket/welcome-example/README.md)
- [Report a bug or suggest an improvement](https://github.com/mauricehuschke/LoKiEnte/issues)
- [Customize or contribute to LoKiEnte itself](docs/development/README.md)

## Optional Windows security profile

Choose the **LoKiEnte duck → Run E.T. model rule test** in the VS Code Activity
Bar, then select the local model. Run it on your regular Windows machine using
your existing installation, without elevation or a VM. It checks one allowed
read, a protected file, an out-of-workspace file and a web request. **Output →
LoKiEnte Security** reports model behaviour, Kilo permissions and observed GPU
activity separately. **Test a custom Kilo rule** also accepts your own question
and expected answer. [How to read the results](SECURITY.md#local-et-model-test).

**Kilo rules and workflows** opens Kilo Settings. Use **Agent Behaviour → Rules**
for prompt instructions. LoKiEnte registers its managed `LOCAL-AI-RULES.md`
there. Keep personal project instructions in `AGENTS.md`. Under **Workflows**
the shipped commands delegate to `shadow-chat`; they inherit the local model
selection. “Use server default” requires no manual model selection.

## License

[Apache License 2.0 with Commons Clause 1.0](LICENSE.txt) permits cloning,
forking, modification, free redistribution and commercial internal use under
its terms. The Commons Clause restricts selling products or services whose
value derives entirely or substantially from LoKiEnte's functionality; this
can also cover hosting and consulting/support. The two texts apply together.

**Projects and work products developed with LoKiEnte may be used commercially
and sold.** Using LoKiEnte does not put those independent results under its
license. LoKiEnte code actually incorporated into a product retains its license
conditions; third-party materials retain their respective licenses.

This combined license is **source available, not OSI open source**. Read the
[full terms](LICENSE.txt) or the [German explanatory notes](LICENSE.de.txt).
