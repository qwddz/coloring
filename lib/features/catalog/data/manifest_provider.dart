import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../content/data/manifest_source.dart';
import '../domain/content_manifest.dart';

/// Catalog content: the local manifest at once, replaced by a newer CDN
/// manifest when the background fetch brings one. The local one is already
/// loaded by then, so the rebuild settles before the next frame and the
/// catalog does not flash a spinner.
final manifestProvider = FutureProvider<ContentManifest>((ref) async {
  final local = await ref.watch(localManifestProvider.future);
  final remote = ref.watch(remoteManifestProvider).value;
  return remote != null && remote.version > local.version ? remote : local;
});
