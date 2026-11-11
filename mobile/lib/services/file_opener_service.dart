import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// Saves downloaded bytes to a temp file and hands it off to the device's default
/// viewer/app for that file type (PDF viewer, image viewer, etc.).
class FileOpenerService {
  static Future<void> openBytes(List<int> bytes, String fileName) async {
    final dir = await getTemporaryDirectory();
    final safeName = fileName.trim().isEmpty ? 'attachment' : fileName;
    final file = File('${dir.path}/$safeName');
    await file.writeAsBytes(bytes, flush: true);

    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) {
      throw Exception(result.message.isNotEmpty ? result.message : 'Could not open that file.');
    }
  }
}
