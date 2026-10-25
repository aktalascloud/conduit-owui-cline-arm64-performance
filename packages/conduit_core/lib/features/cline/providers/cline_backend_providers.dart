import 'dart:async';

import 'package:riverpod/riverpod.dart';

import '../../../providers/backend_mode_providers.dart';
import '../services/cline_native_client.dart';

class ClineBackendClientController extends Notifier<ClineNativeClient?> {
  ClineNativeClient? _owned;
  @override
  ClineNativeClient? build() {
    ref.onDispose(() {
      unawaited(_owned?.close());
    });
    ref.listen(preferredBackendProvider, (previous, next) {
      if (next != PreferredBackend.cline && _owned != null) disconnect();
    });
    return null;
  }

  void adopt(ClineNativeClient client) {
    final previous = _owned;
    _owned = client;
    state = client;
    if (previous != client) unawaited(previous?.close());
  }

  void disconnect() {
    final previous = _owned;
    _owned = null;
    state = null;
    unawaited(previous?.close());
  }
}

final clineBackendClientProvider =
    NotifierProvider<ClineBackendClientController, ClineNativeClient?>(
      ClineBackendClientController.new,
    );
final clineBackendStateProvider = StreamProvider<ClineNativeState?>((ref) {
  final client = ref.watch(clineBackendClientProvider);
  if (client == null) return Stream.value(null);
  return (() async* {
    yield client.state;
    yield* client.changes;
  })();
});
final clineBackendReadyProvider = Provider<bool>((ref) {
  final snapshot = ref.watch(clineBackendStateProvider).value;
  return snapshot?.connected == true && snapshot?.hubConnected == true;
});
