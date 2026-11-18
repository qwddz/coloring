import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../catalog/data/manifest_provider.dart';
import '../../catalog/domain/content_manifest.dart';
import '../../coloring/coloring_controller.dart';
import '../../coloring/data/picture_loader.dart';
import '../../coloring/model/work.dart';
import '../../subscription/data/purchase_providers.dart';
import 'gallery_backend.dart';
import 'share_backend.dart';
import 'work_renderer.dart';

enum ExportOutcome { saved, denied, unavailable, failed, shared }

/// The folder that shared PNGs are written to (inside the app's temporary
/// directory, so the share sheet's file provider can reach it). Tests
/// override it.
final shareDirectoryProvider = Provider<Future<Directory> Function()>(
  (ref) =>
      () async => Directory('${(await getTemporaryDirectory()).path}/share'),
);

/// Renders a work at the picture's full size and hands the PNG to the
/// gallery or the share sheet. Share is not gated here: the screen asks the
/// parental gate first.
class WorkExporter {
  WorkExporter(this._ref);

  final Ref _ref;
  Future<void> _clearing = Future.value();

  /// Saves the work into the gallery album. Not gated.
  Future<ExportOutcome> saveToGallery(Work work) async {
    final png = await _render(work);
    if (png == null) return ExportOutcome.unavailable;
    if (png.isEmpty) return ExportOutcome.failed;
    final name = 'animosaic_colors_${work.pictureId}_${_stamp()}';
    final GallerySaveResult result;
    try {
      result = await _ref.read(galleryBackendProvider).savePng(png, name: name);
    } on Object catch (e) {
      debugPrint('Saving ${work.id} to the gallery failed: $e');
      return ExportOutcome.failed;
    }
    return switch (result) {
      GallerySaveResult.saved => ExportOutcome.saved,
      GallerySaveResult.denied => ExportOutcome.denied,
      GallerySaveResult.failed => ExportOutcome.failed,
    };
  }

  /// Writes `<temp>/share/<workId>.png`, opens the share sheet with it and
  /// deletes it once the sheet returns.
  Future<ExportOutcome> share(Work work) async {
    final png = await _render(work);
    if (png == null) return ExportOutcome.unavailable;
    if (png.isEmpty) return ExportOutcome.failed;
    File? file;
    try {
      await _clearing;
      final directory = await _ref.read(shareDirectoryProvider)();
      await directory.create(recursive: true);
      file = File('${directory.path}/${work.id}.png');
      await file.writeAsBytes(png, flush: true);
      await _ref.read(shareBackendProvider).sharePng(file);
      return ExportOutcome.shared;
    } on Object catch (e) {
      debugPrint('Sharing ${work.id} failed: $e');
      return ExportOutcome.failed;
    } finally {
      if (file != null) await _deleteQuietly(file);
    }
  }

  /// Deletes what earlier shares left in the share folder (a share that was
  /// interrupted before its cleanup). A later [share] waits for it.
  Future<void> clearShareDirectory() => _clearing = () async {
    try {
      final directory = await _ref.read(shareDirectoryProvider)();
      if (await directory.exists()) await directory.delete(recursive: true);
    } on Object catch (e) {
      debugPrint('Clearing the share folder failed: $e');
    }
  }();

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on Object catch (e) {
      debugPrint('Deleting ${file.path} failed: $e');
    }
  }

  /// The PNG, or null when the picture is not in the manifest, is locked or
  /// cannot be loaded; an empty list when rendering failed.
  Future<Uint8List?> _render(Work work) async {
    final loader = _ref.read(pictureLoaderProvider);
    // Listened, not read: an unlistened stream provider never delivers.
    final access = _ref.listen(fullAccessProvider.future, (_, _) {});
    final PictureEntry entry;
    try {
      final fullAccessFuture = access.read();
      final PictureEntry? found;
      try {
        found = (await _ref.read(manifestProvider.future))
            .pictureById(work.pictureId);
      } on Object {
        fullAccessFuture.ignore();
        rethrow;
      }
      if (found == null) {
        fullAccessFuture.ignore();
        return null;
      }
      if (!canColor(found, fullAccess: await fullAccessFuture)) return null;
      entry = found;
    } finally {
      access.close();
    }

    final LoadedPicture picture;
    try {
      picture = await loader.load(entry);
    } on Object catch (e) {
      debugPrint('Loading ${work.pictureId} for export failed: $e');
      return null;
    }
    try {
      return await renderWorkPng(
        map: picture.map,
        colors: work.colors,
        lines: picture.linesImage,
        width: picture.meta.width,
        height: picture.meta.height,
      );
    } on Object catch (e) {
      debugPrint('Rendering ${work.id} failed: $e');
      return Uint8List(0);
    } finally {
      picture.dispose();
    }
  }

  String _stamp() {
    final t = _ref.read(coloringClockProvider)();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year.toString().padLeft(4, '0')}${two(t.month)}${two(t.day)}'
        '_${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }
}

final workExporterProvider = Provider<WorkExporter>(WorkExporter.new);
