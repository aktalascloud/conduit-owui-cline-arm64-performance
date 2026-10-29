import json
from pathlib import Path
import shutil
import tempfile
import unittest
from native_cache_proof import file_hash, compilation_signature, verify_cache

ROOT = Path(__file__).resolve().parents[1]


class ExactNativeCache(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.build = self.root/'build'
        (self.build/'Release').mkdir(parents=True)
        (self.root/'.avx1/measurements').mkdir(parents=True)
        for name in ('native_arm64.py','native-arm64.json','toolchains.json'):
            shutil.copyfile(ROOT/'.avx1'/name, self.root/'.avx1'/name)
        (self.build/'Release/compile_commands.json').write_text('[]')
        self.names = ('libonnxruntime.so','libonnxruntime4j_jni.so')
        for name in self.names: (self.build/'Release'/name).write_bytes(name.encode())
        self.reference = self.root/'.avx1/measurements/onnx-qualified-reference.json'
        self.proof = {'run_id':1,'source_commit':'a'*40,'compiler':'NDK Clang exact version',
            'policy_sha256':file_hash(self.root/'.avx1/native-arm64.json'),
            'toolchains_sha256':file_hash(self.root/'.avx1/toolchains.json'),
            'compilation_signature':compilation_signature(self.root/'.avx1/native_arm64.py'),
            'compile_database_sha256':file_hash(self.build/'Release/compile_commands.json'),
            'binaries':{n:file_hash(self.build/'Release'/n) for n in self.names}}
        self.save()

    def save(self): self.reference.write_text(json.dumps(self.proof))
    def verify(self, compiler='NDK Clang exact version'):
        return verify_cache(self.root,self.build,compiler)['status']

    def test_exact_verified_outputs_reuse(self): self.assertEqual(self.verify(),'reused')
    def test_compiler_change_rejects(self): self.assertEqual(self.verify('different compiler'),'miss')
    def test_corrupt_or_missing_output_rejects(self):
        (self.build/'Release'/self.names[0]).write_bytes(b'changed')
        self.assertEqual(self.verify(),'miss')
        (self.build/'Release'/self.names[0]).unlink()
        self.assertEqual(self.verify(),'miss')
    def test_changed_inputs_reject(self):
        for name in ('native-arm64.json','toolchains.json'):
            p=self.root/'.avx1'/name
            before=p.read_bytes();p.write_bytes(before+b' ')
            self.assertEqual(self.verify(),'miss');p.write_bytes(before)
    def test_flags_or_recipe_change_rejects(self):
        p=self.root/'.avx1/native_arm64.py'
        p.write_text(p.read_text().replace("'-O3'","'-O2'",1))
        self.assertEqual(self.verify(),'miss')
    def test_command_evidence_change_rejects(self):
        (self.build/'Release/compile_commands.json').write_text('[{}]')
        self.assertEqual(self.verify(),'miss')
    def test_missing_or_incomplete_reference_rejects(self):
        self.proof['binaries'].pop(self.names[0]);self.save()
        self.assertEqual(self.verify(),'miss')
        self.reference.unlink();self.assertEqual(self.verify(),'miss')


if __name__ == '__main__': unittest.main()
