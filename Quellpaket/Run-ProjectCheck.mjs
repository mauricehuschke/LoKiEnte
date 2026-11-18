// Fixed local test runners. No shell, package installation or remote fallback.
import fs from 'node:fs';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';

export function parseCheckArguments(args) {
  const options={files:[]};
  for(let i=0;i<args.length;i+=2){
    const flag=args[i],value=args[i+1];
    if(!['--framework','--project','--report','--file'].includes(flag)||typeof value!=='string'||!value||value.includes('\0'))throw new Error('Invalid project-check arguments');
    if(flag==='--file')options.files.push(value);
    else{const key=flag.slice(2);if(options[key])throw new Error('Duplicate argument');options[key]=value;}
  }
  if(!['node','vitest','jest','playwright','tsc'].includes(options.framework)||!options.project||!options.report)throw new Error('Incomplete project-check arguments');
  if(options.files.length>200)throw new Error('At most 200 explicit test files');
  return options;
}

function inside(root,target){const rel=path.relative(root,target);return rel!==''&&!rel.startsWith('..'+path.sep)&&rel!=='..'&&!path.isAbsolute(rel);}
function localFile(root,relative,{mayBeMissing=false}={}){
  if(typeof relative!=='string'||path.isAbsolute(relative)||relative.split(/[\\/]/).some(p=>!p||p==='.'||p==='..'))throw new Error('Only exact relative test files are allowed');
  const full=path.resolve(root,relative);
  if(!inside(root,full))throw new Error('File outside project');
  let cursor=root;
  for(const part of relative.split(/[\\/]/)){
    cursor=path.join(cursor,part);
    if(fs.existsSync(cursor)&&fs.lstatSync(cursor).isSymbolicLink())throw new Error('Linked test path is not allowed');
  }
  if(!mayBeMissing&&(!fs.existsSync(full)||!fs.statSync(full).isFile()))throw new Error('Required project file is missing: '+relative);
  return full;
}
function localEntrypoint(root,relative){
  const full=path.resolve(root,relative);
  if(!fs.existsSync(full)||!inside(root,fs.realpathSync(full)))throw new Error('Local framework entrypoint missing or linked outside project');
  return full;
}

export function createCheckCommand(options) {
  const root=fs.realpathSync(options.project);
  if(!fs.statSync(root).isDirectory()||!path.isAbsolute(options.report))throw new Error('Absolute project/report paths are required');
  if(fs.existsSync(options.report))throw new Error('Refusing to reuse an existing test report');
  const files=options.files.map(file=>localFile(root,file));
  if(options.framework!=='tsc'&&!files.length)throw new Error('No explicit test files');
  const env={...process.env,CI:'true'};
  let args;
  switch(options.framework){
    case 'node':
      if(files.some(file=>!/[.](cjs|mjs|js)$/.test(file)))throw new Error('Native Node tests require JS/CJS/MJS files');
      args=['--test','--test-reporter=junit','--test-reporter-destination='+options.report,...files];break;
    case 'vitest':
      args=[localEntrypoint(root,'node_modules/vitest/vitest.mjs'),'run','--reporter=junit','--outputFile='+options.report,...files];break;
    case 'jest':
      args=[localEntrypoint(root,'node_modules/jest/bin/jest.js'),'--ci','--runInBand','--json','--outputFile='+options.report+'.jest-raw.json','--runTestsByPath',...files];break;
    case 'playwright':
      env.PLAYWRIGHT_JUNIT_OUTPUT_FILE=options.report;
      // Playwright file filters are regexes; match Windows and normalized paths
      // without allowing punctuation in a reviewed filename to become a pattern.
      args=[localEntrypoint(root,'node_modules/@playwright/test/cli.js'),'test','--reporter=junit',...files.map(file=>'^'+file.split(/[\\/]/).map(part=>part.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')).join('[/\\\\]')+'$')];break;
    case 'tsc':
      args=[localEntrypoint(root,'node_modules/typescript/bin/tsc'),'--noEmit','--pretty','false'];break;
  }
  return {command:process.execPath,args,cwd:root,env};
}

export function convertJestReport(document,project) {
  if(!document||!Array.isArray(document.testResults))throw new Error('Jest did not return testResults');
  const tests=[];
  for(const suite of document.testResults){
    if(typeof suite.name!=='string'||!Array.isArray(suite.assertionResults))throw new Error('Invalid Jest suite');
    const file=path.relative(project,suite.name).split(path.sep).join('/');
    for(const test of suite.assertionResults){
      if(typeof test.fullName!=='string'||!test.fullName.trim())throw new Error('Jest assertion lacks an ID');
      let status;
      if(test.status==='passed')status='passed';
      else if(test.status==='failed')status='failed';
      else if(['pending','todo','disabled','skipped'].includes(test.status))status='skipped';
      else throw new Error('Unsupported Jest assertion status');
      tests.push({id:file+'::'+test.fullName,status});
    }
  }
  return {schemaVersion:1,tests};
}

export async function runProjectCheck(options) {
  const command=createCheckCommand(options);
  const child=spawn(command.command,command.args,{cwd:command.cwd,env:command.env,stdio:'inherit',shell:false,windowsHide:true});
  const code=await new Promise((resolve,reject)=>{child.once('error',reject);child.once('exit',(code,signal)=>resolve(signal?125:(code??125)));});
  if(options.framework==='jest'){
    const raw=options.report+'.jest-raw.json';
    const stat=fs.lstatSync(raw);
    if(!stat.isFile()||stat.isSymbolicLink()||stat.size>16*1024*1024)throw new Error('Invalid Jest report file');
    const result=convertJestReport(JSON.parse(fs.readFileSync(raw,'utf8')),command.cwd);
    fs.writeFileSync(options.report,JSON.stringify(result),{flag:'wx'});
  }
  return code;
}

if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  try{process.exitCode=await runProjectCheck(parseCheckArguments(process.argv.slice(2)));}
  catch(error){console.error('Project check failed:',error.message);process.exitCode=125;}
}
