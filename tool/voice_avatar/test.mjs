import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {readAvatar} from './renderer.js';

function fixture(change=()=>{}) {
 const bones=['hips','spine','head','leftUpperArm','rightUpperArm','leftLowerArm','rightLowerArm'];
 const j={nodes:bones.map(name=>({name})),extensions:{VRM:{humanoid:{humanBones:bones.map((bone,node)=>({bone,node}))}}},buffers:[{byteLength:4}]};
 change(j);
 let text=JSON.stringify(j);text+=' '.repeat((4-text.length%4)%4);
 const raw=Buffer.from(text),data=Buffer.alloc(raw.length+32);
 [0x46546c67,2,data.length,raw.length,0x4e4f534a].forEach((v,i)=>data.writeUInt32LE(v,i*4));
 raw.copy(data,20);data.writeUInt32LE(4,20+raw.length);data.writeUInt32LE(0x004e4942,24+raw.length);
 return data.buffer.slice(data.byteOffset,data.byteOffset+data.length);
}
test('accepts only bounded embedded rigged GLBs',()=>{
 assert.ok(readAvatar(fixture()));
 for(const change of [j=>{j.buffers[0].uri='https://evil.invalid/x';},
   j=>{j.images=[{uri:'file:///private/key'}];},
   j=>{j.nodes=Array(513).fill({});},
   j=>{j.extensions.VRM.humanoid.humanBones=[];},
   j=>{j.accessors=[{count:5_000_001}];},
   j=>{j.images=[{bufferView:0,mimeType:'image/svg+xml'}];j.bufferViews=[{buffer:0,byteLength:4}];}])
   assert.throws(()=>readAvatar(fixture(change)));
 const data=fixture();new DataView(data).setUint32(8,1,true);assert.throws(()=>readAvatar(data));
 assert.throws(()=>readAvatar(new ArrayBuffer(26*1024*1024)));
});
test('offline bundle has a matching CSP hash and no credential or network bridge',()=>{
 const html=readFileSync('../../assets/voice_avatar/viewer.html','utf8');
 const js=html.match(/<script>([\s\S]*)<\/script>/)[1];
 const hash=createHash('sha256').update(js).digest('base64');
 assert.ok(html.includes(`script-src 'sha256-${hash}'`));
 assert.ok(html.includes("connect-src blob:"));
 assert.ok(html.includes("frame-src 'none'"));
 assert.ok(!html.includes('unsafe-eval'));
 assert.ok(!js.includes('callHandler('));
});
