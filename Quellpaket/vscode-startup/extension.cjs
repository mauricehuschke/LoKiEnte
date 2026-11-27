'use strict';

const vscode = require('vscode');
const path = require('node:path');
const { registerSyncGuide } = require('./sync-guide.cjs');

async function activate(context) {
    // Do not affect personal VS Code windows, even if this extension is copied there.
    if (process.env.LOKIENTE_MANAGED_VSCODE !== '1') return;
    const dataDirectory = process.env.LOKIENTE_VSCODE_DATA_DIR;
    if (!dataDirectory || !path.isAbsolute(dataDirectory) || !['file', 'vscode-userdata'].includes(context.globalStorageUri.scheme)) return;
    const relative = path.relative(dataDirectory, context.globalStorageUri.fsPath);
    if (!relative || relative === '..' || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative)) return;
    const output = vscode.window.createOutputChannel('LoKiEnte', { log: true });
    let disposed = false;
    context.subscriptions.push(output, { dispose() { disposed = true; } });
    const root = process.env.LOKIENTE_INSTALL_ROOT || path.dirname(dataDirectory);
    const { createLogger, startDiagnostics } = require('./diagnostics.cjs');
    const secrets = Object.entries(process.env).filter(([name]) => /token|api.?key|password/i.test(name)).map(([,value]) => value);
    const logger = createLogger(output, secrets);
    const { waitForKilo, startupSnapshot } = require('./kilo-startup.cjs');
    const helperVersion = context.extension?.packageJSON?.version || 'unknown';
    const snapshot = (state, error) => startupSnapshot(vscode, root, helperVersion, state, error).catch(error => logger.error('LoKiEnte', `Cannot persist startup diagnostics: ${error.message}`));
    const monitor = startDiagnostics({ logger, root, dataDirectory });
    context.subscriptions.push(monitor, vscode.commands.registerCommand('lokiente.showOutput', () => output.show(true)));
    logger.info('VS Code', `LoKiEnte helper ${helperVersion} activated in managed VS Code ${vscode.version}. Log channel: LoKiEnte.`);
    void snapshot('host-started');
    try { await require('./security-view.cjs').registerSecurityView(vscode, context, dataDirectory, { output, logger, root }); }
    catch (error) { logger.error('LoKiEnte', `Settings/security view failed: ${error.message}`); }
    void Promise.resolve(registerSyncGuide(vscode, context, output)).catch(error => logger.error('VS Code', `Sync guidance failed: ${error.message}`));
    const openKilo = async () => {
        try {
            if (vscode.workspace.isTrusted === false) await require('./toolchain-check.cjs').waitForWorkspaceTrust(vscode, logger);
            const kilo = await waitForKilo({ vscode, root, logger, isDisposed: () => disposed });
            if (disposed || !kilo) return;
            logger.info('Kilo Code', 'Activating the installed extension and its dependencies.');
            let timer;
            try { await Promise.race([kilo.activate(), new Promise((_,reject) => { timer = setTimeout(() => reject(new Error('Kilo activation timed out after 90 seconds.')),90000); timer.unref?.(); })]); }
            finally { clearTimeout(timer); }
            if (kilo.isActive === false) throw new Error('Kilo activation returned without an active extension. Inspect the Extension Host errors in LoKiEnte Output.');
            for (const id of kilo.packageJSON?.extensionDependencies || []) {
                const dependency = vscode.extensions.getExtension(id);
                if (!dependency) throw new Error(`Required Kilo dependency is unavailable in the running host: ${id}`);
                await require('./toolchain-check.cjs').withDeadline(() => dependency.activate(), 90000, `Kilo dependency timed out: ${id}`);
            }
            if (disposed) return;
            const command = 'kilo-code.SidebarProvider.focus';
            const commands = await vscode.commands.getCommands(true);
            if (!commands.includes(command)) throw new Error('This Kilo version does not expose its sidebar focus command.');
            if (disposed) return;
            let focusTimer;
            try { await Promise.race([vscode.commands.executeCommand(command), new Promise((_,reject) => { focusTimer = setTimeout(() => reject(new Error('Kilo sidebar focus timed out after 90 seconds.')),90000); focusTimer.unref?.(); })]); }
            finally { clearTimeout(focusTimer); }
            logger.info('Kilo Code', 'Kilo extension activated and its sidebar focus command completed. Connection/inference acceptance is checked separately.');
            await snapshot('kilo-ready');
        } catch (error) {
            const message = error instanceof Error ? error.message : String(error);
            logger.error('Kilo Code', `Could not open Kilo: ${message}`);
            await snapshot('kilo-failed', error);
            if (!disposed) void vscode.window.showWarningMessage(`LoKiEnte could not open Kilo. ${message}`);
        }
    };
    let accepting = false;
    const runAcceptance = async (options = {}) => {
        if (accepting) throw new Error('A live toolchain acceptance is already running in this window.');
        accepting = true; output.show(true);
        try { return await require('./toolchain-check.cjs').checkToolchain({ vscode, root, logger, ...options }); }
        finally { accepting = false; }
    };
    context.subscriptions.push(vscode.commands.registerCommand('lokiente.toolchain.check', () => runAcceptance().catch(error => {
        logger.error('LoKiEnte', `Acceptance could not complete: ${error.message}`);
        void vscode.window.showErrorMessage(`LoKiEnte acceptance failed: ${error.message}`);
    })));
    context.subscriptions.push(vscode.commands.registerCommand('lokiente.openKilo', openKilo));
    if (process.env.LOKIENTE_STARTUP_DIAGNOSTICS_ONLY === '1') output.show(true);
    else if (!process.env.LOKIENTE_TOOLCHAIN_RUN_ID && vscode.workspace.getConfiguration('lokiente.startup').get('openKilo', true)) await openKilo();
    return { runAcceptance };
}

module.exports = { activate };
