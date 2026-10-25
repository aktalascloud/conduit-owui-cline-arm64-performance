"""One bounded upload RPC over SSH, without a shell or arbitrary file paths."""
import asyncio
import hashlib
import hmac
import json
from pathlib import Path
import secrets
import struct

COMMAND = 'conduit-upload-v1'
MAX_FILE = 64 * 1024 * 1024
MAX_TOTAL = 1024 * 1024 * 1024
EXTENSIONS = frozenset(('.png', '.jpg', '.jpeg', '.webp', '.gif', '.pdf', '.txt',
    '.md', '.csv', '.json', '.xml', '.yaml', '.yml', '.docx', '.xlsx', '.pptx',
    '.odt', '.ods', '.rtf', '.log', '.py', '.js', '.ts', '.dart', '.c', '.cpp', '.h'))


def digest(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


class UploadInbox:
    def __init__(self, directory):
        self.root = Path(directory)
        self.active = 0
        self.reserved = 0

    def reply(self, process, value):
        process.stdout.write((json.dumps(value, ensure_ascii=False)+'\n').encode('utf-8'))

    async def handle(self, process):
        async with asyncio.timeout(300):
            await self._handle(process)

    async def _handle(self, process):
        if process.command != COMMAND or process.subsystem:
            process.exit(126)
            return
        partial = None
        reserved = 0
        admitted = False
        try:
            if self.active >= 2:
                raise ValueError('Busy')
            self.active += 1
            admitted = True
            length = struct.unpack('>I', await asyncio.wait_for(process.stdin.readexactly(4), 15))[0]
            if not 1 <= length <= 4096:
                raise ValueError('Header')
            header = json.loads(await asyncio.wait_for(process.stdin.readexactly(length), 15))
            name, size, sha = header['name'], header['size'], header['sha256']
            if not isinstance(name, str) or not 1 <= len(name) <= 128 or any(
                    c in name for c in ('/', '\\', ':', '\x00', '\n', '\r')):
                raise ValueError('Name')
            extension = Path(name).suffix.lower()
            if extension not in EXTENSIONS or type(size) is not int or not 0 < size <= MAX_FILE:
                raise ValueError('Type or size')
            if not isinstance(sha, str) or len(sha) != 64 or any(c not in '0123456789abcdef' for c in sha):
                raise ValueError('Digest')
            if self.root.is_symlink() or (hasattr(self.root, 'is_junction') and self.root.is_junction()):
                raise ValueError('Inbox')
            self.root.mkdir(parents=True, exist_ok=True)
            final = self.root/(sha+extension)
            if final.is_symlink() or (final.exists() and not final.is_file()):
                raise ValueError('Destination')
            if final.exists() and final.stat().st_size == size and hmac.compare_digest(
                    await asyncio.to_thread(digest, final), sha):
                self.reply(process, {'status':'stored','path':str(final.resolve()),'sha256':sha,'size':size})
                process.exit(0)
                return
            if final.exists():
                raise ValueError('Existing content')
            files = list(self.root.iterdir())
            if len(files) >= 1024 or any(p.is_symlink() for p in files):
                raise ValueError('Inbox')
            used = sum(p.stat().st_size for p in files if p.is_file())
            if used+self.reserved+size > MAX_TOTAL:
                raise ValueError('Quota')
            self.reserved += size
            reserved = size
            partial = self.root/('.upload-'+secrets.token_hex(16)+'.partial')
            self.reply(process, {'status':'ready'})
            await process.stdout.drain()
            calculated = hashlib.sha256()
            remaining = size
            with partial.open('xb') as output:
                while remaining:
                    chunk = await asyncio.wait_for(process.stdin.read(min(65536, remaining)), 30)
                    if not chunk:
                        raise ValueError('Truncated')
                    output.write(chunk)
                    calculated.update(chunk)
                    remaining -= len(chunk)
            if await asyncio.wait_for(process.stdin.read(1), 10):
                raise ValueError('Extra data')
            if not hmac.compare_digest(calculated.hexdigest(), sha):
                raise ValueError('Digest mismatch')
            # No existing file is overwritten, including after a lost acknowledgement.
            if final.exists():
                if not final.is_file() or final.is_symlink() or await asyncio.to_thread(digest, final) != sha:
                    raise ValueError('Concurrent destination')
                partial.unlink()
            else:
                partial.rename(final)
            partial = None
            self.reply(process, {'status':'stored','path':str(final.resolve()),'sha256':sha,'size':size})
            process.exit(0)
        except (Exception, asyncio.CancelledError):
            try:
                self.reply(process, {'status':'rejected'})
                process.exit(1)
            except Exception:
                pass
        finally:
            if partial is not None:
                partial.unlink(missing_ok=True)
            self.reserved -= reserved
            if admitted:
                self.active -= 1
