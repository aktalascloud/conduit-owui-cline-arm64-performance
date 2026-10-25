import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../models/cline_native_models.dart';
import 'cline_native_client.dart';

Future<ClineAttachment> uploadClineAttachment(
  ClineNativeClient client,
  File file,
  String name,
) async {
  final uploaded = await client.upload(file, name);
  String? image;
  final extension = name.split('.').last.toLowerCase();
  const types = {
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'webp': 'image/webp',
    'gif': 'image/gif',
  };
  if (types.containsKey(extension) && uploaded.size <= 6 * 1024 * 1024) {
    final bytes = await file.readAsBytes();
    if (sha256.convert(bytes).toString() != uploaded.sha256)
      throw const ClineNativeException('fileChanged');
    image = 'data:' + types[extension]! + ';base64,' + base64Encode(bytes);
  }
  return ClineAttachment(
    name: name,
    path: uploaded.path,
    sha256: uploaded.sha256,
    size: uploaded.size,
    imageDataUrl: image,
  );
}
