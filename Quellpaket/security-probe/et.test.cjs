'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const net = require('node:net');
const { execFileSync } = require('node:child_process');
const { once } = require('node:events');
const {measureInference} = require('./gpu-sample.cjs');

const powershell = path.join(process.env.SystemRoot || 'C:\\Windows', 'System32/WindowsPowerShell/v1.0/powershell.exe');
function guestIdentity() {
    const command = [
        "$ErrorActionPreference='Stop'",
        "$id=(Get-ItemProperty -LiteralPath 'HKLM:\\SOFTWARE\\Microsoft\\Virtual Machine\\Guest\\Parameters').VirtualMachineId",
        "$boot=(Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToUniversalTime().ToString('o')",
        "[pscustomobject]@{id=[string]$id;boot=$boot}|ConvertTo-Json -Compress"
    ].join(';');
    return JSON.parse(execFileSync(powershell, ['-NoProfile','-NonInteractive','-Command',command], {encoding:'utf8',timeout:20000,windowsHide:true}));
}
function verifyChallenge(c, guest, now=Date.now()) {
    const guid = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
    const id = String(guest.id).replace(/[{}]/g,'').toLowerCase();
    const created = Date.parse(c.createdUtc), boot = Date.parse(guest.boot);
    assert(c.schema === 1 && guid.test(c.vmId) && id === c.vmId.toLowerCase(), 'Host challenge does not identify this Hyper-V guest');
    assert(Number.isFinite(created) && created >= boot && created <= now + 10000, 'No fresh host challenge for this boot');
    assert(/^[a-z]:\\/i.test(c.markerPath) && /^lokiente-et-[0-9a-f-]{36}\.probe$/i.test(path.win32.basename(c.markerPath)), 'Invalid marker');
}
function connect(host, port) {
    return new Promise((resolve,reject) => {
        const socket = net.connect({host,port});
        socket.setTimeout(2500,()=>socket.destroy(Object.assign(new Error('timeout'),{code:'ETIMEDOUT'})));
        socket.once('connect',()=>{socket.destroy();resolve();});
        socket.once('error',reject);
    });
}
async function checkNetwork() {
    const addresses = Object.values(os.networkInterfaces()).flat().filter(a=>a && !a.internal);
    assert.equal(addresses.length,0,'Guest has a non-loopback network address');
    const local = net.createServer(s=>s.end());
    local.listen(0,'127.0.0.1');
    await once(local,'listening');
    try{await connect('127.0.0.1',local.address().port);}finally{local.close();}
    for(const ip of ['1.1.1.1','2606:4700:4700::1111']){
        await assert.rejects(connect(ip,443), e=>['ENETUNREACH','EHOSTUNREACH','EADDRNOTAVAIL','ETIMEDOUT','EACCES','EAFNOSUPPORT'].includes(e.code), 'External TCP connection succeeded or gave an unexpected error');
    }
}
function modelRequest(config) {
    const url = new URL(config.provider.lmstudio.options.baseURL);
    assert(['http:','https:'].includes(url.protocol) && ['127.0.0.1','[::1]','localhost'].includes(url.hostname) && !url.username && !url.password,'Expected a loopback model endpoint');
    url.pathname = url.pathname.replace(/\/$/,'')+'/chat/completions';
    assert(config.model.startsWith('lmstudio/'),'Expected managed model');
    const alias = config.model.slice('lmstudio/'.length);
    const model = config.provider.lmstudio.models[alias]?.id;
    assert(model,'Managed model missing');
    const headers = {'Content-Type':'application/json'};
    const key = config.provider.lmstudio.options.apiKey;
    if(key){
        const match = /^\{env:([A-Za-z_][A-Za-z_0-9]*)\}$/.exec(key);
        assert(match && process.env[match[1]],'Local model credential unavailable');
        headers.Authorization = 'Bearer '+process.env[match[1]];
    }
    return async () => {
        const response = await fetch(url,{method:'POST',headers,redirect:'error',signal:AbortSignal.timeout(180000),
            body:JSON.stringify({model,messages:[{role:'user',content:'Count upward in English, one number per line, until fifty.'}],max_tokens:128,stream:false})});
        assert(response.ok,'Guest inference returned HTTP '+response.status);
        const body=await response.json();
        const message=body.choices?.[0]?.message;
        assert(message && [message.content,message.reasoning_content,message.reasoning].some(x=>typeof x==='string' && x.trim()),'No generated tokens in the response');
    };
}
module.exports={verifyChallenge,modelRequest};
if(require.main===module){
    test('E.T. acceptance in the isolated guest',async t=>{
        const c=JSON.parse(fs.readFileSync(path.join(process.env.ProgramData,'LoKiEnte-ET','challenge.json'),'utf8'));
        verifyChallenge(c,guestIdentity());
        await t.test('External IPv4/IPv6 blocked; guest loopback works',checkNetwork);
        await t.test('Host-confirmed marker cannot be opened by a project test',()=>{
            assert.throws(()=>{const fd=fs.openSync(c.markerPath,'r');fs.closeSync(fd);},e=>['ENOENT','ENOTDIR','EACCES','EPERM'].includes(e.code));
        });
        await t.test('Guest project allows a temporary test file',()=>{
            const project=process.env.LOKIENTE_ET_PROJECT;
            assert(project && path.isAbsolute(project),'A local guest project is required');
            const dir=fs.mkdtempSync(path.join(project,'.lokiente-et-'));
            const file=path.join(dir,'acceptance.txt');
            try{
                fs.writeFileSync(file,c.sessionId,{flag:'wx'});
                assert.equal(fs.readFileSync(file,'utf8'),c.sessionId);
            }finally{
                if(fs.existsSync(file))fs.unlinkSync(file);
                fs.rmdirSync(dir);
            }
        });
        let gpu;
        await t.test('Managed LM Studio model generates tokens inside this guest',async ()=>{
            gpu=await measureInference(modelRequest(JSON.parse(process.env.KILO_CONFIG_CONTENT)));
        });
        await t.test('GPU compute observed on a local inference worker during generation',()=>{
            assert.equal(gpu,true,'GPU UNVERIFIED. No positive compute sample from an LM Studio inference worker. Check guest GPU partition, driver and offload, then retry.');
        });
    });
}
