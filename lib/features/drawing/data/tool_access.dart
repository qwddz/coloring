import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../subscription/data/purchase_providers.dart';
import '../model/drawing_tool.dart';
import '../model/tool_rules.dart';

/// [canUseTool] with the current access, for lock badges only: paid tools
/// look locked while the status loads. Selecting a tool waits for the first
/// access value instead (spec §10).
final canUseToolProvider = Provider.autoDispose.family<bool, DrawingTool>(
  (ref, tool) => canUseTool(
    tool,
    fullAccess: ref.watch(fullAccessProvider).value ?? false,
  ),
);

/// [canUseSymmetry] with the current access, for the mirror lock badge.
final canUseSymmetryProvider = Provider.autoDispose<bool>(
  (ref) =>
      canUseSymmetry(fullAccess: ref.watch(fullAccessProvider).value ?? false),
);
