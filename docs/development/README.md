# Developing and distributing LoKiEnte

[Deutsch](README.de.md) · [User guide](../../README.md)

This guide is for contributors, maintainers and people adapting a fork of
LoKiEnte. To install and use it, start with the main README.

## Source layout

- `Quellpaket/`: editable provisioning scripts, agent workflows, templates and tests.
- `Provision-LoKiEnte.ps1`: generated standalone installer with an embedded ZIP and SHA-256.
- `Build-LoKiEnte.py`: embeds the source package in that installer.
- `scripts/Build-Logo.ps1` and `assets/`: branding source and derived images.
- `README.md` / `README.de.md`: installation and everyday use.
- `Quellpaket/README.md`: detailed provisioning behavior; also deployed with the package.
- `Quellpaket/WORKFLOW.md`: user workflows; `Quellpaket/VALIDATION.md`: validation evidence and limitations.

Read the [technical package guide](../../Quellpaket/README.md) before changing
provisioning or model behavior. Keep English as the default and German guides
beside their counterparts using `.de.md`. Change both documents together.

## Making changes

Clone or fork the repository and work on a branch. Keep changes focused and
include relevant tests and documentation. Existing installations, registered
projects and custom settings must continue to survive updates.

Submit changes to `main` through a pull request. Its protection requires resolved
review conversations and blocks force pushes and deletion. No second approval is
mandatory for the current single-maintainer workflow. There are currently no
required CI checks; this does not replace running the relevant validation locally.
New GitHub Actions must use full commit SHAs, with minimal workflow permissions.

Read [SECURITY.md](../../SECURITY.md) before committing or publishing: it covers
credentials, local installation data, embedded archives and Git author metadata.
Use synthetic test data and the public GitHub username/no-reply address for commits.
Never commit reports, runtime profiles, private example projects or tokens.

## Local Git workflow

Work directly in the existing project directory and use the local `git` CLI
for branches, staging, commits, tags, fetches and pushes. Confirm the repository
root, active branch and working-tree status before changing files. Review the
staged diff and commit the intended files locally before pushing them.

Do not publish source changes through GitHub connectors, Git data APIs or the
web editor. If local Git writes or authentication are blocked, report the blocker
and pending changes instead of publishing through another interface. PR/release
metadata and asset uploads may use GitHub tooling; source commits and pushed
release tags must originate in this checkout. See [AGENTS.md](../../AGENTS.md).

After merging a PR, fetch and fast-forward the local target branch. Verify local
`HEAD` against the intended remote commit and check `git status --short --branch`
before reporting completion. Preserve and explicitly report remaining user
changes; never reset or clean them away to make the status appear clean.

## Build the installer

Use Python 3 and Windows PowerShell 7 on the development machine. Edit sources in
`Quellpaket`, update the `Version:` line in both package README files using the
`YYYY.MM.DD.N` format, and rebuild from the repository root:

```powershell
$packageReadme = Get-Content .\Quellpaket\README.md -Raw
$buildVersion = [regex]::Match($packageReadme, '(?m)^Version: (\d{4}\.\d{2}\.\d{2}\.\d+)').Groups[1].Value
if (-not $buildVersion) { throw 'Package version is missing.' }
python .\Build-LoKiEnte.py $buildVersion
if ($LASTEXITCODE -ne 0) { throw 'Installer build failed.' }
```

The builder checks the packed bytes against the source files and records the
payload checksum. Do not edit the Base64 payload manually. The target machine
needs only the resulting PS1; there is no separately maintained ZIP to ship.
Changes confined to the root README or this guide do not change the embedded
package and do not require rebuilding the installer.

Run checks appropriate to the changed behavior. The [validation record](../../Quellpaket/VALIDATION.md)
describes the existing suites and what they prove. Test installation and
reprovisioning of an existing environment, including preservation of custom
settings and projects, when setup behavior changes. Real GPU/model/GUI acceptance
on a target Windows machine is separate from synthetic regression tests.

## Publish a release

1. Validate source changes, the installer payload and the relevant tests. Scan
   current files, Git history and decoded installer contents for secrets.
2. Merge through a pull request and tag the exact reviewed commit. A GitHub release
   version identifies the published snapshot; the internal date-based version
   identifies the embedded package build.
3. Create a draft GitHub Release. Attach the installer with the stable filename
   `Provision-LoKiEnte.ps1` and its checksum before publishing:

   ```powershell
   $digest = (Get-FileHash .\Provision-LoKiEnte.ps1 -Algorithm SHA256).Hash.ToLowerInvariant()
   "$digest  Provision-LoKiEnte.ps1" | Set-Content .\Provision-LoKiEnte.ps1.sha256 -Encoding ascii
   ```

