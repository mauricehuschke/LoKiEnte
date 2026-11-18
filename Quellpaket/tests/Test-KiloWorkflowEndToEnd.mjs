// Invoked by the PowerShell fixture. Real bridge, worker, runner, Git and Node
// assertions; only model responses and Kilo's permission prompt are synthetic.
import assert from 'node:assert/strict';
import {promises as fs} from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
const [root,project,callsFile]=process.argv.slice(2);
assert.ok(root&&project&&callsFile,'Use Test-KiloWorkflowEndToEnd.ps1 to create the isolated fixture');
const {createWorkflowTools,TERMINAL_STATES,lockName,samePath}=await import(pathToFileURL(path.join(root,'app','KiloWorkflowTools.mjs')).href);
const tools=createWorkflowTools({installRoot:root,pollMilliseconds:250});
const permissions=[];
const context={directory:project,sessionID:'e2e-parent-chat',abort:new AbortController().signal,ask:async value=>permissions.push(value.permission)};
const readJson=async file=>JSON.parse(await fs.readFile(file,'utf8'));
const task='Fix app.cjs so that the function returns two. Add an independent regression test, preserve all other behavior and user work.';
let runId,state,checks=0;
try{
  const initial=await tools.startTool.execute({task},context);
  runId=/Auftrag: `([a-f0-9-]{36})`/.exec(initial)?.[1];
  assert.ok(runId,initial);assert.match(initial,/QUEUED/);checks++;
  const job=path.join(root,'workflow-jobs',runId);
  const request=await readJson(path.join(job,'request.json'));
  assert.ok(samePath(request.project,project));assert.equal(request.parentSessionId,context.sessionID);assert.equal(await fs.readFile(path.join(job,'task.md'),'utf8'),task);checks++;
  const deadline=Date.now()+180000;
  while(Date.now()<deadline){
    state=await readJson(path.join(job,'status.json'));
    if(TERMINAL_STATES.has(state.status))break;
    await tools.statusTool.execute({runId},context);
  }
  if(state?.status!=='VERIFIED'){
    const details=await tools.detailsTool.execute({runId},context);
    throw new Error('Bridge did not produce VERIFIED: '+details);
  }
  assert.equal(state.exitCode,0);checks++;
  const receipt=await readJson(state.receiptPath);
  assert.equal(receipt.request_id,runId);assert.ok(samePath(receipt.project,project));assert.equal(receipt.status,'VERIFIED');assert.match(receipt.final_fingerprint,/^[0-9a-f]{64}$/);checks++;
  const calls=(await fs.readFile(callsFile,'utf8')).trim().split(/\r?\n/).map(JSON.parse);
  const expected=['shadow-preparer','shadow-preparation-reviewer','shadow-architect','shadow-test','shadow-test-reviewer','shadow-implementer','shadow-reviewer','shadow-validator'];
  assert.deepEqual(calls.map(call=>call.role),expected);checks++;
  assert.equal(calls.find(call=>call.role==='shadow-preparation-reviewer').model,'lmstudio/review');assert.equal(calls.find(call=>call.role==='shadow-implementer').model,'lmstudio/coder-high');checks++;
  const saved=await readJson(request.checksFile);
  assert.equal(saved.custom,'preserve me');assert.equal(saved.automation.owner,'LoKi task preparation v1');assert.equal(saved.acceptanceCriteria[0].id,'AC-1');assert.equal(saved.checks[0].name,'loki-node-test');checks++;
  assert.ok(samePath(saved.checks[0].arguments[0],path.join(root,'app','Run-ProjectCheck.mjs')));assert.ok(saved.checks[0].arguments.includes('tests/app.test.cjs'));assert.equal(saved.checks[0].reportFormat,'junit');checks++;
  assert.equal(receipt.baseline_checks[0].Report.Failed,1);assert.equal(receipt.rounds.at(-1).checks[0].Report.Passed,1);checks++;
  assert.equal(receipt.preparation_review.Verdict.verdict,'PASS');assert.equal(receipt.test_review.Verdict.verdict,'PASS');assert.ok(receipt.frozen_test_hashes['tests/app.test.cjs']);checks++;
  assert.equal(await fs.readFile(path.join(project,'app.cjs'),'utf8'),'module.exports=()=>2;');assert.match(await fs.readFile(path.join(project,'tests/app.test.cjs'),'utf8'),/node:test/);checks++;
  const visible=state.phaseSummary??state.events;
  assert.ok(expected.every(role=>visible.some(event=>event.role===role)),JSON.stringify(visible));
  for(const role of expected)assert.equal(visible.find(event=>event.role===role).model,calls.find(call=>call.role===role).model,'Visible model differs for '+role);checks++;
  assert.match(await fs.readFile(path.join(request.stateDirectory,'LOKI-STATUS.md'),'utf8'),/VERIFIED/);assert.match(await tools.detailsTool.execute({runId},context),/Pruefergebnis/);checks++;
  await assert.rejects(fs.stat(path.join(root,'workflow-jobs','locks',lockName(project))),{code:'ENOENT'});
  assert.ok(['loki_start','loki_status','loki_details'].every(permission=>permissions.includes(permission)));checks++;
  console.log(JSON.stringify({suite:'Kilo chat to real reviewed workflow',passed:true,checks,limitations:'Synthetic Kilo/model responses; actual worker, runner, Git and Node red/green assertions. No GUI/model inference.'}));
}finally{
  if(runId)state=await readJson(path.join(root,'workflow-jobs',runId,'status.json'));
  if(runId&&state&&!TERMINAL_STATES.has(state.status)){
    await tools.cancelTool.execute({runId},context);
    const until=Date.now()+30000;
    while(Date.now()<until){
      state=await readJson(path.join(root,'workflow-jobs',runId,'status.json'));
      if(TERMINAL_STATES.has(state.status))break;
      await tools.statusTool.execute({runId},context);
    }
  }
}
