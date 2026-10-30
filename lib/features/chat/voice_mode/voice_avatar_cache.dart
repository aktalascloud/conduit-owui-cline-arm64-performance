import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'voice_avatar_policy.dart';

/// Private, bounded cache: no tokens, URLs or model names in filenames.
class VoiceAvatarCache {
  VoiceAvatarCache({Future<Directory> Function()? directory})
    : _directory = directory ?? getTemporaryDirectory;

  final Future<Directory> Function() _directory;
  static const maxCacheBytes = 100 * 1024 * 1024;

  Future<String> load({
    required String server,
    required String userId,
    required String fileId,
    required Future<String> Function() download,
  }) async {
    final key = sha256.convert(
      utf8.encode(jsonEncode([server, userId, fileId])),
    );
    Directory? root;
    File? file;
    try {
      root = Directory('${(await _directory()).path}/voice-avatars-v1');
      await root.create(recursive: true);
      file = File('${root.path}/$key.vrmcache');
      if (await file.exists()) {
        if (await file.length() <= voiceAvatarMaxBytes + 65) {
          final stored = await file.readAsBytes();
          if (stored.length > 65) {
            final bytes = Uint8List.sublistView(stored, 65);
            if (utf8.decode(stored.sublist(0, 64)) ==
                    sha256.convert(bytes).toString() &&
                _valid(bytes)) {
              await file.setLastModified(DateTime.now());
              return base64Encode(bytes);
            }
          }
        }
        await file.delete();
      }
    } catch (_) {
      // A full/unavailable cache must not stop an authenticated avatar load.
    }
    final data = await download();
    final bytes = base64Decode(data);
    if (!_valid(bytes)) throw const FormatException('Invalid avatar data');
    if (root != null && file != null) {
      final temporary = File(
        '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
      );
      try {
        await temporary.writeAsBytes([
          ...utf8.encode('${sha256.convert(bytes)}\n'),
          ...bytes,
        ], flush: true);
        await temporary.rename(file.path);
        final entries = await root
            .list(followLinks: false)
            .where((entry) => entry is File && entry.path.endsWith('.vrmcache'))
            .cast<File>()
            .toList();
        final stats = <File, FileStat>{};
        for (final entry in entries) {
          stats[entry] = await entry.stat();
        }
        entries.sort(
          (a, b) => stats[a]!.modified.compareTo(stats[b]!.modified),
        );
        var total = stats.values.fold<int>(0, (sum, stat) => sum + stat.size);
        for (final entry in entries) {
          if (total <= maxCacheBytes) break;
          total -= stats[entry]!.size;
          await entry.delete();
        }
      } catch (_) {
        // Rendering still works if cache storage runs out of space.
      } finally {
        try {
          if (await temporary.exists()) await temporary.delete();
        } catch (_) {
          /* Cache cleanup cannot interrupt voice graphics. */
        }
      }
    }
    return data;
  }

  bool _valid(Uint8List bytes) =>
      bytes.length >= 20 &&
      bytes.length <= voiceAvatarMaxBytes &&
      bytes[0] == 0x67 &&
      bytes[1] == 0x6c &&
      bytes[2] == 0x54 &&
      bytes[3] == 0x46 &&
      ByteData.sublistView(bytes).getUint32(8, Endian.little) == bytes.length;
}
