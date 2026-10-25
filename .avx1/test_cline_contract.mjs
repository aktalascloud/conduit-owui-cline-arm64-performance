import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
import vm from 'node:vm';

const root=new URL('../',import.meta.url);
const pin=JSON.parse(readFileSync(new URL('.avx1/cline-protocol.json',root),'utf8'));
async function pinned(definition,local) {
  let source;
  if(local) source=readFileSync(local,'utf8');
  else {
    for(let attempt=0;attempt<3;attempt++) {
      try {const r=await fetch(definition.source);if(!r.ok)throw new Error('Pinned source unavailable');source=await r.text();break;}
      catch(error){if(attempt===2)throw error;await new Promise(r=>setTimeout(r,1000*(attempt+1)));}
    }
  }
  source=source.replaceAll('\r\n','\n');
  assert.equal(createHash('sha256').update(source).digest('hex'),definition.sha256_utf8_lf);
  return source;
}
const source=await pinned(pin,process.argv[2]);
const events=await pinned(pin.agent_events,process.argv[3]);
await pinned(pin.webview_protocol,process.argv[4]);
function actualFunction(source,name) {
  const start=source.search(new RegExp(`(?:export )?(?:async )?function ${name}\\(`));
  assert.ok(start>=0,`Missing Cline function: ${name}`);
  const rest=source.slice(start);const end=rest.indexOf('\n}\n')+2;
  assert.ok(end>1);return stripTypeScriptTypes(rest.slice(0,end).replace(/^export /,''));
}
const scope={providerSettingsManager:{getLastUsedProviderSettings:()=>undefined},process:{env:{}},
  workspaceRoot:'/synthetic/default',SessionSource:{WEB:'web'},frames:[]};
vm.createContext(scope);
vm.runInContext(actualFunction(source,'resolveLaunchContext')+'\nthis.resolve=resolveLaunchContext;',scope);
const context=scope.resolve({}, {workspaceRoot:'/synthetic/project',cwd:'/synthetic/project',provider:'local',model:'test-model'});
assert.equal(context.workspaceRoot,'/synthetic/project');assert.equal(context.providerId,'local');
vm.runInContext(actualFunction(source,'toRuntimeReasoningOptions')+'\n'+actualFunction(source,'buildSessionStartInput')+'\nthis.startInput=buildSessionStartInput;',scope);
const input=scope.startInput(context,{mode:'plan',autoApproveTools:false,reasonLevel:'none'});
assert.equal(input.toolPolicies['*'].autoApprove,false);
assert.equal(input.config.mode,'plan');assert.equal(input.config.thinking,false);
let sent;
scope.createSession=()=>{throw new Error('Existing session must not be replaced');};
vm.runInContext(actualFunction(source,'sendMessage')+'\nthis.send=sendMessage;',scope);
await scope.send({cline:{send:async(value)=>{sent=value;}}},{selectedSessionId:'existing'},'literal prompt',
  {mode:'plan',workspaceRoot:'/must-not-replace',provider:'other',model:'other'},
  {userImages:['data:image/png;base64,c3ludGhldGlj']});
assert.equal(sent.sessionId,'existing');assert.equal(sent.prompt,'literal prompt');
assert.equal(sent.workspaceRoot,undefined);assert.equal(sent.providerId,undefined);assert.equal(sent.modelId,undefined);
assert.equal(sent.mode,'plan');assert.equal(sent.userImages.length,1);

scope.context={sendToSelectedPeers:(_id,frame)=>scope.frames.push(frame)};
vm.runInContext(['agentEventText','sendChunkToSelectedPeers','forwardAgentEvent'].map(n=>actualFunction(events,n)).join('\n')+'\nthis.forward=forwardAgentEvent;',scope);
for(const event of [
  {type:'content_start',contentType:'text',text:'Before tool'},
  {type:'content_start',contentType:'reasoning',reasoning:'Synthetic reasoning'},
  {type:'content_start',contentType:'tool',toolCallId:'tool-1',toolName:'read_files',input:{path:'/synthetic/example.txt'}},
  {type:'content_update',contentType:'tool',toolCallId:'tool-1',toolName:'read_files',update:'progress'},
  {type:'content_end',contentType:'tool',toolCallId:'tool-1',toolName:'read_files',output:'result'},
  {type:'content_start',contentType:'text',text:'After tool'},
  {type:'done',reason:'stop',iterations:1,usage:{inputTokens:2,outputTokens:3}},
  {type:'error',error:{message:'Recoverable synthetic notice'},recoverable:true},
]) scope.forward(scope.context,'synthetic-session',event);
assert.deepEqual(Array.from(scope.frames,f=>f.type),['assistant_delta','reasoning_delta','tool_event','tool_event','tool_event','assistant_delta','turn_done','error']);
assert.equal(scope.frames[4].event.status,'completed');assert.equal(scope.frames.at(-1).recoverable,true);
assert.deepEqual(JSON.parse(readFileSync(new URL('.avx1/cline-native-events.json',root),'utf8')),JSON.parse(JSON.stringify(scope.frames)));
const workspace=new URL('.avx1-work/',root);mkdirSync(workspace,{recursive:true});
writeFileSync(new URL('cline-native-events.json',workspace),JSON.stringify(scope.frames,null,2)+'\n');
const dart=readFileSync(new URL('lib/features/cline/views/cline_remote_page.dart',root),'utf8');
assert.ok(!dart.includes('InAppWebView')&&!dart.includes('ClineDashboardPage'),'Cline must use the native client');
assert.ok(readFileSync(new URL('lib/features/cline/views/cline_workspace_page.dart',root),'utf8').includes('StreamingMarkdownWidget'));
console.log('CLINE_NATIVE_CONTEXT_APPROVAL_AND_PINNED_EVENT_CONTRACT_PASSED');
