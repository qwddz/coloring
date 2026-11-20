import 'drawing_tool.dart';
import 'symmetry.dart';

/// Free tools work for everyone; the rest need the full version (spec §10).
bool canUseTool(DrawingTool tool, {required bool fullAccess}) =>
    tool.isFree || fullAccess;

/// Mirror drawing is part of the full version.
bool canUseSymmetry({required bool fullAccess}) => fullAccess;

/// [tool] when it is usable, else the pencil (access lost while drawing).
DrawingTool fallbackTool(DrawingTool tool, {required bool fullAccess}) =>
    canUseTool(tool, fullAccess: fullAccess) ? tool : DrawingTool.pencil;

/// [mode] when mirroring is usable, else off.
SymmetryMode fallbackSymmetry(SymmetryMode mode, {required bool fullAccess}) =>
    canUseSymmetry(fullAccess: fullAccess) ? mode : SymmetryMode.off;
