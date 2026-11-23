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
        // The same test can run in a guest with an actual challenge present.
        assert(items.some(item=>['Offline VM on next launch','Guest challenge present'].includes(item.label)));
        await registrations.get('lokiente.security.rules')();
        assert.deepEqual(calls,[['kilo-code.new.sidebarTitle.settingsButtonClicked']]);
    }finally{await rm(root,{recursive:true,force:true});}
});
