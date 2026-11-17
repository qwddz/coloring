import 'package:flutter/widgets.dart';

import '../catalog/domain/content_manifest.dart';
import 'content_config.dart';

/// Catalog preview of [entry]: the bundled thumb if this build ships it,
/// else the CDN one. Null when the picture has no usable preview or the
/// bundled asset list is not loaded yet.
ImageProvider? thumbImage(
  PictureEntry? entry,
  String cdnBaseUrl,
  Set<String>? bundledAssets,
) {
  if (entry == null || bundledAssets == null) return null;
  final assetPath = entry.thumbAssetPath;
  if (assetPath != null && bundledAssets.contains(assetPath)) {
    return AssetImage(assetPath);
  }
  final url = entry.thumbUrl;
  final uri = url == null ? null : resolveCdnUrl(cdnBaseUrl, url);
  return uri == null ? null : NetworkImage(uri.toString());
}
