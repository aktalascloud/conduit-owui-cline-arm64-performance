import asyncio
import json
import hashlib
import struct
from pathlib import Path
import tempfile
import unittest

import asyncssh
import cline_gateway as gateway


class GatewayTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.temp=tempfile.TemporaryDirectory()
        root=Path(self.temp.name)
        self.config=gateway.prepare(root,root/'cli',root,root/'profile')
        async def echo(reader,writer):
            try:
                writer.write(await reader.read(128));await writer.drain()
            finally:writer.close();await writer.wait_closed()
        self.target=await asyncio.start_server(echo,'127.0.0.1',0)
        self.config['dashboard_port']=self.target.sockets[0].getsockname()[1]
        # A test-only ephemeral listen port; production config requires >=1024.
        probe=await asyncio.start_server(echo,'127.0.0.1',0)
        self.config['ssh_port']=probe.sockets[0].getsockname()[1]
        probe.close();await probe.wait_closed()
        self.server=await gateway.listen(self.config)
        self.known=asyncssh.import_public_key(asyncssh.read_private_key(self.config['host_key_file']).export_public_key())

    async def asyncTearDown(self):
        self.server.close();await self.server.wait_closed()
        self.target.close();await self.target.wait_closed();self.temp.cleanup()

    async def connect(self,password=None):
        return await asyncssh.connect('127.0.0.1',self.config['ssh_port'],username='cline',
            password=password or self.config['password'],known_hosts=([self.known],[],[]))

    async def test_authenticated_forward_preserves_bytes(self):
        async with await self.connect() as connection:
            reader,writer=await connection.open_connection('127.0.0.1',self.config['dashboard_port'])
            writer.write(b'synthetic-stream');await writer.drain()
            self.assertEqual(await reader.read(),b'synthetic-stream')
            writer.close();await writer.wait_closed()

    async def test_wrong_secret_is_rejected(self):
        with self.assertRaises(asyncssh.PermissionDenied):await self.connect('wrong-synthetic-secret')

    async def test_shell_sftp_other_ports_and_reverse_forward_are_rejected(self):
        async with await self.connect() as connection:
            for host,port in [('127.0.0.1',1),('example.com',443)]:
                with self.assertRaises(asyncssh.ChannelOpenError):await connection.open_connection(host,port)
            self.assertEqual((await connection.run('echo denied')).exit_status,126)
            with self.assertRaises(asyncssh.ChannelOpenError):await connection.start_sftp_client()
            with self.assertRaises(asyncssh.ChannelListenError):await connection.forward_remote_port('127.0.0.1',0,'127.0.0.1',80)

    async def upload(self, connection, name, content, *, sha=None, extra=b''):
        process=await connection.create_process('conduit-upload-v1',encoding=None)
        header=json.dumps({'name':name,'size':len(content),'sha256':sha or hashlib.sha256(content).hexdigest()}).encode()
        process.stdin.write(struct.pack('>I',len(header))+header)
        first=json.loads(await process.stdout.readline())
        if first['status']=='ready':
            process.stdin.write(content+extra);process.stdin.write_eof()
            first=json.loads(await process.stdout.readline())
        await process.wait()
        return first

    async def test_document_upload_is_verified_and_deduplicated(self):
        async with await self.connect() as connection:
            content='Пример документа'.encode()
            first=await self.upload(connection,'example.txt',content)
            self.assertEqual(first['status'],'stored')
            self.assertEqual(Path(first['path']).read_bytes(),content)
            again=await self.upload(connection,'other-name.txt',content)
            self.assertEqual(again['path'],first['path'])
            self.assertEqual(len(list(Path(first['path']).parent.iterdir())),1)

    async def test_upload_rejects_paths_executables_and_digest_mismatch(self):
        async with await self.connect() as connection:
            for name in ('../escape.txt','C:\\escape.txt','run.exe','file.ps1'):
                self.assertEqual((await self.upload(connection,name,b'synthetic'))['status'],'rejected')
            self.assertEqual((await self.upload(connection,'ok.txt',b'synthetic',sha='0'*64))['status'],'rejected')
        self.assertEqual(list((Path(self.temp.name)/'user-uploads').glob('*')),[])

    async def test_upload_rejects_extra_bytes_and_cleans_partial(self):
        async with await self.connect() as connection:
            self.assertEqual((await self.upload(connection,'ok.pdf',b'synthetic',extra=b'x'))['status'],'rejected')
        self.assertEqual(list((Path(self.temp.name)/'user-uploads').glob('*')),[])

    async def test_upload_rejects_oversized_declared_content_before_transfer(self):
        async with await self.connect() as connection:
            async with connection.create_process('conduit-upload-v1',encoding=None) as process:
                header=json.dumps({'name':'ok.pdf','size':64*1024*1024+1,'sha256':'0'*64}).encode()
                process.stdin.write(struct.pack('>I',len(header))+header)
                self.assertEqual(json.loads(await process.stdout.readline())['status'],'rejected')

    async def test_preparation_reuses_identity_and_profile_matches_pin(self):
        root=Path(self.temp.name)
        again=gateway.prepare(root,root/'different-cli',root,root/'profile')
        self.assertEqual(again['password'],self.config['password'])
        profile=gateway.client_profile(again,'host.example')
        self.assertEqual(profile['hostKeyFingerprint'],self.known.get_fingerprint('sha256'))
        self.assertNotEqual(profile['roomSecret'],profile['sshPassword'])

    def test_auth_rate_and_memory_are_bounded(self):
        admission=gateway.Admission()
        for _ in range(6):admission.failed('synthetic')
        self.assertTrue(admission.blocked('synthetic'))
        for i in range(2000):admission.failed(str(i))
        self.assertLessEqual(len(admission.failures),1024)

    def test_nat_external_port_does_not_change_the_local_listener(self):
        local=self.config['ssh_port']
        self.config['public_ssh_port']=49123
        gateway.validate_config(self.config)
        self.assertEqual(gateway.client_profile(self.config,'host.example')['sshPort'],49123)
        self.assertEqual(self.config['ssh_port'],local)

    def test_idle_logins_per_source_are_bounded(self):
        admission=gateway.Admission()
        self.assertTrue(admission.enter('synthetic-peer'))
        self.assertTrue(admission.enter('synthetic-peer'))
        self.assertFalse(admission.enter('synthetic-peer'))
        self.assertTrue(admission.enter('other-peer'))
        admission.end_pending('synthetic-peer')
        self.assertTrue(admission.enter('synthetic-peer'))


if __name__=='__main__':unittest.main()
