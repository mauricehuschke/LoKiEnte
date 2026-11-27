'use strict';
const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawn } = require('node:child_process');

async function completedAcceptance(file, runId) {
    try {
        const report = JSON.parse(await fs.readFile(file, 'utf8'));
        return report.runId === runId && ['PASS', 'FAIL', 'BLOCKED'].includes(report.status) ? report : null;
    } catch (error) { if (error.code === 'ENOENT') return null; throw error; }
}

function announceAcceptance({ vscode, report, isolated = false, logger }) {
    const status = report.status;
    const method = status === 'PASS' ? 'showInformationMessage' : status === 'BLOCKED' ? 'showWarningMessage' : 'showErrorMessage';
    const actions = ['Open report', ...(isolated ? ['Close test window'] : [])];
    const first = report.cases?.find(c => c.status === 'FAIL' || c.status === 'BLOCKED');
    void vscode.window[method](`LoKiEnte acceptance finished: ${status}.`, { modal: isolated,
        detail: `${first ? first.evidence + '\n\n' : ''}Report: ${report.reportPath}${isolated ? '\nBackground log forwarding has stopped in this test window. Start a fresh acceptance from provisioning or Test-Toolchain.ps1.' : ''}` }, ...actions)
        .then(async answer => {
            if (answer === 'Close test window' && isolated) await vscode.commands.executeCommand('workbench.action.closeWindow');
            else if (answer === 'Open report') await vscode.window.showTextDocument(await vscode.workspace.openTextDocument(report.reportPath));
        }).catch(error => logger.error('LoKiEnte', `Cannot display acceptance result: ${error.message}`));
}

async function requestAcceptanceRestart({ vscode, root, logger, launch = spawn, env = process.env }) {
    const answer = await vscode.window.showInformationMessage('Run acceptance with the actual LoKiEnte work profile?', { modal: true,
        detail: 'This window will close. Close any other managed LoKiEnte windows too. The background runner waits up to 60 seconds, then starts the same desktop launcher and production configuration. No terminal is kept open.' }, 'Close window and run acceptance');
    if (answer !== 'Close window and run acceptance') return;
    const chain = JSON.parse(await fs.readFile(path.join(root, 'toolchain.json'), 'utf8'));
    const collectorDirectory = path.join(root, 'tooling', 'desktop-runner'), collector = path.join(collectorDirectory, 'LoKiEnte.exe');
    const owner = JSON.parse(await fs.readFile(path.join(collectorDirectory, 'owner.json'), 'utf8'));
    if (owner.owner !== 'lokiente-desktop-runner' || crypto.createHash('sha256').update(await fs.readFile(collector)).digest('hex') !== owner.binarySha256?.toLowerCase()) throw new Error('The installed desktop collector cannot be verified. Reprovision before acceptance.');
    const childEnv = Object.fromEntries(Object.entries(env).filter(([name]) => !/^(?:VSCODE_|ELECTRON_|LOKIENTE_TOOLCHAIN_|LOKIENTE_EDITOR_LAUNCH_ID$)/i.test(name)));
    const args = ['-NoLogo', '-NoProfile', '-NonInteractive', '-File', path.join(root, 'app', 'Test-Toolchain.ps1'), '-InstallRoot', root, '-WaitForProfileClose'];
    const runId = crypto.randomUUID().replaceAll('-', ''), requests = path.join(root, 'runtime', 'launch-requests'), request = path.join(requests, runId + '.json');
    await fs.mkdir(requests, { recursive: true });
    await fs.writeFile(request, JSON.stringify({ file: chain.powerShellExecutable, arguments: args, workingDirectory: root, runId }), { flag: 'wx' });
    await new Promise((resolve, reject) => {
        const child = launch(collector, ['--editor', request], { cwd: root, env: childEnv, shell: false, windowsHide: true, detached: true, stdio: 'ignore' });
        child.once('error', reject); child.once('spawn', () => { child.unref(); resolve(); });
    });
    logger.info('LoKiEnte', 'Background acceptance runner started; closing this window so the real work profile can restart with the current environment.');
    await vscode.commands.executeCommand('workbench.action.closeWindow');
}

module.exports = { completedAcceptance, announceAcceptance, requestAcceptanceRestart };
