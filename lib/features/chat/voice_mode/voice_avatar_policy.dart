import 'package:conduit_core/models/model.dart';

const voiceAvatarMaxBytes = 25 * 1024 * 1024;
const voiceAvatarOrigin = 'https://appassets.androidplatform.net';
const voiceAvatarDocumentUrl =
    '$voiceAvatarOrigin/assets/flutter_assets/assets/voice_avatar/viewer.html';

/// Only model-owned file IDs are accepted, never provider-supplied URLs.
String? voiceAvatarFileId(Model? model) {
  final metadata = model?.metadata;
  final info = metadata?['info'];
  final meta = info is Map ? info['meta'] : metadata?['meta'];
  final avatar = meta is Map ? meta['voice_avatar'] : null;
  final id = avatar is Map ? avatar['file_id'] : null;
  return id is String &&
          RegExp(r'^[a-fA-F0-9]{8}-(?:[a-fA-F0-9]{4}-){3}[a-fA-F0-9]{12}$')
              .hasMatch(id)
      ? id
      : null;
}

bool voiceAvatarResourceAllowed(Uri? uri) => uri?.scheme == 'blob';

/// The one synthetic document is served from bundled bytes, never the network.
bool voiceAvatarDocumentAllowed(Uri? uri, {required bool isMainFrame}) =>
    isMainFrame && uri?.toString() == voiceAvatarDocumentUrl;

bool voiceAvatarLoadErrorIsFatal(Uri? uri, {required bool isMainFrame}) =>
    voiceAvatarDocumentAllowed(uri, isMainFrame: isMainFrame);

Map<String, Object> voiceAvatarSignals({
  required bool speaking,
  required int intensity,
  required bool active,
  required bool reducedMotion,
  bool outputMetered = true,
}) => {
  'speaking': speaking && active,
  'level': speaking && active ? intensity.clamp(0, 10) / 10 : 0.0,
  'active': active,
  'reducedMotion': reducedMotion,
  'metered': outputMetered,
};
