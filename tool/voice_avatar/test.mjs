import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {readAvatar,mouthWeight,renderPixelRatio,fullBodyDistance} from './renderer.js';
import {textureResizePlan,boundedBitmapLoader} from './texture-loader.js';

test('full-body framing fits head, feet and width on tall and wide viewports',()=>{
 for(const aspect of [.45,.7,1,2]) {
  const distance=fullBodyDistance(.8,1.85,.4,aspect);
  const visibleHalfHeight=(distance-.2)*Math.tan(Math.PI/12);
  assert.ok(visibleHalfHeight>1.85/2);assert.ok(visibleHalfHeight*aspect>.8/2);
 }
});

test('large source textures fit a bounded GPU budget without upscaling',async()=>{
 const sizes=[{width:8192,height:8192},{width:4096,height:4096}];
 const plans=textureResizePlan(sizes);
 assert.ok(plans.reduce((n,p)=>n+p.width*p.height,0)<=32*1024*1024);
 assert.ok(plans.every(p=>p.width<=4096&&p.height<=4096));
 assert.deepEqual(textureResizePlan([{width:128,height:256}]),[{width:128,height:256}]);
 await new Promise(resolve=>boundedBitmapLoader([]).load('https://example.invalid',()=>assert.fail('Remote image loaded'),null,error=>{assert.match(error.message,/blocked/);resolve();}));
});

test('phone density stays sharp within bounded GPU buffer dimensions',()=>{
 assert.equal(renderPixelRatio(3,360,230),3);
 assert.equal(renderPixelRatio(4,360,230),3);
 assert.equal(renderPixelRatio(1,360,230),1);
 assert.equal(renderPixelRatio(undefined,360,230),1);
 for(const [w,h,max] of [[2000,1500,4096],[5000,100,2048],[360,230,1024]]) {
  const r=renderPixelRatio(4,w,h,max);
  assert.ok(w*h*r*r<=2_000_001);assert.ok(w*r<=max);assert.ok(h*r<=max);
 }
});

test('standard TTS animates only during actual playback; metered silence stays closed',()=>{
 assert.equal(mouthWeight(1,{speaking:false,metered:false}),0);
 assert.equal(mouthWeight(1,{speaking:true,metered:true,level:0}),0);
 assert.equal(mouthWeight(1,{speaking:true,metered:true,level:.6}),.6);
 const a=mouthWeight(1,{speaking:true,metered:false,level:0});
 const b=mouthWeight(1.1,{speaking:true,metered:false,level:0});
 assert.ok(a>0&&b>0&&a!==b);
 assert.equal(mouthWeight(1,{speaking:false,metered:true,level:10}),0);
});

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
