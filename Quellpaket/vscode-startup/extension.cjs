'use strict';

const vscode = require('vscode');
const path = require('node:path');

async function activate(context) {
    // Do not affect personal VS Code windows, even if this extension is copied there.
    if (process.env.LOKIENTE_MANAGED_VSCODE !== '1') return;
    const dataDirectory = process.env.LOKIENTE_VSCODE_DATA_DIR;
    if (!dataDirectory || !path.isAbsolute(dataDirectory) || !['file', 'vscode-userdata'].includes(context.globalStorageUri.scheme)) return;
    const relative = path.relative(dataDirectory, context.globalStorageUri.fsPath);
    if (!relative || relative === '..' || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative)) return;
    const output = vscode.window.createOutputChannel('LoKiEnte Startup', { log: true });
    let disposed = false;
    context.subscriptions.push(output, { dispose() { disposed = true; } });
    const openKilo = async () => {
        try {
            const kilo = vscode.extensions.getExtension('kilocode.kilo-code');
            if (!kilo) throw new Error('Kilo is unavailable. Run LoKiEnte provisioning again.');
            await kilo.activate();
            if (disposed) return;
            const command = 'kilo-code.SidebarProvider.focus';
            const commands = await vscode.commands.getCommands(true);
            if (!commands.includes(command)) throw new Error('This Kilo version does not expose its sidebar focus command.');
            if (disposed) return;
            await vscode.commands.executeCommand(command);
            output.info('Kilo opened in the managed LoKiEnte window.');
        } catch (error) {
            const message = error instanceof Error ? error.message : String(error);
            output.warn(`Could not open Kilo: ${message}`);
            if (!disposed) void vscode.window.showWarningMessage(`LoKiEnte could not open Kilo. ${message}`);
        }
    };
    context.subscriptions.push(vscode.commands.registerCommand('lokiente.openKilo', openKilo));
    if (vscode.workspace.getConfiguration('lokiente.startup').get('openKilo', true)) await openKilo();
}

module.exports = { activate };
