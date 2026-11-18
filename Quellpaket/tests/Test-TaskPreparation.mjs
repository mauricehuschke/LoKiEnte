import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {parseCheckArguments,createCheckCommand,convertJestReport,runProjectCheck} from '../Run-ProjectCheck.mjs';
const root=fs.mkdtempSync(path.join(os.tmpdir(),'shadow-check-adapter-'));
let checks=0;
function expectThrow(fn){assert.throws(fn);checks++;}
try{
  fs.mkdirSync(path.join(root,'tests'));
  const test='tests/real.test.cjs';
  fs.writeFileSync(path.join(root,test),"const {test}=require('node:test');const assert=require('node:assert/strict');test('adds',()=>assert.equal(1+1,2));");
  const options=parseCheckArguments(['--framework','node','--project',root,'--report',path.join(root,'report.xml'),'--file',test]);
  assert.equal(createCheckCommand(options).command,process.execPath);checks++;
  assert.equal(await runProjectCheck(options),0);assert.match(fs.readFileSync(options.report,'utf8'),/<testcase/);checks++;
  expectThrow(()=>createCheckCommand(options));
  expectThrow(()=>parseCheckArguments(['--framework','node','--shell','cmd']));
  expectThrow(()=>parseCheckArguments(['--framework','node','--framework','jest']));
  expectThrow(()=>createCheckCommand({...options,report:path.join(root,'new.xml'),files:['../escape.cjs']}));
  expectThrow(()=>createCheckCommand({...options,report:path.join(root,'new.xml'),files:[]}));
  expectThrow(()=>createCheckCommand({...options,framework:'vitest',report:path.join(root,'new.xml')}));
  const playwrightEntry=path.join(root,'node_modules/@playwright/test/cli.js');
  fs.mkdirSync(path.dirname(playwrightEntry),{recursive:true});fs.writeFileSync(playwrightEntry,'throw new Error("discovery must not execute this");');
  const playwright=createCheckCommand({...options,framework:'playwright',report:path.join(root,'new.xml')});
  const filePattern=new RegExp(playwright.args.at(-1));
  assert.equal(filePattern.test(path.join(root,test)),true);assert.equal(filePattern.test(path.join(root,test).replaceAll('\\','/')),true);assert.equal(filePattern.test(path.join(root,test)+'.other'),false);checks++;
  const jest=convertJestReport({testResults:[{name:path.join(root,'tests/jest.test.js'),assertionResults:[{fullName:'adds',status:'passed'},{fullName:'later',status:'todo'},{fullName:'broken',status:'failed'}]}]},root);
  assert.deepEqual(jest.tests.map(x=>x.status),['passed','skipped','failed']);assert.equal(jest.tests[0].id,'tests/jest.test.js::adds');checks++;
  expectThrow(()=>convertJestReport({testResults:[{name:'a',assertionResults:[{fullName:'x',status:'unknown'}]}]},root));
  console.log(JSON.stringify({suite:'Local framework adapters',passed:true,checks}));
}finally{
  const expected=path.resolve(os.tmpdir())+path.sep;
  if(!path.resolve(root).startsWith(expected)||!path.basename(root).startsWith('shadow-check-adapter-'))throw new Error('Unsafe cleanup path');
  fs.rmSync(root,{recursive:true,force:true});
}
