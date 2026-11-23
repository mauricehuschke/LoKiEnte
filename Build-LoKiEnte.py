"""Rebuild the self-contained PowerShell installer from Quellpaket."""

import argparse
import base64
import hashlib
import io
from pathlib import Path
import re
import textwrap
import uuid
import zipfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", help="Version recorded in Quellpaket/README.md")
    args = parser.parse_args()
    if not re.fullmatch(r"\d{4}\.\d{2}\.\d{2}\.\d+", args.version):
        parser.error("Expected a YYYY.MM.DD.N version")

    root = Path(__file__).resolve().parent
    source = root / "Quellpaket"
    installer = root / "Provision-LoKiEnte.ps1"
    readme = (source / "README.md").read_text(encoding="utf-8-sig")
    if not re.search(r"^Version: " + re.escape(args.version) + r"\s", readme, re.M):
        parser.error("Update the version in Quellpaket/README.md first")
    paths = sorted(source.rglob("*"))
    files = {}
    for file in paths:
        # Reject name-surrogate tags such as junctions. Sync placeholders can
        # still be read and packed when the source lives in a synchronized folder.
        if file.is_symlink() or getattr(file.lstat(), "st_reparse_tag", 0) & 0x20000000:
            parser.error(f"Link in source package: {file}")
        if file.is_file():
            files[file.relative_to(source).as_posix()] = file.read_bytes()
    required = {
        "assets/lokiente.ico", "Setup.ps1", "Start-LocalAI.ps1", "Invoke-SetupRequest.ps1",
        "UpdatePolicy.ps1", "DependencyVersions.ps1", "Indexing.ps1", "VsCodeProfile.ps1", "vscode-startup/package.json", "vscode-startup/extension.cjs",
        "vscode-startup/sync-guide.cjs",
        "vscode-startup/extension.vsixmanifest", "vscode-startup/[Content_Types].xml",
        "WorkflowPolicy.ps1", "Invoke-ReviewedTask.ps1", "TaskPreparation.ps1",
        "WorkflowProgress.ps1", "KiloWorkflowTools.mjs", "WorkflowJob.mjs",
        "Run-ProjectCheck.mjs", "AcceptancePolicy.ps1", "AgentTemplates.ps1",
        "New-WelcomeTestProject.ps1", "welcome-example/package.json",
        "welcome-example/discount.cjs", "welcome-example/README.md", "welcome-example/README.de.md",
        "README.de.md", "WORKFLOW.md", "WORKFLOW.de.md", "VALIDATION.de.md",
        "templates/LOCAL-AI-RULES.md", "templates/LOCAL-AI-RULES.de.md",
        "templates/START_HERE.md", "templates/START_HERE.de.md",
        "templates/task.md", "templates/task.de.md",
    }
    if required - files.keys():
        parser.error(f"Missing source files: {sorted(required - files.keys())}")

    payload = io.BytesIO()
    with zipfile.ZipFile(payload, "w") as archive:
        for name, data in files.items():
            archive.writestr(zipfile.ZipInfo(name), data, zipfile.ZIP_DEFLATED, 9)
    with zipfile.ZipFile(payload, "r") as archive:
        if {name: archive.read(name) for name in archive.namelist()} != files:
            raise RuntimeError("Payload differs from the source package")
    data = payload.getvalue()
    digest = hashlib.sha256(data).hexdigest()
    encoded = "\n".join(textwrap.wrap(base64.b64encode(data).decode("ascii"), 120))
    script = installer.read_text(encoding="utf-8-sig")
    replacements = {
        r"(?m)^(\$bundleVersion=)'[^']+'": f"'{args.version}'",
        r"(?m)^(\$payloadSha256=)'[a-f0-9]{64}'": f"'{digest}'",
        r"(?ms)^(\$payloadBase64=)@'\n.*?\n'@": f"@'\n{encoded}\n'@",
    }
    for pattern, value in replacements.items():
        script, count = re.subn(pattern, lambda match: match[1] + value, script)
        if count != 1:
            raise RuntimeError("Installer must contain exactly one of each payload field")
    temporary = installer.with_name(f"{installer.name}.{uuid.uuid4().hex}.tmp")
    try:
        temporary.write_bytes(script.replace("\n", "\r\n").encode("utf-8-sig"))
        temporary.replace(installer)
    finally:
        temporary.unlink(missing_ok=True)
    print(f"{args.version}: {len(files)} files, SHA-256 {digest}")


if __name__ == "__main__":
    main()
