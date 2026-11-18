import 'dart:io';

import 'package:coloring/features/coloring/model/work.dart';
import 'package:coloring/features/progress/data/picture_opener.dart';
import 'package:coloring/features/progress/data/work_repository.dart';
import 'package:coloring/features/progress/domain/open_picture.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../coloring/fakes.dart';

Work make(String picture, int millis) => Work.create(
  pictureId: picture,
  regionCount: 3,
  now: () => DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true),
);

void main() {
  test('a work saved after a decide call is seen by the next call', () async {
    final repo = InMemoryWorkRepository();
    final c = ProviderContainer(
      overrides: [workRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(c.dispose);
    final opener = c.read(pictureOpenerProvider);

    expect(await opener.decide('fox'), const PickMode());
    await repo.save(make('fox', 1000));
    expect(await opener.decide('fox'), const ContinueWork('fox-1000'));
    await repo.save(make('fox', 2000));
    expect(await opener.decide('fox'), const ContinueWork('fox-2000'));
    expect(await opener.decide('cat'), const PickMode());
  });

  test('reads the real repository fresh on every call', () async {
    final dir = await Directory.systemTemp.createTemp('opener_test');
    addTearDown(() => dir.delete(recursive: true));
    final repo = WorkRepository(() async => dir);
    final opener = PictureOpener(repo);

    expect(await opener.decide('fox'), const PickMode());
    await repo.save(make('fox', 1000));
    expect(await opener.decide('fox'), const ContinueWork('fox-1000'));
  });
}
