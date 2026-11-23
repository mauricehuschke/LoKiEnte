import assert from 'node:assert/strict';
import {test} from 'node:test';
import path from 'node:path';
import os from 'node:os';
import fs from 'node:fs/promises';
import report from '../vscode-startup/et-report.cjs';
import view from '../vscode-startup/security-view.cjs';

test('an interruption preserves completed evidence and distinguishes active and unstarted cases',()=>{
    const state=report.newRun('quality');
    const checks=['configuration','allowed read','outside folder'].map(check=>({check,expected:'fixture'}));
    report.applyEvent(state,{type:'plan',model:'quality',checks});
    report.applyEvent(state,{type:'step',check:'configuration',status:'PASS',observed:{resolved:true}});
    report.applyEvent(state,{type:'step',check:'allowed read',status:'RUNNING',request:{method:'POST'}},11);
    report.applyEvent(state,{type:'fatal',detail:'Runner stopped'},21);
    report.applyEvent(state,{type:'complete',status:'PASS'},22);
    assert.equal(state.phase,'Interrupted');assert.equal(state.finished,21);
    assert.deepEqual(state.checks.map(c=>c.status),['PASS','UNVERIFIED','NOT RUN']);
    assert.equal(state.checks[1].expected,'fixture');assert.equal(state.checks[1].request.method,'POST');
    assert.deepEqual(state.checks[0].observed,{resolved:true});
});

test('sidebar commands open the editor, receive private runner events, and restore a closed report',async()=>{
    const root=await fs.mkdtemp(path.join(os.tmpdir(),'lokiente-report-ui-'));
    const context={extensionUri:root,subscriptions:[]};
    const commands=new Map(),panels=[],messages=[];
    let tree;
    class Item {constructor(label){this.label=label;}}
    const window={
        createOutputChannel(){return {show(){assert.fail('The local test opened Output');},appendLine(){assert.fail('Unexpected Output');}};},
        registerTreeDataProvider(_id,p){tree=p;},
        showQuickPick:async choices=>choices[0],
        showInputBox:async options=>options.title.startsWith('Your')?'Fixture question':'Fixture expected',
        createWebviewPanel(_id,_title,column,options){
            assert.equal(column,api.ViewColumn.Active);assert.deepEqual(options.localResourceRoots,[root]);
            let dispose,receive;
            const panel={reveals:0,reveal(){this.reveals++;},onDidDispose(fn){dispose=fn;},dispose(){dispose();},
                webview:{cspSource:'https://local.invalid',asWebviewUri:uri=>uri,onDidReceiveMessage(fn){receive=fn;},
                    postMessage:async m=>{messages.push(structuredClone(m));return true;}},
                ready(){receive({type:'ready'});}};
            panels.push(panel);queueMicrotask(()=>panel.ready());return panel;
        }
    };
    const api={window,ViewColumn:{Active:-1},Uri:{joinPath:path.join},ThemeIcon:Item,TreeItem:Item,
        workspace:{isTrusted:true},EventEmitter:class {fire(){}},
        commands:{registerCommand(id,fn){commands.set(id,fn);},executeCommand:async()=>{}}};
    const prev=process.env.KILO_CONFIG_CONTENT;
    try{
        process.env.KILO_CONFIG_CONTENT=JSON.stringify({provider:{lmstudio:{models:{quality:{tool_call:true}}}}});
        await fs.mkdir(path.join(root,'app','security-probe'),{recursive:true});
        await fs.writeFile(path.join(root,'toolchain.json'),JSON.stringify({nodeExecutable:process.execPath}));
        const script=path.join(root,'app','security-probe','local-model.cjs');
        await fs.writeFile(script,[
            "const check='Model fixture',model=process.argv[2];",
            "const prompt=process.env.LOKIENTE_ET_CUSTOM?JSON.parse(process.env.LOKIENTE_ET_CUSTOM).prompt:'Built-in';",
            "process.send({type:'plan',model,checks:[{check,prompt,expected:'Fixture expected',group:'Model behaviour'}]});",
            "process.send({type:'step',check,status:'RUNNING',request:{body:{messages:[{content:'Rules'},{content:prompt}]}}});",
            "process.send({type:'step',check,status:'FAIL',observed:{answer:'Other answer'}});",
            "process.send({type:'complete',status:'FAIL',modelBehaviour:'FAIL'});process.exitCode=1;"
        ].join('\n'));
        await view.registerSecurityView(api,context,path.join(root,'vscode-data'));
        for(const kind of ['test','custom']){
            await commands.get('lokiente.security.'+kind)();
            const latest=messages.at(-1).state;
            assert.equal(latest.phase,'Complete');assert.equal(latest.summary.status,'FAIL');
            assert.equal(latest.checks[0].observed.answer,'Other answer');
            assert.equal(latest.checks[0].prompt,kind==='custom'?'Fixture question':'Built-in');
            assert.equal(latest.checks[0].request.body.messages[1].content,latest.checks[0].prompt);
        }
        assert.equal(panels.length,1);
        assert.match(panels[0].webview.html,/Content-Security-Policy/);
        assert.match(panels[0].webview.html,/script-src 'nonce-[0-9a-f]+'/);
        assert.doesNotMatch(panels[0].webview.html,/unsafe-inline|Other answer/);
        panels[0].dispose();
        assert((await tree.getChildren()).some(i=>i.command?.command==='lokiente.security.report'));
        await commands.get('lokiente.security.report')();await new Promise(setImmediate);
        assert.equal(panels.length,2);assert.equal(messages.at(-1).state.checks[0].observed.answer,'Other answer');
        await fs.writeFile(script,"process.send({type:'complete',status:'PASS'});process.exitCode=2;");
        await commands.get('lokiente.security.test')();
        assert.equal(messages.at(-1).state.phase,'Interrupted');
        assert.match(messages.at(-1).state.summary.detail,/stopped/);
    }finally{
        if(prev===undefined)delete process.env.KILO_CONFIG_CONTENT;else process.env.KILO_CONFIG_CONTENT=prev;
        for(const owned of context.subscriptions)owned?.dispose?.();
        await fs.rm(root,{recursive:true,force:true});
    }
});
