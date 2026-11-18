import 'dart:io';

import 'package:flutter/widgets.dart';

/// A work preview decoded at [logicalWidth] × [devicePixelRatio] pixels
/// wide, so a grid of 640×480 previews never decodes them at full size.
/// Each redraw is a new versioned file, so the image cache never serves an
/// old one and nothing needs evicting.
ImageProvider workPreviewImage(
  File file, {
  required double logicalWidth,
  required double devicePixelRatio,
}) => ResizeImage(
  FileImage(file),
  width: (logicalWidth * devicePixelRatio).floor().clamp(1, 1 << 14),
);
