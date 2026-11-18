# LoKiEnte — local AI development with VS Code, Kilo and LM Studio

[Deutsch](README.de.md)

<p align="center">
  <img src="assets/lokiente-preview.png" width="280" alt="LoKiEnte: a mischievous duck with a green Loki helmet and golden horns">
</p>

LoKiEnte sets up a local development environment on Windows. Work in VS Code,
use Kilo for analysis and development, and run models through LM Studio on your
own machine. The package targets Windows x64 PCs, workstations and suitable VMs
and checks the resources actually available. Automatic GPU checks currently
target NVIDIA; other GPU vendors and CPU-only systems are not validated as
equivalent configurations. The provisioner does not support Linux or macOS.

**The focus is verifiable code quality:** separate agents write tests, implement
a bounded change, then review the code and results. Models run locally.
Installation and downloads require internet access; project tools may make
network requests independently.

Package version: **2026.11.18.23**. English is the default for documentation,
provisioning, menus, diagnostics and generated agent instructions. German
documents are available alongside the English files as `*.de.md`. There is no
runtime language switch. Output from third-party programs follows their own locale.
Updates also deploy paired guides to registered projects. Existing personal guides
and task text remain; an untouched bundled German Welcome README is backed up and
replaced with its English counterpart. Customized Welcome guides are preserved.

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

## Requirements

Read [SECURITY.md](SECURITY.md) for private files, API tokens and Git commit metadata.
Local reports, backups and runtime data do not belong in the repository.

- Windows x64, a regular user account and enough storage for the models.
- Windows PowerShell 5.1 is sufficient to start; the installer provisions tools
  and then uses PowerShell 7.4 or newer.
- Model selection depends on RAM/VRAM. A larger model file does not guarantee
  better results or sufficient memory.
- Code tasks require a Git repository with at least one commit, installed project
  dependencies and known, locally executable test commands.

## Quick install: latest release

