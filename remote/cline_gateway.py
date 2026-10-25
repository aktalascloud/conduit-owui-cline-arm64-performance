"""Password-authenticated SSH tunnel to a loopback-only Cline dashboard.

No SSH shell, SFTP, remote forwarding, or arbitrary TCP destinations are enabled.
Configuration, host keys and client profiles belong outside the source checkout.
"""
from __future__ import annotations

import argparse
import asyncio
from collections import OrderedDict
import contextlib
import hmac
import ipaddress
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import threading
import time

import asyncssh
from upload_rpc import UploadInbox


def dashboard_lifetime_guard(process):
    """Kill only this dashboard when the gateway exits, including abrupt exits.

    Shared Hub/spoke children may break away; the gateway never owns them.
    """
    if os.name != 'nt':return None
    import ctypes
    from ctypes import wintypes as w
    class Basic(ctypes.Structure):
        _fields_=[('process_time',ctypes.c_longlong),('job_time',ctypes.c_longlong),
            ('flags',w.DWORD),('minimum',ctypes.c_size_t),('maximum',ctypes.c_size_t),
            ('active',w.DWORD),('affinity',ctypes.c_size_t),('priority',w.DWORD),('scheduling',w.DWORD)]
    class Limits(ctypes.Structure):
        _fields_=[('basic',Basic),('io',ctypes.c_ulonglong*6),('process_memory',ctypes.c_size_t),
            ('job_memory',ctypes.c_size_t),('peak_process',ctypes.c_size_t),('peak_job',ctypes.c_size_t)]
    kernel=ctypes.WinDLL('kernel32',use_last_error=True)
    kernel.CreateJobObjectW.argtypes=[ctypes.c_void_p,w.LPCWSTR];kernel.CreateJobObjectW.restype=w.HANDLE
    kernel.SetInformationJobObject.argtypes=[w.HANDLE,ctypes.c_int,ctypes.c_void_p,w.DWORD]
    kernel.AssignProcessToJobObject.argtypes=[w.HANDLE,w.HANDLE]
    kernel.CloseHandle.argtypes=[w.HANDLE]
    handle=kernel.CreateJobObjectW(None,None)
    limits=Limits();limits.basic.flags=0x2000|0x1000
    if not handle:raise RuntimeError('Dashboard lifetime guard could not be created')
    if not kernel.SetInformationJobObject(handle,9,ctypes.byref(limits),ctypes.sizeof(limits)) or not kernel.AssignProcessToJobObject(handle,w.HANDLE(int(process._handle))):
        kernel.CloseHandle(handle)
        raise RuntimeError('Dashboard lifetime guard could not be attached')
    return lambda:kernel.CloseHandle(handle)


class Admission:
    def __init__(self, maximum: int = 12):
        self.maximum = maximum
        self.active = 0
        self.pending: dict[str,int] = {}
        self.failures: OrderedDict[str, tuple[int, float]] = OrderedDict()

    def blocked(self, peer: str) -> bool:
        count, start = self.failures.get(peer, (0, time.monotonic()))
        if time.monotonic() - start >= 300:
            self.failures.pop(peer, None)
            return False
        return count >= 6

    def failed(self, peer: str) -> None:
        count, start = self.failures.pop(peer, (0, time.monotonic()))
        self.failures[peer] = (count + 1, start)
        while len(self.failures) > 1024:
            self.failures.popitem(last=False)

    def enter(self, peer):
        if self.active >= self.maximum or self.pending.get(peer,0) >= 2 or self.blocked(peer):
            return False
        self.active += 1
        self.pending[peer]=self.pending.get(peer,0)+1
        return True

    def end_pending(self, peer):
        remaining=self.pending.get(peer,0)-1
        if remaining > 0:self.pending[peer]=remaining
        else:self.pending.pop(peer,None)


