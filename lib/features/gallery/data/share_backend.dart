import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Opens the system share sheet with one PNG. No text, no links.
abstract class ShareBackend {
  Future<void> sharePng(File file);
}

class SharePlusShareBackend implements ShareBackend {
  const SharePlusShareBackend();

  @override
  Future<void> sharePng(File file) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: 'image/png')]),
    );
  }
}

final shareBackendProvider = Provider<ShareBackend>(
  (ref) => const SharePlusShareBackend(),
);
