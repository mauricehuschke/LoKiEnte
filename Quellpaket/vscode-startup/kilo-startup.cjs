'use strict';
const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');

async function installedKilo(root) {
    const result = [];
    let directories;
    try { directories = await fs.readdir(path.join(root, 'vscode-extensions'), { withFileTypes: true }); }
    catch (e) { if (e.code === 'ENOENT') return result; throw e; }
    for (const directory of directories) {
        if (!directory.isDirectory() || directory.isSymbolicLink() || !/^kilocode\.kilo-code-/i.test(directory.name)) continue;
        const manifest = JSON.parse(await fs.readFile(path.join(root, 'vscode-extensions', directory.name, 'package.json'), 'utf8'));
        if (manifest.publisher?.toLowerCase() === 'kilocode' && manifest.name === 'kilo-code') result.push({ version: manifest.version, engines: manifest.engines, dependencies: manifest.extensionDependencies || [], untrustedWorkspaces: manifest.capabilities?.untrustedWorkspaces });
    }
    return result;
}

async function startupSnapshot(vscode, root, helperVersion, state, error) {
    let launchId = process.env.LOKIENTE_EDITOR_LAUNCH_ID;
    if (!process.env.LOKIENTE_TOOLCHAIN_RUN_ID) {
        const current = await fs.readFile(path.join(root, 'runtime', 'launch-requests', 'current-launch.json'), 'utf8').then(JSON.parse).catch(e => { if (e.code === 'ENOENT') return null; throw e; });
        if (current?.runId) launchId = current.runId;
    }
    const value = { schema: 1, utc: new Date().toISOString(), state, helperVersion, launchId, dataDirectory: process.env.LOKIENTE_VSCODE_DATA_DIR, expectedHelperVersion: process.env.LOKIENTE_STARTUP_VERSION || null,
        vscodeVersion: vscode.version, appHost: vscode.env?.appHost, remoteName: vscode.env?.remoteName || null, workspaceTrusted: vscode.workspace.isTrusted,
        installedKilo: await installedKilo(root), visibleExtensions: (vscode.extensions.all || []).map(extension => ({ id: extension.id, version: extension.packageJSON?.version, active: extension.isActive })),
        error: error ? { code: error.code, message: error.message } : null };
    const file = path.join(root, 'runtime', 'startup-health.json');
    await fs.mkdir(path.dirname(file), { recursive: true });
    const temporary = file + '.' + crypto.randomUUID() + '.tmp';
    await fs.writeFile(temporary, JSON.stringify(value, null, 2)); await fs.rename(temporary, file);
    if (/^[a-f0-9]{32}$/.test(launchId || '')) {
        const handshake = path.join(root, 'runtime', 'startup-handshakes', launchId + '.json'); await fs.mkdir(path.dirname(handshake), { recursive: true });
        const pending = handshake + '.' + crypto.randomUUID() + '.tmp'; await fs.writeFile(pending, JSON.stringify(value)); await fs.rename(pending, handshake);
    }
    return value;
}

async function waitForKilo({ vscode, root, logger, timeoutMs = 90000, pollMs = 250, isDisposed = () => false }) {
    const existing = vscode.extensions.getExtension('kilocode.kilo-code');
    if (existing) return existing;
    logger.info('Kilo Code', 'Waiting for Kilo discovery in this Extension Host; an installed extension may not yet be available during startup.');
    return await new Promise((resolve, reject) => {
        let finished = false, subscription;
        const done = (error, value) => { if (finished) return; finished = true; clearTimeout(deadline); clearInterval(poll); subscription?.dispose(); error ? reject(error) : resolve(value); };
        const check = () => { if (isDisposed()) return done(null, null); const kilo = vscode.extensions.getExtension('kilocode.kilo-code'); if (kilo) done(null, kilo); };
        const deadline = setTimeout(() => {
            void installedKilo(root).then(installed => {
                const error = Object.assign(new Error(installed.length ? `Kilo ${installed.map(k => k.version).join(', ')} is installed but was not exposed by this Extension Host. Check Workspace Trust, whether Kilo is enabled, and Extension Host errors in LoKiEnte Output.` : 'Kilo is not installed in this managed extension directory. Run provisioning with the current installer.'), { code: installed.length ? 'KILO_NOT_DISCOVERED' : 'KILO_NOT_INSTALLED' });
                done(error);
            }).catch(error => done(error));
        }, timeoutMs);
        const poll = setInterval(check, pollMs);
        if (typeof vscode.extensions.onDidChange === 'function') subscription = vscode.extensions.onDidChange(check);
        check(); // Close the discovery/subscription race.
    });
}

module.exports = { installedKilo, startupSnapshot, waitForKilo };