class TunnelServer(asyncssh.SSHServer):
    def __init__(self, config: dict, admission: Admission):
        self.config = config
        self.admission = admission
        self.peer = ''
        self.accepted = False
        self.authenticated = False
        self.attempts = 0
        self.connection = None

    def connection_made(self, connection):
        self.connection = connection
        self.peer = str(connection.get_extra_info('peername')[0])
        if not self.admission.enter(self.peer):
            connection.abort()
            return
        self.accepted = True

    def connection_lost(self, exc):
        if self.accepted:
            self.admission.active -= 1
            if not self.authenticated:self.admission.end_pending(self.peer)
            self.accepted = False

    def begin_auth(self, username):
        return True

    def password_auth_supported(self):
        return True

    def validate_password(self, username, password):
        if not self.accepted or self.admission.blocked(self.peer):
            return False
        valid = username == 'cline' and hmac.compare_digest(
            password.encode('utf-8'), self.config['password'].encode('utf-8'))
        if not valid:
            self.attempts += 1
            self.admission.failed(self.peer)
            if self.attempts >= 3:
                self.connection.abort()
        return valid

    def auth_completed(self):
        self.authenticated = True
        self.admission.end_pending(self.peer)
        self.admission.failures.pop(self.peer, None)

    def session_requested(self):
        return False

    def connection_requested(self, dest_host, dest_port, orig_host, orig_port):
        return self.authenticated and dest_host == '127.0.0.1' and dest_port == self.config['dashboard_port']

    def server_requested(self, listen_host, listen_port):
        return False


def validate_config(config: dict) -> dict:
    if config.get('schema') != 1:
        raise ValueError('Unsupported gateway configuration')
    ipaddress.ip_address(config['bind_host'])
    for key in ('ssh_port', 'dashboard_port'):
        if type(config[key]) is not int or not 1024 <= config[key] <= 65535:
            raise ValueError('Invalid gateway port')
    if 'public_ssh_port' in config and (type(config['public_ssh_port']) is not int or not 1024 <= config['public_ssh_port'] <= 65535):
        raise ValueError('Invalid public SSH port')
    if config['ssh_port'] == config['dashboard_port']:
        raise ValueError('The SSH and dashboard ports must differ')
    for key in ('password', 'room_secret'):
        if not isinstance(config[key], str) or len(config[key]) < 32:
            raise ValueError('Generate independent strong gateway secrets')
    if config['password'] == config['room_secret']:
        raise ValueError('Gateway and dashboard secrets must differ')
    return config


async def listen(config: dict, admission=None):
    validate_config(config)
    admission = admission or Admission()
    inbox = UploadInbox(Path(config['host_key_file']).parent/'user-uploads')
    return await asyncssh.create_server(
        lambda: TunnelServer(config, admission), config['bind_host'], config['ssh_port'],
        server_host_keys=[config['host_key_file']],
        login_timeout=15, keepalive_interval=30,
        keepalive_count_max=3, kex_algs=['curve25519-sha256', 'curve25519-sha256@libssh.org'],
        encryption_algs=['chacha20-poly1305@openssh.com', 'aes256-gcm@openssh.com', 'aes128-gcm@openssh.com'],
        compression_algs=['none'], server_version='Conduit-Cline-Tunnel',
        process_factory=inbox.handle, encoding=None, allow_pty=False,
    )


def prepare(directory: Path, cli: Path, workspace: Path, config_dir: Path,
            *, bind_host='127.0.0.1', ssh_port=2222, dashboard_port=11280):
    directory.mkdir(parents=True, exist_ok=True)
    path = directory/'server.json'
    if path.exists():
        return validate_config(json.loads(path.read_text('utf-8')))
    key_file = directory/'host_ed25519'
    if not key_file.exists():
        key_file.write_bytes(asyncssh.generate_private_key('ssh-ed25519').export_private_key())
        key_file.chmod(0o600)
    config = validate_config({'schema':1,'bind_host':bind_host,'ssh_port':ssh_port,
        'dashboard_port':dashboard_port,'password':secrets.token_urlsafe(32),
        'room_secret':secrets.token_urlsafe(32),'host_key_file':str(key_file.resolve()),
        'cline_cli':str(cli.resolve()),'workspace_root':str(workspace.resolve()),
        'cline_config_dir':str(config_dir.resolve())})
    path.write_text(json.dumps(config, indent=2)+'\n', encoding='utf-8')
    path.chmod(0o600)
    return config


def client_profile(config: dict, host: str) -> dict:
    key = asyncssh.read_private_key(config['host_key_file'])
    return {'schema':1,'name':'Cline Desktop','host':host,'sshPort':config.get('public_ssh_port',config['ssh_port']),
        'username':'cline','sshPassword':config['password'],
        'hostKeyFingerprint':key.get_fingerprint('sha256'),
        'dashboardPort':config['dashboard_port'],'roomSecret':config['room_secret'],
        'projectPath':config.get('workspace_root','')}


