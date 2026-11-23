'use strict';
const fs = require('node:fs/promises');
const path = require('node:path');
const { execFile } = require('node:child_process');
const { promisify } = require('node:util');
const execute = promisify(execFile);

function registerSecurityView(vscode, context, dataDirectory) {
    const root = path.dirname(dataDirectory);
    const guestChallenge = path.join(process.env.ProgramData, 'LoKiEnte-ET', 'challenge.json');
    const profile = path.join(root, 'security', 'profile.json');
    const event = new vscode.EventEmitter();
    const output = vscode.window.createOutputChannel('LoKiEnte Security');
    const run = async (script,args,timeout=30000) => {
        const chain = JSON.parse(await fs.readFile(path.join(root,'toolchain.json'),'utf8'));
        return execute(chain.powerShellExecutable,['-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.join(root,'app',script),...args],
            {windowsHide:true,timeout,maxBuffer:2*1024*1024});
    };
    const folder = async label => (await vscode.window.showOpenDialog({openLabel:label,canSelectFiles:false,canSelectFolders:true,canSelectMany:false,availableFileSystems:['file']}))?.[0]?.fsPath;
    function item(label,icon,command,description){
        const entry = new vscode.TreeItem(label);
        entry.iconPath = new vscode.ThemeIcon(icon);
        if(command)entry.command={command,title:label};
        entry.description=description;
        return entry;
    }
    const provider = {onDidChangeTreeData:event.event,getTreeItem:entry=>entry,async getChildren(){
        let mode = 'Local session';
        try{
            const p=JSON.parse(await fs.readFile(profile,'utf8'));
            mode=p.schema===1 && p.mode==='offline-vm' ? 'Offline VM on next launch' :
                p.schema===1 && p.mode==='standard' ? mode : 'Invalid profile';
        }catch(e){if(e.code!=='ENOENT')mode='Unreadable profile';}
        let guest=false;
        try{await fs.access(guestChallenge);guest=true;}catch{}
        return [
            item(guest?'Guest challenge present':mode,'shield'),
            item('Run E.T. model rule test','beaker','lokiente.security.test','local model'),
            item('Test a custom Kilo rule','checklist','lokiente.security.custom'),
            ...(guest?[]:[item('Check host capabilities','pulse','lokiente.security.inspect'),item('Choose security profile','settings-gear','lokiente.security.choose')]),
            ...(guest?[item('Check VM isolation','vm','lokiente.security.guestTest')]:[]),
            item('Kilo rules and workflows','book','lokiente.security.rules','Agent Behaviour'),
            item('LoKiEnte startup settings','settings','lokiente.security.settings'),
            item('Configure extension sync','sync','lokiente.configureExtensionSync')
        ];
    }};
    context.subscriptions.push(output,event,vscode.window.registerTreeDataProvider('lokiente.settingsView',provider));
    const command = (id,fn) => context.subscriptions.push(vscode.commands.registerCommand(id,async()=>{
        try{await fn();}catch(e){
            const message=e.stderr || e.message || String(e);
            output.appendLine(message);output.show(true);
            await vscode.window.showErrorMessage('LoKiEnte: '+message.slice(0,450));
        }finally{event.fire();}
    }));
    command('lokiente.security.settings',()=>vscode.commands.executeCommand('workbench.action.openSettings','@ext:lokiente.managed-startup'));
    command('lokiente.security.rules',async()=>{
        await vscode.extensions.getExtension('kilocode.kilo-code')?.activate();
        const cmds=await vscode.commands.getCommands(true);
        const settings='kilo-code.new.sidebarTitle.settingsButtonClicked';
        if(cmds.includes(settings))await vscode.commands.executeCommand(settings);
        else await vscode.commands.executeCommand('lokiente.openKilo');
        await vscode.window.showInformationMessage('In Kilo Settings, open Agent Behaviour → Rules or Workflows.');
    });
    command('lokiente.security.inspect',async()=>{
        output.show(true);
        output.appendLine((await run('SecurityProfile.ps1',['-Action','Inspect'])).stdout.trim());
    });
    command('lokiente.security.choose',async()=>{
        if(!vscode.workspace.isTrusted)throw new Error('Change profiles from a trusted managed window.');
        const mode=await vscode.window.showQuickPick(['Standard host session','Offline Hyper-V guest'],{title:'Choose how the next desktop launch opens LoKiEnte'});
        if(!mode)return;
        if(mode==='Standard host session'){
            if(await vscode.window.showWarningMessage('Use the standard host session on future launches?',{modal:true},'Use standard')==='Use standard')
                await run('SecurityProfile.ps1',['-Action','Disable']);
            return;
        }
        const machines=JSON.parse((await run('SecurityProfile.ps1',['-Action','List'])).stdout);
        if(!machines.length)throw new Error('No Hyper-V guest found. Prepare a dedicated Windows guest with LoKiEnte and its models installed.');
        const vm=await vscode.window.showQuickPick(machines.map(m=>({label:m.Name,id:m.VMId})),{title:'Select the dedicated provisioned offline VM'});
        if(!vm)return;
        const blocked=await folder('Select a protected host folder for the harmless E.T. marker');
        if(!blocked)return;
        const snapshot=await vscode.window.showQuickPick(['Use projects already inside the VM','Import a project ZIP at each launch'],{title:'Project access'});
        if(!snapshot)return;
        const importing=snapshot.startsWith('Import');
        const source=importing?(await vscode.window.showOpenDialog({openLabel:'Select project archive',canSelectMany:false,canSelectFiles:true,canSelectFolders:false,filters:{ZIP:['zip']},availableFileSystems:['file']}))?.[0]?.fsPath:undefined;
        if(importing && !source)return;
        const confirmation=await vscode.window.showInformationMessage('Start future desktop launches in '+vm.label+'? Close all managed host VS Code windows before using the guest.'+(source?' A fresh copy of the selected ZIP is sent to the guest at each launch.':''),{modal:true},'Enable offline VM');
        if(confirmation!=='Enable offline VM')return;
        await run('SecurityProfile.ps1',['-Action','Enable','-VmId',vm.id,'-ProtectedFolder',blocked,...(source?['-ImportArchive',source]:[])]);
        await vscode.window.showInformationMessage('Offline VM selected. Close the managed host window, then reopen LoKiEnte from the desktop.');
    });
    let testing=false;
    async function testModel(customRule) {
        if(!vscode.workspace.isTrusted)throw new Error('Open a trusted managed window to run the local model test.');
        if(testing)return;
        testing=true;
        try{
            const config=JSON.parse(process.env.KILO_CONFIG_CONTENT || '{}');
            const catalog=config.provider?.lmstudio?.models ?? {};
            const models=Object.entries(catalog).filter(([,m])=>m.tool_call===true).map(([alias,m])=>({
                alias,label:alias,description:m.name,detail:config.model==='lmstudio/'+alias?'Managed default':undefined
            })).sort((a,b)=>Number(Boolean(b.detail))-Number(Boolean(a.detail)));
            if(!models.length)throw new Error('No provisioned local chat models. Reopen VS Code from the LoKiEnte desktop shortcut.');
            const model=await vscode.window.showQuickPick(models,{title:'E.T. — choose the local model to test'});
            if(!model)return;
            let custom;
            if(customRule){
                const input={ignoreFocusOut:true,validateInput:s=>!s.trim() || s.length>3000?'Enter 1–3000 characters.':undefined};
                const prompt=await vscode.window.showInputBox({...input,title:'Your question about an existing Kilo rule'});
                if(!prompt)return;
                const expected=await vscode.window.showInputBox({...input,title:'Exact visible answer required to pass',prompt:'Only the question is sent to the model.'});
                if(!expected)return;
                custom={prompt,expected:expected.trim()};
            }
            const chain=JSON.parse(await fs.readFile(path.join(root,'toolchain.json'),'utf8'));
            const project=vscode.workspace.workspaceFolders?.find(f=>f.uri.scheme==='file')?.uri.fsPath;
            const env={...process.env,LOKIENTE_ET_PROJECT:project || '',LOKIENTE_ET_CUSTOM:custom?JSON.stringify(custom):''};
            output.show(true);
            output.appendLine('E.T. local model rule test — '+model.alias);
            await vscode.window.withProgress({location:vscode.ProgressLocation.Notification,title:'Checking Kilo permissions and '+model.label},async()=>{
                const proc=execute(chain.nodeExecutable,[path.join(root,'app','security-probe','local-model.cjs'),model.alias],
                    {cwd:root,env,windowsHide:true,timeout:1200000,maxBuffer:1024*1024});
                proc.child.stdout.setEncoding('utf8');
                proc.child.stdout.on('data',chunk=>output.append(chunk));
                try{await proc;}
                catch(e){
                    if(e.stderr?.trim())throw new Error(e.stderr.trim().slice(0,450));
                    if(![1,2].includes(e.code) || !e.stdout?.includes('Local report:'))throw new Error('The local model test did not complete.');
                    void vscode.window.showWarningMessage('Local rule check '+(e.code===1?'failed':'was inconclusive')+'. See LoKiEnte Security for each result.');
                }
            });
        }finally{testing=false;}
    }
    command('lokiente.security.test',()=>testModel(false));
    command('lokiente.security.custom',()=>testModel(true));
    command('lokiente.security.guestTest',async()=>{
        if(!vscode.workspace.isTrusted)throw new Error('Run acceptance from a trusted managed guest window.');
        const project=vscode.workspace.workspaceFolders?.find(f=>f.uri.scheme==='file');
        if(!project)throw new Error('Open a local guest project first.');
        if(testing)return;
        testing=true;
        try{
            output.show(true);output.appendLine('Starting E.T. acceptance…');
            await vscode.window.withProgress({location:vscode.ProgressLocation.Notification,title:'Checking guest isolation and GPU inference'},async()=>{
                try{const result=await run('Invoke-ETCheck.ps1',['-ProjectPath',project.uri.fsPath],240000);output.appendLine(result.stdout);}
                catch(e){if(e.stdout)output.appendLine(e.stdout);throw e;}
            });
        }finally{testing=false;}
    });
    return vscode.commands.executeCommand('setContext','lokiente.managedWindow',true);
}
module.exports={registerSecurityView};
