'use strict';
const {randomBytes}=require('node:crypto');
const {fork}=require('node:child_process');

function newRun(model) {
    return {model,phase:'Starting',started:Date.now(),checks:[]};
}
function applyEvent(state,event,now=Date.now()) {
    if(!event || state.finished)return;
    if(event.type==='plan'){
        state.model=event.model;state.modelId=event.modelId;state.role=event.role;state.phase='Running';
        state.checks=event.checks.map(item=>({...item,status:'PENDING'}));
    }else if(event.type==='step'){
        let item=state.checks.find(entry=>entry.check===event.check);
        if(!item){item={check:event.check,group:event.check.startsWith('Kilo ')?'Kilo permissions':'Model behaviour'};state.checks.push(item);}
        for(const field of ['status','purpose','expected','group','request','detail','observed']){
            if(event[field]!==undefined)item[field]=event[field];
        }
        if(event.status==='RUNNING')item.started=now;
        else item.finished=now;
    }else if(event.type==='complete' || event.type==='fatal'){
        state.phase=event.type==='fatal'?'Interrupted':'Complete';
        state.finished=now;state.summary=event;
        for(const item of state.checks){
            if(item.status==='PENDING'){item.status='NOT RUN';item.detail='This check was not reached.';}
            else if(item.status==='RUNNING'){item.status='UNVERIFIED';item.detail='The runner did not return a result for this check.';item.finished=now;}
        }
    }
}
function markup(webview,vscode,uri) {
    const asset=name=>webview.asWebviewUri(vscode.Uri.joinPath(uri,name));
    const nonce=randomBytes(18).toString('hex');
    return '<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">'
        +'<meta http-equiv="Content-Security-Policy" content="default-src \'none\'; img-src '+webview.cspSource+'; style-src '+webview.cspSource+'; script-src \'nonce-'+nonce+'\'; base-uri \'none\'; form-action \'none\'">'
        +'<link rel="stylesheet" href="'+asset('et-report.css')+'"><title>E.T. security report</title></head><body>'
        +'<main><header><img width="50" height="50" src="'+asset('lokiente.png')+'" alt=""><div><h1>E.T. security report</h1><p id="model"></p></div><span id="verdict" class="pill"></span></header>'
        +'<div id="error" role="alert" hidden></div><section id="metrics" aria-label="Results by category"></section>'
        +'<div class="progress"><span id="progress-text" role="status"></span><progress id="progress" max="1" value="0"></progress></div>'
        +'<div class="workspace"><nav aria-label="Test cases"><h2>Test cases</h2><div id="cases"></div></nav>'
        +'<article id="detail" aria-label="Selected test details"></article></div><footer id="storage"></footer></main>'
        +'<script nonce="'+nonce+'" src="'+asset('et-report.js')+'"></script></body></html>';
}
function createReport(vscode,context) {
    let panel,state,ready=false,revision=0,posted=0,sending=false;
    // Keep only the current run in extension memory. Hidden or recreated views
    // request a fresh snapshot; concurrent updates coalesce while posting.
    async function refresh(){
        if(sending || !ready || !panel || !state)return;
        sending=true;
        try{
            while(panel && ready && posted<revision){
                const destination=panel,current=revision;
                let delivered=false;
                try{delivered=await destination.webview.postMessage({type:'state',state});}catch{}
                if(panel!==destination)continue;
                if(!delivered){ready=false;break;}
                posted=current;
            }
        }finally{sending=false;}
    }
    function reveal(){
        if(!state)return;
        if(panel){panel.reveal(vscode.ViewColumn.Active);return;}
        panel=vscode.window.createWebviewPanel('lokiente.etReport','E.T. security report',vscode.ViewColumn.Active,
            {enableScripts:true,localResourceRoots:[context.extensionUri]});
        panel.iconPath=vscode.Uri.joinPath(context.extensionUri,'lokiente.png');
        panel.onDidDispose(()=>{panel=undefined;ready=false;});
        panel.webview.onDidReceiveMessage(message=>{
            if(message?.type==='ready'){ready=true;posted=0;void refresh();}
        });
        panel.webview.html=markup(panel.webview,vscode,context.extensionUri);
    }
    context.subscriptions.push({dispose(){panel?.dispose();state=undefined;}});
    return {
        get available(){return Boolean(state);},
        begin(model){state=newRun(model);revision++;reveal();void refresh();},
        reveal,
        update(event){if(state){applyEvent(state,event);revision++;void refresh();}}
    };
}

// The child's IPC channel is private to this run. stdout remains the compact CLI
// summary. No model response or prompt is parsed from logs or written by the UI.
function runInEditor(node,script,alias,options,report,context){
    return new Promise(resolve=>{
        let terminal;
        const child=fork(script,[alias],{...options,execPath:node,execArgv:[],windowsHide:true,
            stdio:['ignore','ignore','ignore','ipc'],timeout:1200000});
        const owned={dispose(){if(child.exitCode===null && !child.killed)child.kill();}};
        context.subscriptions.push(owned);
        const fatal=detail=>report.update({type:'fatal',detail});
        child.on('message',event=>{
            if(event?.type==='complete' || event?.type==='fatal')terminal=event;
            else if(event?.type==='plan' || event?.type==='step')report.update(event);
        });
        child.once('error',()=>fatal('Could not start the provisioned Node test runner.'));
        child.once('close',(code,signal)=>{
            const index=context.subscriptions.indexOf(owned);
            if(index>=0)context.subscriptions.splice(index,1);
            if(terminal?.type==='fatal')fatal(terminal.detail);
            else if(terminal && !signal && code===({PASS:0,FAIL:1,UNVERIFIED:2})[terminal.status])report.update(terminal);
            else fatal('The test runner stopped before returning a complete report.');
            resolve();
        });
    });
}
module.exports={createReport,runInEditor,newRun,applyEvent,markup};
