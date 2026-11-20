import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The drawing model folder must stay pure Dart: no Flutter, Flame or
/// dart:ui.
void main() {
  test('lib/features/drawing/model has no Flutter/Flame/dart:ui imports', () {
    final dir = Directory('lib/features/drawing/model');
    final files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(files, isNotEmpty);
    final directive = RegExp(
      r'''^\s*(import|export|part)\s+['"]([^'"]+)['"]''',
      multiLine: true,
    );
    final banned = RegExp(r'^(package:flutter|package:flame|dart:ui)');
    final offenders = <String>[];
    for (final f in files) {
      for (final m in directive.allMatches(f.readAsStringSync())) {
        final uri = m.group(2)!;
        if (banned.hasMatch(uri)) offenders.add('${f.path}: $uri');
      }
    }
    expect(offenders, isEmpty);
  });
}
