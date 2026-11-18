import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `lib/features/gallery/model/` is pure Dart, like the coloring model.
void main() {
  test('gallery model files import neither Flutter nor dart:ui', () {
    final files = Directory('lib/features/gallery/model')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(files, isNotEmpty);
    for (final file in files) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('package:flutter')), reason: file.path);
      expect(source, isNot(contains('dart:ui')), reason: file.path);
    }
  });
}
