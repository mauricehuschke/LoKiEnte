import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import view from '../vscode-startup/security-view.cjs';
import {readFile} from 'node:fs/promises';

test('the activity bar opens the managed settings view and delegates rules to Kilo',async()=>{
    const root=await mkdtemp(path.join(tmpdir(),'lokiente-ui-'));
    const registrations=new Map(),calls=[];
    let tree;
    class Item {constructor(label){this.label=label;}}
    const api={EventEmitter:class {fire(){}},ThemeIcon:Item,TreeItem:Item,
        commands:{registerCommand(id,fn){registrations.set(id,fn);},async getCommands(){return ['kilo-code.new.sidebarTitle.settingsButtonClicked'];},async executeCommand(...args){calls.push(args);}},
        workspace:{isTrusted:true},
        extensions:{getExtension(){return {async activate(){}};}},
        window:{createOutputChannel(){return {};},registerTreeDataProvider(id,p){assert.equal(id,'lokiente.settingsView');tree=p;},async showInformationMessage(){}}
    };
    try{
        const manifest=JSON.parse(await readFile(new URL('../vscode-startup/package.json',import.meta.url),'utf8'));
        assert.equal(manifest.contributes.viewsContainers.activitybar[0].icon,'lokiente.png');
        await view.registerSecurityView(api,{subscriptions:[]},path.join(root,'vscode-data'));
        assert.deepEqual(calls.shift(),['setContext','lokiente.managedWindow',true]);
        await mkdir(path.join(root,'security'));
        await writeFile(path.join(root,'security','profile.json'),JSON.stringify({schema:1,mode:'offline-vm'}));
        const items=await tree.getChildren();
        assert(items.some(item=>item.command?.command==='lokiente.security.test'));
        assert(items.some(item=>item.command?.command==='lokiente.security.custom'));
        assert.equal(items.find(item=>item.command?.command==='lokiente.security.test').description,'local model');
        assert(items.some(item=>['Offline VM on next launch','Guest challenge present'].includes(item.label)));
        const previous=process.env.KILO_CONFIG_CONTENT;
        try{
            process.env.KILO_CONFIG_CONTENT=JSON.stringify({model:'lmstudio/quality',provider:{lmstudio:{models:{
                quick:{name:'Fast',tool_call:true},quality:{name:'Quality',tool_call:true},embeddings:{tool_call:false}
            }}}});
            api.window.showQuickPick=async models=>{assert.deepEqual(models.map(m=>m.alias),['quality','quick']);return undefined;};
            // Cancellation needs no project, VM, guest marker or provisioned toolchain.
            await registrations.get('lokiente.security.test')();
        }finally{
            if(previous===undefined)delete process.env.KILO_CONFIG_CONTENT;else process.env.KILO_CONFIG_CONTENT=previous;
        }
        await registrations.get('lokiente.security.rules')();
        assert.deepEqual(calls,[['kilo-code.new.sidebarTitle.settingsButtonClicked']]);
    }finally{await rm(root,{recursive:true,force:true});}
});
