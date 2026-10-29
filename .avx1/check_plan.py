"""Conservative Flutter check selection against a qualified immutable baseline."""
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SMOKE = ['test/core/providers/backend_mode_providers_test.dart',
         'test/core/providers/chat_entry_readiness_providers_test.dart']
DOC_SUFFIXES = ('.md', '.txt', '.png', '.jpg', '.svg')


def select(changed, root, *, recipe_allowed=False, avatar_assets_only=False, reviewed_native_cache=False):
    targets = set(SMOKE)
    analysis = set()
    for path in changed:
        if path == '.gitignore':
            continue  # Privacy/package gates still run; no runtime code.
        if path.startswith(('assets/voice_avatar/', 'tool/voice_avatar/')) or (path == 'pubspec.yaml' and avatar_assets_only):
            targets.add('test/features/chat/voice_mode')
            continue  # Offline JS build/audit/security checks are mandatory in CI.
        if path in {'packages/conduit_core/lib/utils/server_version_compat.dart',
                    'packages/conduit_core/test/utils/server_version_compat_test.dart'}:
            targets.update(['packages/conduit_core/test/utils/server_version_compat_test.dart',
                            'test/core/providers/server_incompatible_provider_test.dart',
                            'test/shared/widgets/server_version_warning_card_test.dart'])
            if (root / path).is_file():
                analysis.add(path)
            continue
        if path == '.avx1/build.py' and recipe_allowed:
            continue
        if path in ('.avx1/native_arm64.py', '.avx1/native_cache_proof.py', '.avx1/test_native_cache_proof.py') and reviewed_native_cache:
            continue  # Exact binary cache only; unchanged native flags and all ABI gates.
        if path.startswith(('.avx1/measurements/', '.github/', 'docs/')) or path.endswith('.md'):
            continue
        if path.startswith('.avx1/'):
            if Path(path).name in {'check_plan.py', 'test_check_plan.py', 'check-baseline.json', 'project.json', 'PATCHES.json'}:
                continue
            return 'full', [], [], 'native/toolchain or verification recipe changed: ' + path
        if path.endswith('.arb') and path.startswith('lib/l10n/'):
            targets.update(['test/l10n'])
            continue
        if path.startswith('test/') and path.endswith('_test.dart'):
            if not (root / path).is_file():
                return 'full', [], [], 'deleted test requires broad coverage'
            targets.add(path)
            analysis.add(path)
            continue
        if path.startswith(('lib/features/', 'packages/conduit_core/lib/features/')) and path.endswith('.dart'):
            feature = path.split('/features/', 1)[1].split('/')[0]
            folder = 'test/features/' + feature
            if not (root / folder).is_dir():
                return 'full', [], [], 'no affected feature suite: ' + feature
            targets.add(folder)
            if (root / path).is_file():
                analysis.add(path)
            continue
        # Shared navigation/providers, native code, lockfiles, SDK and unknown files
        # can affect every backend. Never silently narrow their coverage.
        return 'full', [], [], 'shared or unclassified input changed: ' + path
    existing = {p for p in targets if (root / p).exists()}
    targets = sorted(p for p in existing if not any(
        parent != p and (root / parent).is_dir() and p.startswith(parent.rstrip('/') + '/')
        for parent in existing))
    if not targets:
        return 'full', [], [], 'required smoke tests are missing'
    return 'targeted', targets, sorted(analysis), 'qualified unchanged shared inputs; affected feature suites plus backend smoke'


def plan(root=ROOT):
    baseline = json.loads((root / '.avx1/check-baseline.json').read_text('utf-8'))
    source = baseline['source_commit']
    if not re.fullmatch('[0-9a-f]{40}', source) or baseline.get('full_flutter_tests', 0) < 1:
        raise RuntimeError('Invalid qualified check baseline')
    def git(*args):
        return subprocess.run(['git', *args], cwd=root, capture_output=True, text=True, encoding='utf-8', check=True).stdout.strip()
    try:
        try:
            git('cat-file', '-e', source + '^{commit}')
        except subprocess.CalledProcessError:
            git('fetch', '--no-tags', '--depth=1', 'origin', source)
        if git('rev-parse', source + '^{commit}') != source:
            raise RuntimeError('Baseline source changed')
        changed = git('diff', '--name-only', source, 'HEAD').splitlines()
        current_recipe = hashlib.sha256((root / '.avx1/build.py').read_bytes()).hexdigest()
        allowed = current_recipe == baseline.get('reviewed_verification_only_recipe_sha256')
        old_pubspec = git('show', source + ':pubspec.yaml')
        current_pubspec = (root / 'pubspec.yaml').read_text('utf-8').strip()
        asset_line = '    - assets/voice_avatar/\n'
        asset_only = current_pubspec.count(asset_line) == 1 and current_pubspec.replace(asset_line, '', 1) == old_pubspec
        cache_files = baseline.get('reviewed_native_cache_files', {})
        native_cache_allowed = bool(cache_files) and all(
            (root / name).is_file() and hashlib.sha256((root / name).read_bytes()).hexdigest() == digest
            for name, digest in cache_files.items())
        mode, tests, analysis, reason = select(changed, root, recipe_allowed=allowed,
            avatar_assets_only=asset_only, reviewed_native_cache=native_cache_allowed)
        return {'mode': mode, 'tests': tests, 'analysis': analysis, 'reason': reason,
                'baseline_source': source, 'baseline_full_flutter_tests': baseline['full_flutter_tests'],
                'source_commit': git('rev-parse', 'HEAD'), 'changed_paths': changed,
                'full_suite': 'selected' if mode == 'full' else 'not run; unchanged coverage inherited from qualified baseline'}
    except (subprocess.CalledProcessError, RuntimeError) as error:
        return {'mode': 'full', 'tests': [], 'analysis': [], 'reason': 'trusted baseline unavailable: ' + type(error).__name__,
                'baseline_source': source, 'full_suite': 'selected'}


if __name__ == '__main__':
    print(json.dumps(plan(), indent=2))
