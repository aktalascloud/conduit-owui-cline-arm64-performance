"""Loopback-only interoperability fixture; never loads a Cline profile."""
import asyncio
import json
from pathlib import Path
import sys
import tempfile
import base64
import hashlib
import struct
import urllib.parse
import cline_gateway as gateway

async def ws_send(writer,frame):
    body=json.dumps(frame).encode()
    length=len(body)
    header=bytes([0x81,length]) if length<126 else b'\x81\x7e'+struct.pack('>H',length)
    writer.write(header+body);await writer.drain()

async def ws_read(reader):
    header=await reader.readexactly(2);length=header[1]&127
    if length==126:length=struct.unpack('>H',await reader.readexactly(2))[0]
    if length==127:length=struct.unpack('>Q',await reader.readexactly(8))[0]
    if length>32768:raise ValueError('Oversized fixture frame')
    mask=await reader.readexactly(4) if header[1]&128 else None
    body=await reader.readexactly(length)
    if mask:body=bytes(value^mask[i%4] for i,value in enumerate(body))
    return header[0]&15,body

async def main():
    with tempfile.TemporaryDirectory() as directory:
        root=Path(directory)
        config=gateway.prepare(root,root/'unused',root,root)
        config['password']='synthetic-ssh-test-password-not-a-real-credential'
        config['room_secret']='synthetic-dashboard-test-secret-not-a-real-credential'
        async def http(reader,writer):
            try:
                request=(await reader.readuntil(b'\r\n\r\n')).decode('ascii')
                lines=request.split('\r\n');path=lines[0].split(' ')[1]
                headers=dict((line.split(':',1)[0].lower(),line.split(':',1)[1].strip()) for line in lines[1:] if ':' in line)
                if urllib.parse.urlsplit(path).path=='/browser':
                    expected='127.0.0.1:'+str(config['dashboard_port'])
                    query=urllib.parse.parse_qs(urllib.parse.urlsplit(path).query)
                    if headers.get('host')!=expected or headers.get('origin')!='http://'+expected or query.get('roomSecret')!=[config['room_secret']]:
                        writer.write(b'HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n');await writer.drain();return
                    accept=base64.b64encode(hashlib.sha1((headers['sec-websocket-key']+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest())
                    writer.write(b'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: '+accept+b'\r\n\r\n');await writer.drain()
                    while True:
                        opcode,body=await ws_read(reader)
                        if opcode==8:writer.write(b'\x88\x00');await writer.drain();return
                        if opcode==9:writer.write(bytes([0x8a,len(body)])+body);await writer.drain();continue
                        frame=json.loads(body)
                        if frame['type']=='ready':
                            for reply in [
                                {'type':'defaults','defaults':{'provider':'fixture','model':'fixture-model','workspaceRoot':'/synthetic'}},
                                {'type':'providers','providers':[{'id':'fixture','name':'Fixture','enabled':True}]},
                                {'type':'models','providerId':'fixture','models':[{'id':'fixture-model','name':'Fixture model','operation':'language'}]},
                                {'type':'sessions','sessions':[{'sessionId':'fixture-session','title':'Fixture session','workspaceRoot':'/synthetic','status':'completed'}]},
                                {'type':'hub_state','connected':True},
                            ]:await ws_send(writer,reply)
                        elif frame['type']=='attachSession':
                            await ws_send(writer,{'type':'session_started','sessionId':frame['sessionId']})
                            await ws_send(writer,{'type':'session_hydrated','sessionId':frame['sessionId'],'status':'completed',
                                'providerId':'fixture','modelId':'fixture-model','messages':[{'id':'message-1','role':'assistant','text':'Native fixture history'}]})
                        elif frame['type']=='desktopCommand':await ws_send(writer,{'type':'desktopCommandResult','id':frame['id'],'ok':True,'result':[]})
                        elif frame['type']=='send':
                            await ws_send(writer,{'type':'assistant_delta','text':'Native synthetic response'})
                            await ws_send(writer,{'type':'turn_done','finishReason':'stop','iterations':1})
                    return
                body=b'conduit-cline-encrypted-transport-ok'
                writer.write(b'HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: '+str(len(body)).encode()+b'\r\n\r\n'+body)
                await writer.drain()
            except (asyncio.IncompleteReadError,ConnectionError):pass
            finally:writer.close();await writer.wait_closed()
        target=await asyncio.start_server(http,'127.0.0.1',0)
        config['dashboard_port']=target.sockets[0].getsockname()[1]
        probe=await asyncio.start_server(http,'127.0.0.1',0)
        config['ssh_port']=probe.sockets[0].getsockname()[1]
        probe.close();await probe.wait_closed()
        server=await gateway.listen(config)
        try:
            print(json.dumps(gateway.client_profile(config,'127.0.0.1')),flush=True)
            await asyncio.to_thread(sys.stdin.buffer.read)
        finally:
            server.close();await server.wait_closed()
            target.close();await target.wait_closed()

if __name__=='__main__':asyncio.run(main())
