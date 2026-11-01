import 'dart:async';

import 'package:conduit_core/ports/app_lifecycle.dart';
import 'package:conduit_core/providers/app_providers.dart';
import 'package:conduit_core/providers/host_ports.dart';
import 'package:conduit_core/features/auth/providers/unified_auth_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'voice_avatar_policy.dart';

typedef VoiceAvatarBinding = ({String fileId, String revision});

/// Re-read the model card: the selected model object can outlive an avatar edit.
final voiceAvatarBindingProvider =
    StreamProvider.autoDispose<VoiceAvatarBinding?>((ref) {
      final model = ref.watch(selectedModelProvider);
      final api = ref.watch(apiServiceProvider);
      if (model == null || api == null) return Stream.value(null);
      if (ref.watch(currentUserProvider2)?.id == null)
        return Stream.value(null);
      return watchVoiceAvatarBindings(
        () => api.getModelDetails(model.id),
        lifecycle: ref.watch(appLifecycleProvider),
      );
    });

Stream<VoiceAvatarBinding?> watchVoiceAvatarBindings(
  Future<Map<String, dynamic>?> Function() fetch, {
  required AppLifecyclePort lifecycle,
  Duration interval = const Duration(seconds: 15),
}) {
  late StreamController<VoiceAvatarBinding?> controller;
  Timer? timer;
  StreamSubscription<AppLifecyclePhase>? subscription;
  var closed = false, busy = false, first = true;
  var foreground = !(lifecycle.current?.isBackground ?? false);
  Future<void> refresh() async {
    if (closed || busy || !foreground) return;
    busy = true;
    try {
      final profile = await fetch();
      if (closed) return;
      if (profile != null) {
        final id = voiceAvatarIdFromMetadata(profile);
        controller.add(
          id == null
              ? null
              : (fileId: id, revision: '${profile['updated_at'] ?? ''}'),
        );
      } else if (first) {
        controller.add(null);
      }
      first = false;
    } catch (_) {
      if (!closed && first) controller.add(null);
    } finally {
      busy = false;
    }
  }

  controller = StreamController<VoiceAvatarBinding?>(
    onListen: () {
      unawaited(refresh());
      timer = Timer.periodic(interval, (_) => unawaited(refresh()));
      subscription = lifecycle.changes.listen((phase) {
        foreground = !phase.isBackground;
        if (phase == AppLifecyclePhase.resumed) unawaited(refresh());
      });
    },
    onCancel: () async {
      closed = true;
      timer?.cancel();
      await subscription?.cancel();
    },
  );
  return controller.stream;
}
