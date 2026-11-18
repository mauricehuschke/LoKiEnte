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