4. Every release description must include a changelog and these permanent links,
   even when GitHub already shows the assets below. Keep the latest Windows
   download and provisioning-guide buttons in the installation section of both
   user READMEs, after the project introduction and security overview. Preserve
   the existing quick-install anchors. Detailed setup variants, parameters and
   troubleshooting belong in [the usage reference](../usage/README.md).

   - [Always download the latest Windows installer](https://github.com/mauricehuschke/LoKiEnte/releases/latest/download/Provision-LoKiEnte.ps1)
   - [Latest installer SHA-256](https://github.com/mauricehuschke/LoKiEnte/releases/latest/download/Provision-LoKiEnte.ps1.sha256)
   - [Install or update](https://github.com/mauricehuschke/LoKiEnte/blob/main/README.md#quick-install-latest-release)

   Explain upgrade steps and changed defaults, record the validation performed,
   and distinguish synthetic regression checks from target-machine acceptance.
5. Verify both uploaded assets, publish the release, and check the anonymous
   latest-release download and checksum. Release immutability locks the tag and
   assets after publication; publish a new version to change them.

Keep release-specific details in release notes and package metadata. Keep the
main README pointed at `releases/latest`; its download URLs must not require
users to edit a version number. Links to installation guidance should follow the
current main README. Update title/notes as needed without replacing immutable assets.

GitHub Releases fits this standalone PS1. GitHub Packages serves package
registries such as npm, NuGet and container images and is not needed here.

## Logo and project identity

- [Transparent original, 1254 × 1254 pixels](../../assets/lokiente-logo.png)
- [PNG preview, 512 × 512 pixels](../../assets/lokiente-preview.png)
- [Windows icon, 16 through 256 pixels](../../Quellpaket/assets/lokiente.ico)
- [Asset provenance and generation prompt](../../assets/README.md)

`scripts/Build-Logo.ps1` regenerates the preview and multi-size ICO from the
original using PowerShell 7 on Windows. Rebuild the installer after changing its
ICO. Only the small icon is embedded; the high-resolution PNG stays in the repository.
The desktop shortcut is named LoKiEnte. Updates back up and replace matching
legacy shortcuts for the same installation; `-NoShortcut` skips that step.

## Compatibility and helper scripts

Historical identifiers (`loki_*`, `LOKI_*`, `shadow-*`), `LOKI-STATUS.md` and
installation markers preserve compatibility. Do not rename them without a tested
migration. Existing installation directories are not renamed. The optional
`Provision-Run.ps1` and `Project-Run.ps1` helpers retain the legacy default `D:\LoKi`;
use `-InstallRoot` for a different destination. Release users do not need these helpers.

The default name of the optional token environment variable is `LOKIENTE_LM_API_KEY`,
not a credential value. Updates retain a saved variable name unless explicitly
overridden with `-ApiTokenEnvironmentVariable`. Token values stay local.

Updates deploy paired English/German guides. Personal `ANLEITUNG.md` files and
custom task text remain. An untouched bundled German Welcome README is backed up
and replaced with the English guide; customized Welcome content is preserved.

## Managed VS Code startup

`Quellpaket/VsCodeProfile.ps1` merges the local profile policy and packages the
dependency-free helper from `Quellpaket/vscode-startup/` as a VSIX. Setup installs
it through the regular VS Code CLI into the isolated extension directory and
verifies its version. Keep package.json and extension.vsixmanifest versions aligned.
The helper uses public VS Code extension APIs and Kilo's own sidebar focus command.
It checks both launcher environment and the extension's actual profile storage path.
Do not edit VS Code's SQLite storage, cloud sync state or personal profiles.

Validate profile preservation, sync opt-in removal, idempotence, VSIX contents,
workspace migration and startup/failure behavior using Test-ProvisionSettings.ps1,
Test-VsCodeProfile.ps1, Test-WorkspaceGuide.ps1 and Test-VsCodeStartup.mjs. A real
VS Code/Kilo window and signed-in sync acceptance are separate integration checks.

The startup VSIX also includes `sync-guide.cjs`. Its command
`lokiente.configureExtensionSync` opens the supported VS Code sync configuration
UI and explains selecting Extensions only. The one-time marker records guidance,
not successful configuration. Test it with `node Quellpaket/tests/Test-SyncGuide.mjs`.
Never set internal sync database keys or claim category selection was applied.

The managed `/v1/embeddings` route has its own bounded CPU request handling and
shares router authentication and shutdown protection. Run Test-EmbeddingRouter.mjs,
Test-ModelRouter.mjs, Test-Embedding.ps1 and Test-RouterLifecycle.ps1 after changes.
Provisioning and launch must send embedding preflight and Kilo through the same
route. A synthetic API checks compatibility; real target inference remains separate.

## License and forks

[Apache License 2.0 with Commons Clause 1.0](../../LICENSE.txt) applies to LoKiEnte
itself. Retain both texts and required notices when distributing a fork. This
combined license is source available, not OSI open source. Independent projects
and work products created using LoKiEnte may be used commercially and sold.