async def run(config: dict, state: Path):
    validate_config(config)
    cli = Path(config['cline_cli'])
    if not cli.is_file():
        raise RuntimeError('Configured installed Cline CLI does not exist')
    with socket.socket() as probe:
        try:probe.bind(('127.0.0.1',config['dashboard_port']))
        except OSError:raise RuntimeError('Dashboard port is already owned; no other service was stopped') from None
    # Use the installed fork's own CLI and profile; never copy session databases.
    environment = dict(os.environ, ROOM_SECRET=config['room_secret'], HOST='127.0.0.1',
        PUBLIC_URL=f"http://127.0.0.1:{config['dashboard_port']}")
    flags = (subprocess.CREATE_NO_WINDOW | subprocess.CREATE_NEW_PROCESS_GROUP) if os.name == 'nt' else 0
    process = subprocess.Popen([str(cli),'hub','dashboard','--no-open','--host','127.0.0.1',
        '--port',str(config['dashboard_port']),'--cwd',config['workspace_root'],
        '--config',config['cline_config_dir']],env=environment,stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,creationflags=flags)
    diagnostics=[]
    def read_diagnostics():
        for raw in iter(process.stderr.readline,b''):
            line=raw.decode('utf-8','replace').strip()
            for secret in (config['password'],config['room_secret']):line=line.replace(secret,'[redacted]')
            if any(word in line.lower() for word in ('apikey','auth_token','accesstoken','sk-','eyj')):
                line='[sensitive diagnostic omitted]'
            diagnostics.append(line[:500])
            del diagnostics[:-20]
    threading.Thread(target=read_diagnostics,daemon=True).start()
    server = None
    close_guard = None
    try:
        close_guard = dashboard_lifetime_guard(process)
        for _ in range(120):
            if process.poll() is not None:
                raise RuntimeError('Cline dashboard exited; original Desktop/Hub were not stopped')
            try:
                reader, writer = await asyncio.wait_for(asyncio.open_connection('127.0.0.1',config['dashboard_port']),1)
                writer.close();await writer.wait_closed();break
            except (OSError,asyncio.TimeoutError):
                await asyncio.sleep(.5)
        else:
            raise RuntimeError('Cline dashboard did not become ready')
        admission=Admission()
        server = await listen(config,admission)
        (state.parent/'gateway-error.json').unlink(missing_ok=True)
        while process.poll() is None:
            receipt={'status':'ready','pid':os.getpid(),'dashboard_pid':process.pid,
                'ssh_port':config['ssh_port'],'dashboard_port':config['dashboard_port'],
                'bind_host':config['bind_host'],'shell':False,'sftp':False,
                'forward_target':'loopback Cline dashboard only',
                'active_connections':admission.active,'updated_unix':time.time()}
            state.write_text(json.dumps(receipt)+'\n',encoding='utf-8')
            if config.get('coordination_file'):
                Path(config['coordination_file']).write_text(json.dumps(receipt)+'\n',encoding='utf-8')
            await asyncio.sleep(2)
        raise RuntimeError('Cline dashboard stopped')
    finally:
        if server:
            server.close();await server.wait_closed()
        if process.poll() is None:
            process.terminate()
            with contextlib.suppress(subprocess.TimeoutExpired):process.wait(timeout=15)
            if process.poll() is None:process.kill();process.wait()
        if close_guard:close_guard()
        state.write_text(json.dumps({'status':'stopped','pid':os.getpid(),
            'dashboard_exit_code':process.poll(),'diagnostics':diagnostics,'updated_unix':time.time()})+'\n',encoding='utf-8')


async def supervise(config,state):
    delay=2
    while True:
        try:
            await run(config,state)
        except (OSError,RuntimeError) as error:
            # An installer may replace the installed CLI. Reopen that same
            # binary/profile after backoff; never stop or replace the shared Hub.
            (state.parent/'gateway-error.json').write_text(json.dumps({
                'type':type(error).__name__,'message':str(error),'retry_seconds':delay,
                'updated_unix':time.time()})+'\n',encoding='utf-8')
            await asyncio.sleep(delay)
            delay=min(delay*2,60)


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--config',type=Path,required=True)
    args=parser.parse_args()
    config=validate_config(json.loads(args.config.read_text('utf-8')))
    # One process owns this gateway. OS releases the lock if it exits.
    lock_path=args.config.parent/'gateway.lock'
    with lock_path.open('a+b') as lock:
        if os.name=='nt':
            import msvcrt
            lock.write(b'\0');lock.flush();lock.seek(0)
            msvcrt.locking(lock.fileno(),msvcrt.LK_NBLCK,1)
        else:
            import fcntl
            fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        asyncio.run(supervise(config,args.config.parent/'runtime.json'))


if __name__=='__main__':main()
