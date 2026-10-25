import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/misc.dart';
import 'package:conduit_core/features/auth/providers/unified_auth_providers.dart';
import 'package:conduit_core/features/chat/providers/chat_providers.dart';
import 'package:conduit_core/features/cline/providers/cline_backend_providers.dart';
import 'package:conduit_core/navigation/route_redirect.dart';
import 'package:conduit_core/navigation/routes.dart';
import 'package:conduit_core/models/server_config.dart';
import 'package:conduit_core/providers/app_providers.dart';
import 'package:conduit_core/providers/backend_mode_providers.dart';

class _ClinePreferred extends PreferredBackendController {
  @override
  PreferredBackend build() => PreferredBackend.cline;
}

void main() {
  test('Cline cold start uses native workspace without an OWUI login', () {
    T read<T>(ProviderListenable<T> p) {
      if (p == reviewerModeProvider) return false as T;
      if (p == activeServerProvider)
        return const AsyncData<ServerConfig?>(null) as T;
      if (p == authNavigationStateProvider)
        return AuthNavigationState.needsLogin as T;
      if (p == preferredBackendProvider) return PreferredBackend.cline as T;
      throw StateError('Unexpected cross-backend provider read');
    }

    expect(resolveRouteRedirect(Routes.chat, read), Routes.clineWorkspace);
    expect(resolveRouteRedirect(Routes.splash, read), Routes.clineWorkspace);
    expect(resolveRouteRedirect(Routes.clineRemote, read), isNull);
    expect(resolveRouteRedirect(Routes.accounts, read), isNull);
  });
  test('generic sends cannot fall through to an OWUI account while Cline is offline', () async {
    final container = ProviderContainer(
      overrides: [preferredBackendProvider.overrideWith(_ClinePreferred.new)],
    );
    addTearDown(container.dispose);
    expect(container.read(clineBackendClientProvider), isNull);
    await expectLater(
      sendMessageWithContainer(container, 'Private Cline prompt', null),
      throwsA(isA<StateError>()),
    );
  });
}
