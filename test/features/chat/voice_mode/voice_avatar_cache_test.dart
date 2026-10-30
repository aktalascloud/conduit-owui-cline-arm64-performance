import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:conduit/features/chat/voice_mode/voice_avatar_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late VoiceAvatarCache cache;
  late String data;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('voice-avatar-cache-');
    cache = VoiceAvatarCache(directory: () async => directory);
    final bytes = Uint8List(20)..setAll(0, [0x67, 0x6c, 0x54, 0x46]);
    ByteData.sublistView(bytes).setUint32(8, bytes.length, Endian.little);
    data = base64Encode(bytes);
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'same avatar survives cache recreation; server/account/file isolate it',
    () async {
      var downloads = 0;
      Future<String> download() async {
        downloads++;
        return data;
      }

      Future<String> load(
        VoiceAvatarCache c,
        String server,
        String user,
        String file,
      ) => c.load(
        server: server,
        userId: user,
        fileId: file,
        download: download,
      );
      expect(await load(cache, 'a', 'u', 'one'), data);
      cache = VoiceAvatarCache(directory: () async => directory);
      expect(await load(cache, 'a', 'u', 'one'), data);
      expect(downloads, 1);
      await load(cache, 'b', 'u', 'one');
      await load(cache, 'a', 'other', 'one');
      await load(cache, 'a', 'u', 'two');
      expect(downloads, 4);
      final files = await directory
          .list(recursive: true)
          .where((f) => f is File)
          .toList();
      expect(files.length, 4);
    },
  );
  test(
    'corrupt body is fetched again; invalid download is not stored',
    () async {
      var downloads = 0;
      Future<String> load() => cache.load(
        server: 'a',
        userId: 'u',
        fileId: 'one',
        download: () async {
          downloads++;
          return data;
        },
      );
      await load();
      final file =
          (await directory.list(recursive: true).where((f) => f is File).first)
              as File;
      final bytes = await file.readAsBytes();
      bytes[bytes.length - 1] ^= 1;
      await file.writeAsBytes(bytes);
      expect(await load(), data);
      expect(downloads, 2);
      await expectLater(
        cache.load(
          server: 'a',
          userId: 'u',
          fileId: 'bad',
          download: () async => base64Encode([1, 2, 3]),
        ),
        throwsFormatException,
      );
    },
  );
}
