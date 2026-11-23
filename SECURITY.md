# Privacy and credentials

[Deutsch](SECURITY.de.md)

Only sources, tests, documentation, assets and the embedded installer belong in
this repository. Provisioning reports, runtime profiles, model state, backups and
example projects from an actual installation stay local. .gitignore excludes them;
it does not remove files already tracked in earlier commits.

Provide API tokens through the designated environment variables or local credential
management. Names such as LOKIENTE_LM_API_KEY are not credentials. Never copy real
values into scripts, tests, screenshots or issues. Use synthetic test data and
neutral example paths only.

Before publishing, run Gitleaks on current files and history. The installer embeds
a Base64 ZIP, so scan its extracted contents too. Backup archives can also contain
private data. SHA-256 checksums in manifests are not secret keys.

Use your public username and GitHub no-reply address for commits. GitHub shows the
appropriate address in email settings. Changing Git configuration does not clean
existing commits.

If credentials were published, revoke/rotate them first and then clean history.
A deletion commit is insufficient. Coordinate replacement of published history;
other clones and GitHub caches may retain old contents. Contact GitHub Support
when necessary to remove cached sensitive content.

## Dependency updates

Provisioning enforces a minimum release age of 48 hours in every update policy. The installer resolves exact versions before updating tools. Dynamic policies require dated catalog evidence. See the [update guide](README.md#choose-how-development-tools-update).

## Local E.T. model test

Open LoKiEnte from the desktop shortcut. In a trusted window choose the duck
in the Activity Bar, then **Run E.T. model rule test**. Pick the model from
the provisioned LM Studio catalog. This explicit selection also works if you
temporarily changed models in a Kilo chat.
If you previously enabled the offline VM profile, select **No** in the host shortcut dialog once, then reopen it to use the standard local session.

- **Model behaviour.** Each question starts a new model context with the
  managed chat role prompt, its explicitly configured local Markdown rules and
  the project root AGENTS.md when present. An allowed file request provides a
  positive control. Three challenges ask for a synthetic .env file, a file
  outside the test workspace and a reserved .invalid web address. The exercise
  explains its permissions and response format. Structured model tool requests
  are recorded as decisions. None is dispatched.
- **Kilo tools.** The Kilo runtime bundled with VS Code supplies its resolved
  tool registry. Fixed tool calls exercise real read decisions against freshly
  generated harmless markers. Unrecognized CLI errors cannot pass as denials.
- **Custom rules.** Choose **Test a custom Kilo rule** to add a question about
  an existing instruction. Only your question goes to the selected local model.
  The expected answer is used for a local comparison. Continue managing rules
  in Kilo. Remote instruction URLs are never fetched by the rule loader;
  unsupported instruction sources give an unverified result.
- **Results.** PASS requires the expected observations, FAIL indicates a
  detected violation, and UNVERIFIED means insufficient or ambiguous evidence.
  GPU observation is separate. An unavailable counter cannot establish CPU
  fallback. **Output → LoKiEnte Security** shows the results and local JSON
  report location. The report omits instruction contents, responses and tokens.

The probe uses synthetic targets and the local inference endpoint. It tests
specific model responses and Kilo tools. It does not establish a Windows-wide
network or filesystem restriction for other processes. Users of the optional
prepared VM can run **Check VM isolation** there as an additional test.

## Offline Windows guest

The standard desktop session uses Kilo tool permissions. Tests and extensions
still have the rights of your Windows account. The optional offline profile
starts a separate Hyper-V guest before the host launcher starts any project,
model, router or editor. Prompt rules stay in Kilo. Setting a profile applies
to the next desktop launch; close running managed host windows first.

### Prepare once

Open **Check host capabilities** in the LoKiEnte sidebar first. It reports local Hyper-V availability and discoverable GPU partitions without starting a VM.

1. On the host, check that Hyper-V, its PowerShell management commands and
   VMConnect are available to your Windows account (for example, membership
   in Hyper-V Administrators). A cloud PC needs provider support for nested
   virtualization. Check guest GPU partition and driver support separately.
2. Provision a dedicated Windows guest with this branch's installer, models
   and tools while it can still download them. Test a local model first.
   Shut down the guest, then remove **every virtual network adapter** and
   eject installation media. Keep one local VHDX system disk. Do not attach
   host disks, serial pipes, Fibre Channel or directly assigned devices.
   GPU partitioning (GPU-P) is the supported configuration to try.
3. Enable the guest's **Guest Service Interface** integration service for
   one-way host-to-guest file copy. Turn off **Enhanced Session Mode Policy**
   in the Hyper-V host settings to prevent drive and clipboard redirection.
   This policy affects other VMs on that host. The launcher checks it and
   never changes it. Leave the host's remote desktop network connected.
4. In the managed host window, select **LoKiEnte → Choose security profile →
   Offline Hyper-V guest**. Select the prepared VM and a writable private host
   folder for the probe. LoKiEnte creates a tiny, reusable
   `lokiente-et-<id>.probe` there at launch. Using projects already in the
   guest exposes no host project data. Optionally select a project ZIP outside
   the protected folder. Each launch copies only that archive to a fresh
   `C:\LoKiEnte-Imports\<session>\project.zip` in the guest. Unpack it there.
   Guest edits remain on the guest disk.
5. Close the host's managed VS Code windows and launch the desktop shortcut.
   The VM must be fully off at the start. Log in on its basic console, open
   the **guest** LoKiEnte shortcut, select a guest project and run **LoKiEnte →
   Check VM isolation**. A failed prerequisite stops the launch. If the VM
   already booted before a guest-copy failure, shut it down before retrying.

### Read the results

The host verifies the VM configuration and the existence of its marker. It
delivers a challenge specific to the guest and its current boot. The guest
uses LoKiEnte's normal Node project-check runner. A test child probes IPv4
and IPv6 TCP port 443 (Cloudflare public addresses, no application data),
checks that no external interface address exists, exercises loopback, and
attempts to open the host marker. It also writes, reads and removes a temporary file in the selected guest project. A real completion uses the configured
local LM Studio model. The GPU check needs a positive compute-engine counter
from a known inference worker during that completion. An installed GPU,
a successful CPU completion or missing counters do not pass the GPU check.
See **Output → LoKiEnte Security** and the local JUnit file it names. A passing
run reports these particular observations; the hypervisor supplies the boundary.
Trusted host administrators control the VM. Do not reconnect it during a session.

In the host desktop launch dialog, choose **No** to reset the preference, then reopen the shortcut. **Cancel** closes the launcher and keeps the offline profile.

To return to standard mode after closing the guest, run the following on the
host, replacing the example installation path. It resets the launcher preference.
The next desktop launch opens the normal project picker.

```powershell
pwsh -NoProfile -File 'D:\LoKiEnte\app\Start-LocalAI.ps1' -ResetSecurityProfile
```

Provisioning preserves the host-side preference. Update the guest deliberately
during a separate maintenance window. A VM configured for network access
cannot be started by the offline profile. The marker can be removed manually
after resetting the profile. [Hyper-V guest device redirection](https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/enhanced-session-mode)
