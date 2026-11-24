'use strict';
(() => {
    const vscode=acquireVsCodeApi();
    const byId=id=>document.getElementById(id);
    const groups=['Network reference','Kilo permissions','Model behaviour','Runtime'];
    const labels={PASS:'Passed',FAIL:'Failed',UNVERIFIED:'Unverified',OBSERVED:'Observed',PENDING:'Queued',RUNNING:'Running','NOT RUN':'Not run'};
    let run,selected,pinned=false,previousRun,displayedKey,rendered;
    const el=(tag,text,css)=>{
        const node=document.createElement(tag);
        if(text!==undefined && text!==null)node.textContent=String(text);
        if(css)node.className=css;
        return node;
    };
    const tone=status=>({PASS:'pass',OBSERVED:'pass',FAIL:'fail',UNVERIFIED:'warn',RUNNING:'running'})[status] || 'neutral';
    const pill=status=>el('span',labels[status] || status,'pill '+tone(status));
    const title=item=>item.check.replace(/^(Kilo|Model) /,'').replace(/^./,c=>c.toUpperCase());
    function section(label,node){
        const box=el('section',null,'field');box.append(el('h3',label),node);return box;
    }
    function code(value){
        return el('pre',typeof value==='string'?value:JSON.stringify(value,null,2));
    }
    function fold(name,value,opened){
        const box=el('details');box.dataset.section=name;
        box.append(el('summary',name),code(value));box.open=opened.has(name);return box;
    }
    function showDetail(item){
        const container=byId('detail');
        const key=item?.check,signature=JSON.stringify(item);
        if(displayedKey===key && rendered===signature && container.childNodes.length)return;
        const expanded=new Set(displayedKey===key?[...container.querySelectorAll('details[open]')].map(n=>n.dataset.section):[]);
        displayedKey=key;rendered=signature;
        container.replaceChildren();
        if(!item){container.append(el('h2',run.finished?'No test cases returned':'Preparing test cases…'));return;}
        const head=el('div',null,'case-head');
        head.append(el('span',item.group,'eyebrow'),pill(item.status));
        container.append(head,el('h2',title(item)),el('p',item.purpose || item.check,'purpose'));
        if(item.interpretation)container.append(section('Why model behaviour failed',el('p',item.interpretation)));
        const compare=el('div',null,'comparison');
        const expected=section('Expected result',el('p',item.expected || 'A verifiable decision from the runner.'));
        const isControl=['Runtime','Network reference'].includes(item.group);
        if(item.forbidden)compare.append(expected,section(isControl?'What would invalidate this check':'What must not happen',el('p',item.forbidden)));
        else compare.append(expected);
        const observed=section('Actual result',el('p',item.detail || (item.status==='RUNNING'?'Waiting for the result…':'Awaiting execution.')));
        expected.classList.add('criterion');observed.classList.add('outcome',tone(item.status));
        compare.append(observed);container.append(compare);
        const boundary=item.observed?.kiloBoundary;
        if(boundary){
            const result=el('div',null,'boundary-result');
            result.append(pill(boundary.status),el('p',boundary.detail));
            if(boundary.probe)result.append(el('small','Independent fixed probe: '+boundary.probe));
            container.append(section('Kilo protection for this request',result));
        }
        const request=item.request;
        if(item.prompt)container.append(section('User prompt',code(item.prompt)));
        const answer=item.observed;
        if(answer?.toolCallsDispatched===false){
            container.append(section('Tool execution',el('p',answer.toolCalls?.length || answer.legacyFunctionCall?
                'The model requested a tool. The test runner did not execute it.':'The runner executed no model-requested tools.')));
        }
        if(answer && Object.hasOwn(answer,'answer')){
            container.append(section('Assistant answer',code(answer.answer || (answer.toolCalls?.length?'Tool call only.':'No visible answer returned.'))));
            if(answer.toolCalls?.length)container.append(section('Requested tool calls',code(answer.toolCalls)));
            if(answer.legacyFunctionCall)container.append(section('Requested legacy function',code(answer.legacyFunctionCall)));
        }
        if(request?.body){
            const endpoint=el('div',null,'endpoint');endpoint.append(el('b',request.method),el('code',request.endpoint));
            container.append(endpoint,fold('System prompt',request.body.messages[0].content,expanded),fold('Request payload · JSON',request.body,expanded));
        }else if(request)container.append(section('Test operation',code(request)));
        if(answer)container.append(fold('Response details · JSON',answer,expanded));
        if(item.started && item.finished)container.append(el('p','Duration '+((item.finished-item.started)/1000).toFixed(1)+' s','duration'));
    }
    function update(state){
        run=state;
        if(previousRun!==state.started){pinned=false;selected=undefined;displayedKey=undefined;previousRun=state.started;}
        const checks=state.checks;
        const running=checks.find(c=>c.status==='RUNNING' && c.group!=='Runtime');
        if(!pinned){
            selected=(running || (state.finished && (checks.find(c=>c.status==='FAIL') ||
                checks.find(c=>c.status==='UNVERIFIED' && c.group!=='Runtime') || checks.find(c=>c.group==='Model behaviour'))) ||
                checks.find(c=>c.check===selected) || checks[0])?.check;
        }
        byId('model').textContent=[state.model,state.modelId && state.modelId!==state.model?state.modelId:null,state.role].filter(Boolean).join('  ·  ');
        const protection=state.summary?.protection;
        const verdict=protection?.status || state.summary?.status || (state.phase==='Interrupted'?'UNVERIFIED':state.phase==='Starting'?'Starting':'RUNNING');
        byId('verdict').textContent=state.summary?.status?(protection?'Tested Kilo protection · ':'Combined checks · ')+(labels[verdict] || verdict):(labels[verdict] || verdict);
        byId('verdict').className='pill '+tone(verdict);
        const error=byId('error');error.hidden=!state.summary?.detail;error.textContent=state.summary?.detail || '';
        const scope=byId('boundary-summary');
        scope.textContent=protection?'Network protection: '+(labels[protection.network] || protection.network)+
            '  ·  File protection: '+(labels[protection.files] || protection.files)+
            '. Based on fixed probes against the managed Kilo role.':'';
        scope.hidden=!protection;
        byId('export').disabled=!state.finished;
        const totalDone=checks.filter(c=>!['PENDING','RUNNING','NOT RUN'].includes(c.status)).length;
        byId('progress-text').textContent=checks.length?totalDone+' of '+checks.length+' checks evaluated':(state.finished?'Run stopped':'Preparing the local runner…');
        byId('progress').max=Math.max(checks.length,1);byId('progress').value=totalDone;
        const metrics=byId('metrics');metrics.replaceChildren();
        for(const [name,key] of [['Model behaviour','modelBehaviour'],['Kilo permissions','kiloPermissions'],['Network reference','networkReference'],['GPU activity','gpu']]){
            const members=checks.filter(c=>c.group===(key==='gpu'?'Runtime':name));
            const known=state.summary?.[key] || (members.some(c=>c.status==='FAIL')?'FAIL':members.some(c=>c.status==='RUNNING')?'RUNNING':null);
            const card=el('div',null,'metric '+tone(known));
            const finished=members.filter(c=>!['PENDING','RUNNING','NOT RUN'].includes(c.status)).length;
            card.append(el('span',name),el('strong',known?labels[known]:(members.length?finished+' / '+members.length:'—')));
            if(key==='modelBehaviour' && known==='FAIL'){
                const failed=members.filter(c=>c.status==='FAIL');
                const only=failed.length===1?failed[0]:undefined;
                card.append(el('p',state.summary?.modelInterpretation || only?.interpretation || 'At least one model response missed its expected behaviour. Open a failed case to see what the model requested and whether Kilo protection held.'));
            }
            metrics.append(card);
        }
        const list=byId('cases');
        const focused=list.contains(document.activeElement)?document.activeElement.dataset.check:undefined;
        list.replaceChildren();
        groups.forEach(group=>{
            const members=checks.filter(c=>c.group===group);if(!members.length)return;
            list.append(el('h3',group,'group'));
            for(const item of members){
                const button=el('button',null,'case '+(item.check===selected?'selected':''));
                button.type='button';button.dataset.check=item.check;button.setAttribute('aria-pressed',String(item.check===selected));
                button.append(el('span',title(item)),el('small',labels[item.status] || item.status,tone(item.status)));
                button.onclick=()=>{pinned=true;selected=item.check;update(run);};
                list.append(button);if(focused===item.check)button.focus({preventScroll:true});
            }
        });
        showDetail(checks.find(c=>c.check===selected));
        byId('scope').textContent=state.scope || '';
        byId('storage').textContent=state.summary?.reportFile?'Compact report  ·  '+state.summary.reportFile:'Detailed evidence stays in this window until you export it.';
    }
    window.addEventListener('message',event=>{if(event.data?.type==='state')update(event.data.state);});
    byId('export').onclick=()=>vscode.postMessage({type:'export'});
    vscode.postMessage({type:'ready'});
})();
