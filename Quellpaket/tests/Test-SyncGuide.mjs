import test from 'node:test';
import assert from 'node:assert/strict';
import guide from '../vscode-startup/sync-guide.cjs';

function fixture({seen=0,choice,available=true,fail=false,wait}={}){
  const messages=[],calls=[],warnings=[],lines=[],registered=new Map(),state=new Map([['extensionSyncGuideVersion',seen]]);
  const context={subscriptions:[],globalState:{get:(key,fallback)=>state.get(key)??fallback,async update(key,value){assert.equal(key,'extensionSyncGuideVersion');state.set(key,value);await wait;}}};
  const vscode={window:{async showInformationMessage(text){messages.push(text);return choice;},async showWarningMessage(text){warnings.push(text);}},
    commands:{registerCommand(id,handler){registered.set(id,handler);return {dispose(){}};},async getCommands(){return available?['workbench.userDataSync.actions.configure']:[];},async executeCommand(id){calls.push(id);if(fail)throw new Error('Unavailable');}}};
  const output={info:text=>lines.push(text),warn:text=>warnings.push(text)};
  return {context,state,messages,calls,warnings,lines,registered,run:()=>guide.registerSyncGuide(vscode,context,output)};
}
test('initial hint explains extension-only selection without changing sync or settings',async()=>{
  const f=fixture();await f.run();assert.equal(f.messages.length,1);assert.deepEqual(f.calls,[]);
  assert.match(f.messages[0],/select Extensions and deselect every other category/);
  assert.equal(f.state.get('extensionSyncGuideVersion'),1);
  assert.equal(f.registered.has('lokiente.configureExtensionSync'),true);
});
test('acknowledged hint is not repeated on later starts',async()=>{
  const f=fixture({seen:1});await f.run();assert.deepEqual(f.messages,[]);assert.deepEqual(f.calls,[]);
});
test('explicit button opens only the supported VS Code configuration UI',async()=>{
  const f=fixture({choice:'Open Sync Options'});await f.run();
  assert.deepEqual(f.calls,['workbench.userDataSync.actions.configure']);
  assert.ok(f.lines.some(line=>line.includes('cannot verify the selected categories')));
});
test('manual command remains available after dismissing the hint',async()=>{
  const f=fixture({seen:1});await f.run();await f.registered.get('lokiente.configureExtensionSync')();
  assert.equal(f.messages.length,1);assert.deepEqual(f.calls,['workbench.userDataSync.actions.configure']);
});
for(const [name,options] of [['missing command',{available:false}],['failed command',{fail:true}]]){
  test(`${name} reports that no sync choices were changed`,async()=>{
    const f=fixture({...options,choice:'Open Sync Options'});await f.run();
    assert.ok(f.warnings.some(line=>line.includes('has not changed your sync choices')));
  });
}
test('closing the window while recording the hint prevents late UI changes',async()=>{
  let release;const wait=new Promise(resolve=>{release=resolve;});const f=fixture({wait});const pending=f.run();
  for(const item of f.context.subscriptions)item.dispose();release();await pending;
  assert.deepEqual(f.calls,[]);assert.deepEqual(f.messages,[]);
});
