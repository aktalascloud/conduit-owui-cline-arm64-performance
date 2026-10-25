import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
import {fileURLToPath} from 'node:url';
import vm from 'node:vm';

const root = new URL('../', import.meta.url);
const pin = JSON.parse(readFileSync(new URL('.avx1/cline-protocol.json', root), 'utf8'));
let source;
if (process.argv[2]) source = readFileSync(process.argv[2], 'utf8');
else {
  const response = await fetch(pin.source);
  if (!response.ok) throw new Error('Pinned Cline contract source is unavailable');
  source = await response.text();
}
source = source.replaceAll('\r\n', '\n');
assert.equal(createHash('sha256').update(source).digest('hex'), pin.sha256_utf8_lf);

function sourceFunction(name) {
  const expression = new RegExp(`export (?:async )?function ${name}\\(`);
  const start = source.search(expression);
  assert.ok(start >= 0, `Missing actual Cline function: ${name}`);
  const rest = source.slice(start);
  const end = rest.indexOf('\n}\n') + 2;
  assert.ok(end > 1);
  return stripTypeScriptTypes(rest.slice(0, end).replace(/^export /, ''));
}
const scope = {
  providerSettingsManager: {getLastUsedProviderSettings: () => undefined},
  process: {env: {}}, workspaceRoot: '/synthetic/default',
};
vm.createContext(scope);
vm.runInContext(sourceFunction('resolveLaunchContext') + '\nthis.resolve = resolveLaunchContext;', scope);
const context = scope.resolve({}, {workspaceRoot: '/synthetic/project', cwd: '/synthetic/project',
  providerId: 'synthetic-provider', modelId: 'synthetic-model'});
assert.equal(context.workspaceRoot, '/synthetic/project');
let sent;
scope.createSession = () => { throw new Error('An existing session must not be replaced'); };
vm.runInContext(sourceFunction('sendMessage') + '\nthis.send = sendMessage;', scope);
await scope.send({cline: {send: async (input) => { sent = input; }}},
  {selectedSessionId: 'synthetic-existing'}, 'same prompt',
  {workspaceRoot: '/different', cwd: '/different', mode: 'plan'});
assert.equal(sent.sessionId, 'synthetic-existing');
assert.equal(sent.prompt, 'same prompt');
assert.equal(sent.workspaceRoot, undefined);

const dart = readFileSync(new URL('lib/features/cline/views/cline_remote_page.dart', root), 'utf8');
const start = dart.indexOf('\n(() => {');
const end = dart.indexOf("\n'''", start);
assert.ok(start >= 0 && end > start);
const bootstrap = dart.slice(start, end).replaceAll('\\\\', '\\')
  .replace('${jsonEncode(project)}', JSON.stringify('/synthetic/new-project'))
  .replace('${jsonEncode(roomSecret)}', JSON.stringify('synthetic-room-not-a-real-credential'));
class Socket {
  constructor(url) { this.url = url; this.sent = []; }
  send(value) { this.sent.push(value); }
}
const browser = {window: {WebSocket: Socket}, location: {host: '127.0.0.1:11280', href: 'http://127.0.0.1:11280/'}, URL, DOMException};
vm.runInNewContext(bootstrap, browser);
const socket = new browser.window.WebSocket('ws://127.0.0.1:11280/browser');
assert.equal(new URL(socket.url).searchParams.get('roomSecret'), 'synthetic-room-not-a-real-credential');
const approval = JSON.stringify({type: 'approval_response', approvalId: 'synthetic', approved: false});
socket.send(approval);
assert.equal(socket.sent.at(-1), approval);
socket.send(JSON.stringify({type: 'send', prompt: 'unmodified text', config: {autoApproveTools: false}}));
const frame = JSON.parse(socket.sent.at(-1));
assert.equal(frame.prompt, 'unmodified text');
assert.equal(frame.config.autoApproveTools, false);
assert.equal(frame.config.workspaceRoot, '/synthetic/new-project');
browser.window.__conduitPendingFiles = [{name:'example.pdf',path:'/synthetic/inbox/document.pdf',sha256:'0'.repeat(64),size:12},
  {name:'example.png',path:'/synthetic/inbox/image.png',sha256:'1'.repeat(64),size:16,image:'data:image/png;base64,c3ludGhldGlj'}];
socket.send(approval);
assert.equal(socket.sent.at(-1), approval);
assert.equal(browser.window.__conduitPendingFiles.length, 2, 'Approval must not consume files');
socket.send(JSON.stringify({type:'send',prompt:'read these files',attachments:{userImages:['data:image/png;base64,b2xk']}}));
const attachedFrame = JSON.parse(socket.sent.at(-1));
assert.ok(attachedFrame.prompt.startsWith('read these files\n\n[User attachments:'));
assert.ok(attachedFrame.prompt.includes('/synthetic/inbox/document.pdf'));
assert.deepEqual(attachedFrame.attachments.userImages,['data:image/png;base64,b2xk','data:image/png;base64,c3ludGhldGlj']);
assert.equal(browser.window.__conduitPendingFiles.length, 0);
let attempts = 0;
const originalSend = Socket.prototype.send;
Socket.prototype.send = function(value) { attempts++; throw new Error('Synthetic transport failure'); };
browser.window.__conduitPendingFiles = [{name:'example.txt',path:'/synthetic/inbox/file.txt',sha256:'0'.repeat(64),size:12}];
assert.throws(() => socket.send(JSON.stringify({type: 'send', prompt: 'once'})));
assert.equal(attempts, 1, 'A failed write must never replay the original agent command');
assert.equal(browser.window.__conduitPendingFiles.length, 0, 'Uncertain writes must not replay files');
Socket.prototype.send = originalSend;
assert.throws(() => new browser.window.WebSocket('ws://foreign.example/browser'));
console.log('CLINE_PINNED_SOURCE_PROJECT_CONTEXT_APPROVAL_AND_ORIGIN_CONTRACT_PASSED');
