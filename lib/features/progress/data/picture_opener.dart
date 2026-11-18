import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/open_picture.dart';
import 'work_repository.dart';

final pictureOpenerProvider = Provider<PictureOpener>(
  (ref) => PictureOpener(ref.watch(workRepositoryProvider)),
);

/// Decides what a tap on a picture opens.
class PictureOpener {
  PictureOpener(this._repository);

  final WorkRepository _repository;

  /// Reads the picture's works fresh on every call, so a work saved a
  /// moment ago is always seen.
  Future<OpenPicture> decide(String pictureId) async =>
      decideOpen(await _repository.worksFor(pictureId));
}
