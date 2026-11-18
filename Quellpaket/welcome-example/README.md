# Welcome: try the Kilo workflow

[Deutsch](README.de.md)

This standalone Git test project contains only synthetic data. Do not install
packages: Node.js, node:test and node:assert/strict are sufficient. Provisioning
creates a local initial commit once. There is no remote; later changes are not
committed automatically.

## Start the test

Open the desktop shortcut and select this workflow-test project. Enter the
following task unchanged in the Kilo shadow-chat agent:

> Fix the bug in discountedPrice in discount.cjs. The function must return the
> remaining price in whole cents after applying the discount:
> (10000, 20) returns 8000, (10000, 0) returns 10000, (10000, 100) returns 0,
> and (999, 10) returns 899. Negative prices and discounts outside 0 through 100
> must throw RangeError. Use the Bugfix workflow. Derive acceptance criteria and
> checks.json automatically. Have the test author write meaningful node:test tests
> in tests/discount.test.cjs and have them independently reviewed. Demonstrate the
> bug with actually failing tests before fixing it. Then change only discount.cjs.
> Preserve the frozen tests and perform code review and validation. Show roles,
> models, phases and results until the task reaches a final status. No dependencies, network access,
> commits or pushes.

Expected: preparation -> preparation review -> architecture -> test author ->
test review -> failing baseline tests -> implementation -> passing tests ->
code review -> validation. Only a matching VERIFIED report means success.
checks.json is created in the managed task directory, alongside LOKI-STATUS.md
and the guide. Inspect details for questions or failures. This test exercises
the complete basic workflow. Security/integration specialists are required for
the corresponding change types; this pure calculation does not need them.

## Repeat

Updates preserve the modified example. For a fresh attempt, run in PowerShell 7
(adjust the path for a different installation):

```powershell
& 'D:\LoKi\app\New-WelcomeTestProject.ps1' -InstallRoot 'D:\LoKi' -NewExample
```

Then select the newly registered workflow-test directory in the launcher.
No existing project is reset. Tests still run under your Windows account;
the example is not an OS sandbox.
