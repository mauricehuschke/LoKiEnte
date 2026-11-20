'use strict';

const configureCommand = 'workbench.userDataSync.actions.configure';
const instructions = 'LoKiEnte recommends syncing Extensions only. In the VS Code checklist, select Extensions and deselect every other category, including Settings, UI State and Profiles. Apply the selection. If an initial settings merge is still open, cancel it first. This keeps editor settings local and does not replace cloud settings.';

function registerSyncGuide(vscode, context, output) {
    let disposed = false;
    context.subscriptions.push({ dispose() { disposed = true; } });
    const openOptions = async () => {
        try {
            const commands = await vscode.commands.getCommands(true);
            if (disposed) return;
            if (!commands.includes(configureCommand)) throw new Error('Open Settings Sync: Configure from the Command Palette, or choose the categories when turning on Backup and Sync Settings.');
            output.info(instructions);
            await vscode.commands.executeCommand(configureCommand);
            // Public VS Code APIs expose this UI, not its selected categories.
            // Opening it is not evidence that the user applied the recommendation.
            output.info('Opened VS Code sync options. Select only Extensions and apply; LoKiEnte cannot verify the selected categories.');
        } catch (error) {
            output.warn(`Could not open sync options: ${error instanceof Error ? error.message : String(error)}`);
            if (!disposed) void vscode.window.showWarningMessage('Open Settings Sync: Configure and select Extensions only. LoKiEnte has not changed your sync choices.');
        }
    };
    context.subscriptions.push(vscode.commands.registerCommand('lokiente.configureExtensionSync', async () => {
        if (disposed) return;
        void vscode.window.showInformationMessage(instructions);
        await openOptions();
    }));
    const ready = (async () => {
        if (context.globalState.get('extensionSyncGuideVersion', 0) >= 1) return;
        // Record only that the hint was shown, never a fictitious configured state.
        await context.globalState.update('extensionSyncGuideVersion', 1);
        if (disposed) return;
        const choice = await vscode.window.showInformationMessage(instructions, 'Open Sync Options');
        if (choice === 'Open Sync Options' && !disposed) await openOptions();
    })().catch(() => output.warn('Could not show the sync setup hint. Use LoKiEnte: Configure Extension Sync from the Command Palette.'));
    return ready;
}

module.exports = { registerSyncGuide };
