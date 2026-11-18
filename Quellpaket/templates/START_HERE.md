# LoKiEnte

[Deutsch](START_HERE.de.md)

This window uses a dedicated VS Code profile and local models.

1. Open the LoKiEnte desktop shortcut. Select a known project by number or N for another existing project directory (enter its path). 0 cancels before model startup. A direct launcher call with -ProjectPath opens the project without a menu.
2. Chat/planning: Kilo sidebar. Roles and /feature, /bugfix, /refactor, /review, /architecture are predefined.
3. Enter code changes directly in shadow-chat. Criteria and checks.json are prepared automatically and independently reviewed.
4. To try the workflow, select welcome/workflow-test in the launcher. The ready-to-use task is in the [example guide](../welcome-example/README.md). The example uses only synthetic data, built-in Node facilities and its own local Git repository.
5. Only a successful task run may report VERIFIED. This status applies to the exact verified working tree and configured checks.

For semantic search in Dual mode, open Settings > Indexing in Kilo and enable
indexing for the project. First check .gitignore and .kilocodeignore for sensitive
files. The index is stored locally and is not automatically encrypted. Wait for
Complete status; configuration alone does not prove that indexing has finished.

Kilo shows roles/models/phases through loki_status and LOKI-STATUS.md; loki_details explains findings. The runner executes tests. The chat does not write directly.
Updates preserve modified test projects. To create a fresh example, run app/New-WelcomeTestProject.ps1 -InstallRoot <installation-directory> -NewExample in PowerShell 7. The example is not an OS sandbox.
This package does not configure GitHub/Lovable logins or project-specific secrets.
