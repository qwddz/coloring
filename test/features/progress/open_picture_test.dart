import 'dart:typed_data';

import 'package:coloring/features/coloring/model/coloring_mode.dart';
import 'package:coloring/features/coloring/model/work.dart';
import 'package:coloring/features/progress/domain/open_picture.dart';
import 'package:flutter_test/flutter_test.dart';

Work work(String id, int millis, {bool completed = false}) => Work(
  id: id,
  pictureId: 'fox',
  mode: ColoringMode.free,
  colors: Uint32List(4),
  modified: DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true),
  completed: completed,
);

void main() {
  test('no works → pick a mode', () {
    expect(decideOpen(const []), const PickMode());
  });

  test('latest unfinished work is continued', () {
    expect(
      decideOpen([
        work('fox-1', 1000),
        work('fox-3', 3000),
        work('fox-2', 2000),
      ]),
      const ContinueWork('fox-3'),
    );
  });

  test('latest completed → pick a mode, even with an older unfinished', () {
    expect(
      decideOpen([work('fox-1', 1000), work('fox-2', 2000, completed: true)]),
      const PickMode(),
    );
  });

  test('equal modified times go to the larger id, in any order', () {
    final a = work('fox-a', 5000);
    final b = work('fox-b', 5000);
    expect(decideOpen([a, b]), const ContinueWork('fox-b'));
    expect(decideOpen([b, a]), const ContinueWork('fox-b'));
  });
}
