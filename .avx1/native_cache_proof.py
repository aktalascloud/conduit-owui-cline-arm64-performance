"""Reuse only exact ONNX outputs with immutable per-binary compiler evidence."""
import ast
import hashlib
import json
from pathlib import Path


def file_hash(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def compilation_signature(path):
    tree = ast.parse(Path(path).read_text('utf-8'))
    functions = {n.name:n for n in tree.body if isinstance(n, ast.FunctionDef)}
    calls = [n for n in ast.walk(functions['onnx_native']) if isinstance(n, ast.Call)
             and isinstance(n.func, ast.Name) and n.func.id == 'run' and n.args
             and isinstance(n.args[0], ast.Constant) and n.args[0].value == 'python']
    if len(calls) != 1:
        raise ValueError('ONNX compilation entry point changed')
    # ast.dump changes its empty-field formatting between Python3.12/3.13.
    # Encode semantic fields ourselves so maintenance/CI fingerprints agree.
    def canonical(node):
        if isinstance(node, ast.AST):
            return {'type':type(node).__name__, 'fields':{
                key:canonical(value) for key,value in ast.iter_fields(node)
                if value is not None and value != []}}
        if isinstance(node, list): return [canonical(value) for value in node]
        return node
    parts = [canonical(calls[0])]
    for name in ('toolchain', 'onnx_compile_evidence', 'verify_elf', 'symbols', 'build_id'):
        parts.append(canonical(functions[name]))
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id in ('FLAGS','LINK') for t in node.targets):
            parts.append(canonical(node))
    return hashlib.sha256(json.dumps(parts,sort_keys=True,separators=(',',':')).encode()).hexdigest()


def verify_cache(root, build, compiler):
    root, build = Path(root), Path(build)
    reference = root / '.avx1/measurements/onnx-qualified-reference.json'
    try:
        proof = json.loads(reference.read_text('utf-8'))
        exact = (proof['policy_sha256'] == file_hash(root/'.avx1/native-arm64.json') and
                 proof['toolchains_sha256'] == file_hash(root/'.avx1/toolchains.json') and
                 proof['lockfile_sha256'] == file_hash(root/'pubspec.lock') and
                 proof['compilation_signature'] == compilation_signature(root/'.avx1/native_arm64.py') and
                 proof['compiler'] == compiler and
                 proof['compile_database_sha256'] == file_hash(build/'Release/compile_commands.json'))
        if not exact:
            return {'status':'miss','reason':'native inputs/compiler/evidence changed'}
        for name, expected in proof['binaries'].items():
            paths = sorted(build.rglob(name), key=lambda p:len(str(p)))
            if not paths or paths[0].is_symlink() or file_hash(paths[0]) != expected:
                return {'status':'miss','reason':'native output missing or checksum changed'}
        if set(proof['binaries']) != {'libonnxruntime.so','libonnxruntime4j_jni.so'}:
            return {'status':'miss','reason':'incomplete ONNX output set'}
        return {'status':'reused','reference_run':proof['run_id'],
                'reference_source':proof['source_commit'],
                'reference_sha256':file_hash(reference),
                'scope':'Exact source/toolchain/flags/recipe/compiler/commands and both binary SHA256; ABI/exports/ELF/package gates still run'}
    except (OSError, KeyError, ValueError, TypeError, SyntaxError):
        return {'status':'miss','reason':'qualified native evidence unavailable'}
