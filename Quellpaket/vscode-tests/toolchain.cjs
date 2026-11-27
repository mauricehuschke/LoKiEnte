'use strict';
// Entry for VS Code's official --extensionTestsPath interface. No API mocks.
const path = require('node:path');
const vscode = require('vscode');
exports.run = async function () {
    const helper = vscode.extensions.getExtension('lokiente.managed-startup');
    if (!helper) throw new Error('The installed LoKiEnte extension is missing in the real Extension Host.');
    const api = await helper.activate();
    if (!api?.runAcceptance) throw new Error('The installed LoKiEnte extension does not expose live acceptance.');
    const result = await api.runAcceptance({ reportPath: process.env.LOKIENTE_TOOLCHAIN_REPORT, project: process.env.LOKIENTE_TOOLCHAIN_PROJECT, runId: process.env.LOKIENTE_TOOLCHAIN_RUN_ID });
    if (result.status !== 'PASS') throw new Error(`Live toolchain acceptance ${result.status}. Read ${path.basename(result.reportPath)} and LoKiEnte Output.`);
};
