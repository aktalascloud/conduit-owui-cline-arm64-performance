"""Loopback-only interoperability fixture; never loads a Cline profile."""
import asyncio
import json
from pathlib import Path
import sys
import tempfile
import cline_gateway as gateway

async def main():
    with tempfile.TemporaryDirectory() as directory:
        root=Path(directory)
        config=gateway.prepare(root,root/'unused',root,root)
        config['password']='synthetic-ssh-test-password-not-a-real-credential'
        config['room_secret']='synthetic-dashboard-test-secret-not-a-real-credential'
        async def http(reader,writer):
            try:
                await reader.readuntil(b'\r\n\r\n')
                body=b'conduit-cline-encrypted-transport-ok'
                writer.write(b'HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: '+str(len(body)).encode()+b'\r\n\r\n'+body)
                await writer.drain()
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
