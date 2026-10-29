"""Guard against narrowing checks after risky or unrecognized changes."""
import tempfile
from pathlib import Path
import unittest
from check_plan import select


class CheckSelection(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for p in ['test/core/providers/backend_mode_providers_test.dart',
                  'test/core/providers/chat_entry_readiness_providers_test.dart',
                  'test/features/cline/client_test.dart', 'lib/features/cline/client.dart']:
            path = self.root / p
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('', encoding='utf-8')

    def test_native_cline_change_keeps_the_whole_feature_suite(self):
        mode, tests, _, _ = select(['lib/features/cline/client.dart'], self.root)
        self.assertEqual(mode, 'targeted')
        self.assertIn('test/features/cline', tests)
        self.assertIn('test/core/providers/backend_mode_providers_test.dart', tests)

    def test_changed_shared_or_unknown_inputs_force_full_suite(self):
        for path in ['pubspec.lock', 'packages/conduit_core/lib/providers/auth.dart',
                     'packages/conduit_core/lib/utils/unknown.dart',
                     'android/app/build.gradle.kts', '.avx1/native_arm64.py', '.avx1/toolchains.json', 'unknown.file']:
            with self.subTest(path=path):
                self.assertEqual(select([path], self.root)[0], 'full')

    def test_version_gate_uses_specific_core_provider_and_widget_coverage(self):
        for name in ['packages/conduit_core/test/utils/server_version_compat_test.dart',
                     'test/core/providers/server_incompatible_provider_test.dart',
                     'test/shared/widgets/server_version_warning_card_test.dart']:
            p = self.root / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text('', encoding='utf-8')
        mode, tests, _, _ = select(['packages/conduit_core/lib/utils/server_version_compat.dart'], self.root)
        self.assertEqual(mode, 'targeted')
        self.assertIn('test/shared/widgets/server_version_warning_card_test.dart', tests)
        self.assertIn('packages/conduit_core/test/utils/server_version_compat_test.dart', tests)

    def test_missing_feature_suite_does_not_silently_skip_tests(self):
        self.assertEqual(select(['lib/features/new_feature/main.dart'], self.root)[0], 'full')

    def test_unreviewed_build_recipe_forces_full_suite(self):
        self.assertEqual(select(['.avx1/build.py'], self.root)[0], 'full')
        self.assertEqual(select(['.avx1/build.py'], self.root, recipe_allowed=True)[0], 'targeted')

    def test_deleted_test_requires_full_suite(self):
        self.assertEqual(select(['test/features/cline/deleted_test.dart'], self.root)[0], 'full')

    def test_docs_do_not_expand_runtime_coverage(self):
        mode, tests, _, _ = select(['README.md', '.avx1/measurements/receipt.json'], self.root)
        self.assertEqual(mode, 'targeted')
        self.assertEqual(len(tests), 2)

    def test_offline_avatar_assets_keep_voice_regressions(self):
        p = self.root / 'test/features/chat/voice_mode/test.dart'
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text('')
        mode, tests, _, _ = select(['assets/voice_avatar/viewer.html',
            'tool/voice_avatar/renderer.js', 'pubspec.yaml'], self.root,
            avatar_assets_only=True)
        self.assertEqual(mode, 'targeted')
        self.assertIn('test/features/chat/voice_mode', tests)
        self.assertEqual(select(['pubspec.yaml'], self.root)[0], 'full')

    def test_feature_folder_does_not_run_its_changed_test_twice(self):
        mode, tests, _, _ = select(['lib/features/cline/client.dart', 'test/features/cline/client_test.dart'], self.root)
        self.assertEqual(mode, 'targeted')
        self.assertIn('test/features/cline', tests)
        self.assertNotIn('test/features/cline/client_test.dart', tests)


if __name__ == '__main__':
    unittest.main()