Download the [latest release](https://github.com/mauricehuschke/LoKiEnte/releases/latest)
or its [standalone installer](https://github.com/mauricehuschke/LoKiEnte/releases/latest/download/Provision-LoKiEnte.ps1). The installer embeds the complete source
package; the GitHub source ZIP and a repository clone are not required.
Release **v0.1** contains installer build **2026.11.18.23**; the release version and
the internal build version have different purposes.

These unauthenticated commands work once the repository is public. While it is
private, download the two assets from the release page while signed in to an
authorized GitHub account; unauthenticated requests may return 404.

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
[technical README](Quellpaket/README.md) for details.

`releases/latest/download/...` follows the latest published release, not the newest
commit on `main`. For a fixed version, replace `latest/download` with `download/v0.1`.
GitHub Releases is the distribution channel: it provides versioned downloads and
stable latest links. GitHub Packages is intended for package registries such as
npm, NuGet and container images; a standalone Windows PS1 does not need a second
package there.

Optional repository helpers `Provision-Run.ps1` and `Project-Run.ps1` retain the
legacy default `D:\LoKi`; supply `-InstallRoot` for another destination. They are
not required when installing from the single release PS1.

## All provisioning parameters and options

These are the public parameters of `Provision-LoKiEnte.ps1`. Switches default to
off for a fresh installation. During updates, saved model options take precedence
over defaults when the parameter was not supplied explicitly.

| Parameter | Default / allowed values | Effect |
|---|---|---|
| `-InstallRoot` | Directory of the launched PS1; nonempty | Installation root. Use the same directory for updates. Base programs and LM Studio models retain their own storage locations. |
| `-AuditOnly` | Switch | Inspect prerequisites without installing package files or loading models. Existing CLI tools may initialize caches/services; public metadata is queried online. |
| `-ModelMode` | `Dual`; `Dual`, `Single` | Dual uses a role-based model pool and local router; it does not mean two coding models are loaded simultaneously. Single uses one coding model, currently without semantic indexing. |
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
| `-UpdateManaged` | Switch | Compatibility with older commands; currently no additional effect. Normal runs already update managed files/workspaces. |
| `-NoShortcut` | Switch | Do not create/refresh the desktop shortcut in this run. Does not delete an existing shortcut. |

Saved model options that can be retained: ModelMode, IncludeFastModel,
AllowPartialGpuOffload, AllowUnfitAttempt, RouterPort, PreferredModel, ModelKey,
ApiTokenEnvironmentVariable, ContextLength and Port. ProjectPath, AuditOnly,
SkipModelDownload, UpdateManaged and NoShortcut are not inherited as model options.
Dependencies are upgraded to approved versions; a newer installed version is not
automatically downgraded. This does not mean updating to every arbitrary latest release.

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

## Welcome test without your own application project

Provisioning creates `<InstallRoot>\welcome\workflow-test` as a registered Git
example. It contains an intentionally faulty discount function, package.json
without external dependencies, and a ready-to-use task in its README. All data is
synthetic. A local initial commit enables source-state verification; there is no
remote or automatic commit of subsequent Kilo changes.

1. Launch the desktop shortcut and select `welcome\workflow-test`.
2. Open its README and paste the task into Kilo `shadow-chat`.
3. Observe automatic checks.json preparation and independent reviews. Baseline
   tests must expose the calculation bug; final tests must pass.
4. Check roles, models and results in tool cards or LOKI-STATUS.md. A matching
   VERIFIED report and understandable Git diff demonstrate the basic workflow.
   Security/integration phases are unnecessary for this pure calculation.

The full [test task](Quellpaket/welcome-example/README.md) is also in the source
package. It requires, among other cases, 8000 cents for 10000 cents at 20% discount,
plus boundary cases and error handling. Updates preserve the modified example.
For a fresh attempt, run in PowerShell 7:

```powershell
& 'D:\LoKi\app\New-WelcomeTestProject.ps1' -InstallRoot 'D:\LoKi' -NewExample
```

The example avoids changing your own applications. It is not an OS sandbox:
these processes still run under your account.

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
Enable and complete local indexing per project in the supported Kilo profile.
Verify it once using the [search probe](Quellpaket/VALIDATION.md). Single mode does
not currently configure indexing.

**Are test processes isolated?**
They receive sanitized environment variables and separate temporary/profile paths
but run under your Windows account and can access files and networks. Use approved
commands and local test data without production credentials.

## Package development

Quellpaket contains editable scripts, guides and tests. Build-LoKiEnte.py embeds
them with a SHA-256 checksum. After updating the version in Quellpaket/README.md:

```powershell
python .\Build-LoKiEnte.py 2026.11.18.23
```

Executable checks and their limits are recorded in [VALIDATION.md](Quellpaket/VALIDATION.md).
A real sample task and GPU/GUI acceptance are additionally required on the target machine.

## Logo and project name

The project is named **LoKiEnte**. Provisioning gives the desktop launcher this
name and the duck icon, including on updates. Matching legacy shortcuts for the
same installation are backed up and replaced. `-NoShortcut` skips this step;
shortcuts for other installations remain.

- [Transparent PNG original, 1254 × 1254 pixels](assets/lokiente-logo.png)
- [PNG preview, 512 × 512 pixels](assets/lokiente-preview.png)
- [Windows icon, 16 through 256 pixels](Quellpaket/assets/lokiente.ico)
- [Asset provenance and generation prompt](assets/README.md)

scripts/Build-Logo.ps1 regenerates the preview and multi-size ICO from the original
using PowerShell 7 on Windows. Then rebuild the installer. Only the small ICO is
needed inside the installer; the PNG original stays in the repository.

Historical technical identifiers (`loki_*`, `LOKI_*`, `shadow-*`), files such as
LOKI-STATUS.md and installation markers remain compatible with existing projects.
Existing installation directories are not renamed. Entry helpers still default to
D:\LoKi unless -InstallRoot is supplied; new installations can use D:\LoKiEnte.

### Compatibility of existing installations

The default **name** of the optional token environment variable is
LOKIENTE_LM_API_KEY; this is not a token. Updates retain the saved name unless
explicitly changed with -ApiTokenEnvironmentVariable. Provide the value locally
only. Historical internal prefixes imply neither provider dependence nor personal data.
