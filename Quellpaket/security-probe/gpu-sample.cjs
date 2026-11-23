'use strict';
const path = require('node:path');
const {spawn} = require('node:child_process');
const readline = require('node:readline');
const powershell = path.join(process.env.SystemRoot || 'C:\\Windows', 'System32/WindowsPowerShell/v1.0/powershell.exe');

async function measureInference(run) {
    const child=spawn(powershell,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.join(__dirname,'Measure-Gpu.ps1')],{stdio:['ignore','pipe','pipe'],windowsHide:true});
    // A missing performance counter must not suppress the actual inference test.
    const lines=readline.createInterface({input:child.stdout});
    let active=false, observed=false;
    let signalReady;
    const ready=new Promise(resolve=>{signalReady=resolve;});
    lines.on('line',line=>{if(line==='READY')signalReady();if(active && line==='COMPUTE')observed=true;});
    child.once('close',signalReady);child.once('error',signalReady);child.stderr.resume();
    const timer=setTimeout(signalReady,10000);
    try{
        await ready;
        active=true;
        await run();
        active=false;
        return observed;
    }finally{clearTimeout(timer);lines.close();child.kill();}
}

module.exports={measureInference};
