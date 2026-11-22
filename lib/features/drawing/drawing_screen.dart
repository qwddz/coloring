import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/back_gesture_exclusion.dart';
import '../../app/immersive_mode.dart';
import '../../app/widgets/book_button.dart';
import '../../app/widgets/paper_background.dart';
import '../../app/widgets/round_icon_button.dart';
import '../../l10n/app_localizations.dart';
import '../palette/data/recent_colors.dart';
import '../subscription/data/purchase_providers.dart';
import '../subscription/paywall_screen.dart';
import 'drawing_canvas.dart';
import 'drawing_controller.dart';
import 'drawing_panel.dart';
import 'drawing_route.dart';
import 'drawing_state.dart';
import 'model/drawing_tool.dart';

/// The drawing screen (spec R3, §13): the 4:3 sheet on the left, the panel
/// on the right, full screen. Everything comes from
/// [drawingControllerProvider]; touches and buttons go back to it.
class DrawingScreen extends ConsumerStatefulWidget {
  const DrawingScreen({super.key, required this.request});

  final DrawingRequest request;

  @override
  ConsumerState<DrawingScreen> createState() => _DrawingScreenState();
}

class _DrawingScreenState extends ConsumerState<DrawingScreen> {
  /// The panel is never narrower than this (tools, actions and colors fit).
  static const _minPanelWidth = 300.0;
  static const _gap = 8.0;

  /// The tool to go back to when a color is picked with the eraser.
  DrawingTool _toolBeforeEraser = DrawingTool.pencil;
  bool _leavingForNewSheet = false;

  DrawingController get _controller =>
      ref.read(drawingControllerProvider(widget.request).notifier);

  @override
  void initState() {
    super.initState();
    ImmersiveMode.enter();
  }

  @override
  void dispose() {
    ImmersiveMode.leave();
    super.dispose();
  }

  /// The save is queued before the screen goes (spec §12.2), so «Мои
  /// работы» opened right after shows the last strokes. System back
  /// flushes in [PopScope]; after this flush that one finds nothing new.
  void _leave() {
    _controller.flushNow();
    context.canPop() ? context.pop() : context.go('/');
  }

  Future<void> _selectTool(DrawingTool tool) async {
    final current = ref.read(drawingControllerProvider(widget.request)).value;
    if (current != null &&
        tool == DrawingTool.eraser &&
        current.tool != DrawingTool.eraser) {
      _toolBeforeEraser = current.tool;
    }
    final controller = _controller;
    await _selectThroughPaywall(() => controller.selectTool(tool));
  }

  Future<void> _toggleMirror() async {
    final controller = _controller;
    await _selectThroughPaywall(controller.toggleSymmetry);
  }

  /// Runs [select]; when it is locked, shows the paywall and tries again.
  /// The access status may arrive a moment after the paywall closed, so a
  /// second "locked" waits for it (at most [_accessWait]) and tries once
  /// more.
  Future<void> _selectThroughPaywall(
    Future<ToolSelection> Function() select,
  ) async {
    if (await select() != ToolSelection.locked || !mounted) return;
    if (!await openPaywallThroughGate(context, ref)) return;
    if (!mounted || await select() != ToolSelection.locked) return;
    if (!mounted || !await _accessGranted()) return;
    if (mounted) await select();
  }

  static const _accessWait = Duration(seconds: 2);

  /// Completes with true once the full version is on, or false after
  /// [_accessWait].
  Future<bool> _accessGranted() {
    final granted = Completer<bool>();
    final subscription = ref.listenManual<AsyncValue<bool>>(
      fullAccessProvider,
      (_, next) {
        if (next.value == true && !granted.isCompleted) granted.complete(true);
      },
      fireImmediately: true,
    );
    return granted.future
        .timeout(_accessWait, onTimeout: () => false)
        .whenComplete(subscription.close);
  }

  /// A color picked with the eraser selected goes back to the tool used
  /// before it (the pencil when that one is no longer available).
  Future<void> _selectColor(DrawingState state, int color) async {
    final controller = _controller..selectColor(color);
    if (state.tool != DrawingTool.eraser) return;
    final selection = await controller.selectTool(_toolBeforeEraser);
    if (selection == ToolSelection.locked) {
      await controller.selectTool(DrawingTool.pencil);
    }
  }

  /// «Новый лист»: the save of this sheet is queued before the new one
  /// opens, so the new screen never races it.
  void _newSheet() {
    if (_leavingForNewSheet) return;
    _leavingForNewSheet = true;
    _controller.flushNow();
    context.pushReplacement(
      drawRoute(newSheet: true, now: ref.read(drawingClockProvider)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final drawing = ref.watch(drawingControllerProvider(widget.request));
    final Widget body = switch (drawing) {
      AsyncData(:final value) => _buildDrawing(value),
      AsyncError() => _buildError(l10n),
      _ => _buildLoading(l10n),
    };
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _controller.flushNow();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: PaperBackground(
          child: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(child: body),
                Positioned(
                  top: _gap,
                  left: _gap,
                  child: RoundIconButton(
                    tooltip: l10n.back,
                    icon: Icons.arrow_back_rounded,
                    onPressed: _leave,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading(AppLocalizations l10n) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 12),
        Text(l10n.drawingLoading, textAlign: TextAlign.center),
      ],
    ),
  );

  Widget _buildError(AppLocalizations l10n) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.drawingLoadError, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            children: [
              BookButton(
                kind: BookButtonKind.text,
                onPressed: _leave,
                label: l10n.back,
              ),
              BookButton(onPressed: _controller.retry, label: l10n.retry),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _buildDrawing(DrawingState state) {
    final controller = _controller;
    final engine = controller.engine;
    final live = controller.liveStroke;
    final recent = ref.watch(recentColorsProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - _gap * 3;
        final height = constraints.maxHeight - _gap * 2;
        final canvasWidth = (width - _minPanelWidth)
            .clamp(0.0, height * 4 / 3)
            .toDouble();
        final canvasHeight = canvasWidth * 3 / 4;
        final panelWidth = width - canvasWidth;
        return Padding(
          padding: const EdgeInsets.all(_gap),
          child: Row(
            children: [
              SizedBox(
                width: canvasWidth,
                height: height,
                child: Center(
                  child: SizedBox(
                    width: canvasWidth,
                    height: canvasHeight,
                    child: engine == null || live == null
                        ? null
                        : BackGestureExclusion(
                            child: DrawingCanvas(
                              key: ObjectKey(engine),
                              engine: engine,
                              live: live,
                              fillMode: state.tool == DrawingTool.fill,
                              onStrokeBegin: (point, erases) =>
                                  controller.strokeBegin(point, erases: erases),
                              onStrokeAdd: controller.strokeAdd,
                              onStrokeEnd: controller.strokeEnd,
                              onStrokeDiscard: controller.strokeDiscard,
                              onFill: controller.fillAt,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: _gap),
              SizedBox(
                width: panelWidth,
                height: height,
                child: DrawingPanel(
                  state: state,
                  recent: recent,
                  onTool: _selectTool,
                  onColor: (color) => _selectColor(state, color),
                  onSize: controller.selectSize,
                  onUndo: controller.undo,
                  onRedo: controller.redo,
                  onMirror: _toggleMirror,
                  onClear: controller.clear,
                  onNewSheet: _newSheet,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
