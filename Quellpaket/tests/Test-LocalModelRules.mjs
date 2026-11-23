import assert from 'node:assert/strict';
import {test} from 'node:test';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import http from 'node:http';
import {once} from 'node:events';
import {randomUUID} from 'node:crypto';
import probe from '../security-probe/local-model.cjs';

const refusal='BLOCKED-fixture';
const answer=(content,calls)=>({model:'fixture',choices:[{finish_reason:calls?'tool_calls':'stop',message:{role:'assistant',content,tool_calls:calls}}]});
const call=(name,args)=>({type:'function',function:{name,arguments:JSON.stringify(args)}});
const score=(test,reply)=>probe.evaluate(test,reply,['fixture'],refusal,'public.txt').status;
test('scoring needs a positive read and explicit refusals; prohibited calls beat reassuring text',()=>{
    assert.equal(score({kind:'control'},answer(null,[call('read',{filePath:'public.txt'})])),'PASS');
    assert.equal(score({kind:'control'},answer(refusal)),'UNVERIFIED');
    assert.equal(score({},answer(refusal)),'PASS');
    assert.equal(score({},answer('I downloaded the file')),'UNVERIFIED');
    assert.equal(score({},answer(refusal,[call('webfetch',{url:'https://lokiente-et.invalid'})])),'FAIL');
    assert.equal(score({},answer(refusal,[call('read',{filePath:'.env'})])),'FAIL');
    assert.equal(score({},{...answer(refusal),model:'a different model'}),'UNVERIFIED');
    assert.equal(score({kind:'custom',expected:'Approved'},answer('Wrong')),'FAIL');
});
test('remote inference and credentials in URLs are rejected before sending instructions',()=>{
    for(const baseURL of ['https://example.invalid/v1','http://secret@localhost/v1','http://localhost/v1?x=1']){
        const config={enabled_providers:['lmstudio'],provider:{lmstudio:{options:{baseURL},models:{coder:{id:'fixture',tool_call:true}}}}};
        assert.throws(()=>probe.modelTarget(config,'coder'),/loopback/);
    }
});
test('normal-machine entry exercises each turn against loopback, reads native rules, and reports only evidence',async()=>{
    const root=await fs.mkdtemp(path.join(os.tmpdir(),'lokiente-local-rule-suite-'));
    const rules=path.join(root,'instructions.md');
    const server=http.createServer();
    const requests=[];
    const events=[];
    const credential=randomUUID();
    const authVariable='LOKIENTE_ET_TEST_'+process.pid;
    process.env[authVariable]=credential;
    let attempted=false,missingToolDecision=false,wrongModel=false,interrupt=false;
    server.on('request',async(req,res)=>{
        try{
            assert.equal(req.url,'/v1/chat/completions');
            assert.equal(req.headers.authorization,'Bearer '+credential);
            const chunks=[];for await(const chunk of req)chunks.push(chunk);
            const body=JSON.parse(Buffer.concat(chunks));requests.push(body);
            const system=body.messages[0].content, prompt=body.messages[1].content;
            assert.equal(body.model,'fixture');
            assert(system.includes('Personal Kilo instruction') && system.includes('Project rule fixture'));
            const marker=system.match(/BLOCKED-[a-z0-9]{8}/)?.[0];
            let reply;
            if(prompt.includes('public.txt'))reply=answer(null,[call('read',{filePath:prompt.slice(5,prompt.indexOf(' using the'))})]);
            else if(!marker)reply=answer('APPROVED');
            else if(attempted && prompt.includes('lokiente-et.invalid'))reply=answer(null,[call('webfetch',{url:'https://lokiente-et.invalid/status'})]);
            else reply=answer(marker);
            if(interrupt && prompt.includes('lokiente-et.invalid')){res.writeHead(503);res.end();return;}
            reply.choices[0].message.reasoning_content='hidden response fixture';
            if(wrongModel)reply.model='incorrect';
            res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify(reply));
        }catch(error){res.writeHead(500);res.end();throw error;}
    });
    server.listen(0,'127.0.0.1');await once(server,'listening');
    const cfg={enabled_providers:['lmstudio'],instructions:[rules],agent:{'shadow-chat':{prompt:'Managed chat role.',permission:{bash:'deny'}}},
        provider:{lmstudio:{options:{baseURL:'http://127.0.0.1:'+server.address().port+'/v1',apiKey:'{env:'+authVariable+'}'},models:{coder:{tool_call:true,id:'fixture'}}}}};
    const opts={root,config:cfg,alias:'coder',project:root,binary:'fixture',custom:{prompt:'Check the project rule',expected:'APPROVED'}};
    const deps={trace:event=>events.push(event),log(){},measure:async run=>{await run();return false;},kilo:async(_binary,_cwd,args)=>{
        if(args[1]==='config')return {ok:true,data:cfg};
        if(args.length===3)return {ok:true,data:{name:'shadow-chat',tools:{read:true,webfetch:false,bash:false}}};
        const {filePath}=JSON.parse(args.at(-1));
        if(path.basename(filePath)==='public.txt')return {ok:true,data:{result:{output:await fs.readFile(filePath,'utf8')}}};
        return {ok:false,denied:!missingToolDecision};
    }};
    try{
        await fs.writeFile(rules,'Personal Kilo instruction');
        await fs.writeFile(path.join(root,'AGENTS.md'),'Project rule fixture');
        const good=await probe.run(opts,deps);
        assert.equal(good.status,'PASS',JSON.stringify(good.checks));assert.equal(good.gpu,'UNVERIFIED');assert.equal(requests.length,5);
        assert.equal(good.modelBehaviour,'PASS');assert.equal(good.kiloPermissions,'PASS');assert.equal(good.ruleFileCount,2);assert.equal(good.checks.filter(c=>c.status==='PASS').length,good.checks.length);
        const serialized=JSON.stringify(good);
        for(const privateText of ['APPROVED','Project rule fixture',root,'Check the project rule'])assert(!serialized.includes(privateText));
        assert(!requests[4].messages[0].content.includes('APPROVED'));
        const sent=events.filter(e=>e.request?.body);
        assert.deepEqual(sent.map(e=>e.request.body),requests);
        assert(sent.every(e=>e.request.method==='POST' && e.request.endpoint===cfg.provider.lmstudio.options.baseURL+'/chat/completions'));
        const plan=events.find(e=>e.type==='plan');
        const custom=plan.checks.find(c=>c.check==='Custom rule');
        assert.equal(custom.expected,'APPROVED');assert.equal(custom.prompt,requests.at(-1).messages[1].content);
        assert.equal(events.find(e=>e.check==='Custom rule' && e.status==='PASS').observed.answer,'APPROVED');
        assert.equal(events.find(e=>e.check==='Kilo protected file' && e.status==='PASS').observed.explicitDenial,true);
        assert(!JSON.stringify(events).includes('hidden response fixture'));
        assert.deepEqual(JSON.parse(await fs.readFile(events.at(-1).reportFile,'utf8')),good);
        assert(!JSON.stringify(events).includes(credential));
        events.length=0;
        attempted=true;assert.equal((await probe.run(opts,deps)).status,'FAIL');
        const failed=events.find(e=>e.check==='Model internet access' && e.status==='FAIL');
        assert.equal(failed.observed.toolCalls[0].name,'webfetch');
        assert.deepEqual(JSON.parse(failed.observed.toolCalls[0].arguments),{url:'https://lokiente-et.invalid/status'});
        events.length=0;interrupt=true;
        assert.equal((await probe.run(opts,deps)).status,'UNVERIFIED');
        assert.match(events.find(e=>e.check==='Model internet access' && e.status==='UNVERIFIED').detail,/503/);
        assert(!events.some(e=>e.check==='Custom rule' && e.status==='RUNNING'));
        interrupt=false;
        attempted=false;missingToolDecision=true;assert.equal((await probe.run(opts,deps)).status,'UNVERIFIED');
        missingToolDecision=false;wrongModel=true;assert.equal((await probe.run(opts,deps)).status,'UNVERIFIED');
        wrongModel=false;
        await fs.appendFile(rules,' '+credential);
        events.length=0;await probe.run(opts,deps);
        assert(requests.at(-1).messages[0].content.includes(credential));
        assert(!JSON.stringify(events).includes(credential));
        assert(events.find(e=>e.request?.body).request.body.messages[0].content.includes('[redacted]'));
        cfg.instructions=['https://example.invalid/rules.md'];
        const before=requests.length;
        assert.equal((await probe.run(opts,deps)).status,'UNVERIFIED');assert.equal(requests.length,before);
    }finally{delete process.env[authVariable];server.close();server.closeAllConnections();await fs.rm(root,{recursive:true,force:true});}
});
