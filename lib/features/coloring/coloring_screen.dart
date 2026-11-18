import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/widgets/book_button.dart';
import '../../app/widgets/paper_background.dart';
import '../../app/widgets/round_icon_button.dart';
import '../../l10n/app_localizations.dart';
import '../content/data/picture_store.dart';
import '../palette/data/recent_colors.dart';
import '../palette/palette_panel.dart';
import '../subscription/paywall_screen.dart';
import 'coloring_canvas.dart';
import 'coloring_controller.dart';
import 'coloring_route.dart';
import 'coloring_state.dart';
import 'coloring_toolbar.dart';
import 'completion_overlay.dart';
import 'data/picture_loader.dart';
import 'game/coloring_game.dart';
import 'game/fill_renderer.dart';
import 'model/coloring_mode.dart';
import 'model/picture_meta.dart';

export 'coloring_route.dart' show coloringRoute, ColoringRequest;

/// Builds the fill renderer of a game from its own copy of `regions.png`.
typedef FillRendererBuilder = FillRenderer Function(
  PictureMeta meta,
  ui.Image regions,
);

/// The fill shader, loaded once per app run. Widget tests override it with
/// a [FlatFillRenderer].
final fillRendererProvider = FutureProvider<FillRendererBuilder>((ref) async {
  final program = await ShaderFillRenderer.loadProgram();
  return (meta, regions) => ShaderFillRenderer(program, regions);
});

/// The coloring screen (spec §4–5): the picture on the left, toolbar and
/// palette on the right. Everything it shows comes from
/// [coloringControllerProvider]; touches and buttons go back to it.
class ColoringScreen extends ConsumerStatefulWidget {
  const ColoringScreen({super.key, required this.request});

  final ColoringRequest request;

  @override
  ConsumerState<ColoringScreen> createState() => _ColoringScreenState();
}

class _ColoringScreenState extends ConsumerState<ColoringScreen> {
  /// Coloring screens alive right now; full screen is left only at zero.
  static var _activeScreens = 0;

  /// The panel is never narrower than this.
  static const _minPanelWidth = 200.0;
  static const _gap = 8.0;

  ColoringGame? _game;
  LoadedPicture? _gamePicture;
  FillRendererBuilder? _gameRenderer;
  ColoringController? _attachedTo;
  bool _showCompletion = false;
  bool _redirected = false;

  ColoringController get _controller =>
      ref.read(coloringControllerProvider(widget.request).notifier);

  @override
  void initState() {
    super.initState();
    _activeScreens++;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _detachGame();
    if (--_activeScreens == 0) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  void _detachGame() {
    final game = _game;
    if (game != null) _attachedTo?.detachCanvas(game);
    _attachedTo = null;
  }

  /// One game per opened picture and renderer; mode, palette and fills are
  /// pushed into it by the controller, never by recreating it.
  ColoringGame _gameFor(ColoringState state, FillRendererBuilder renderer) {
    final existing = _game;
    if (existing != null &&
        identical(_gamePicture, state.picture) &&
        identical(_gameRenderer, renderer)) {
      return existing;
    }
    _detachGame();
    final picture = state.picture;
    final game = ColoringGame(
      picture: picture,
      createRenderer: (regions) => renderer(picture.meta, regions),
      labelsEnabled: state.mode == ColoringMode.numbers,
      highlightPalette: state.mode == ColoringMode.numbers
          ? state.selectedPaletteIndex
          : null,
      reducedMotion: MediaQuery.disableAnimationsOf(context),
    );
    _game = game;
    _gamePicture = picture;
    _gameRenderer = renderer;
    final controller = _attachedTo = _controller;
    controller.attachCanvas(game);
    return game;
  }

  void _onStateChanged(
    AsyncValue<ColoringState>? previous,
    AsyncValue<ColoringState> next,
  ) {
    final before = previous?.value?.completionSeq;
    final after = next.value?.completionSeq;
    if (before != null && after != null && after > before) {
      setState(() => _showCompletion = true);
    }
  }

  /// A locked picture goes to the paywall in place of this screen, so the
  /// paywall returns to the picture after a purchase.
  void _redirectToPaywall() {
    if (_redirected) return;
    _redirected = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.pushReplacement(
          paywallRoute(pictureId: widget.request.pictureId),
        );
      }
    });
  }

  void _leave() => context.canPop() ? context.pop() : context.go('/');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = coloringControllerProvider(widget.request);
    ref.listen(provider, _onStateChanged);
    final coloring = ref.watch(provider);
    final renderer = ref.watch(fillRendererProvider);
    if (coloring case AsyncError(error: ColoringLockedException())) {
      _redirectToPaywall();
    }
    final Widget body = switch ((coloring, renderer)) {
      (AsyncData(:final value), AsyncData(value: final builder)) =>
        _buildColoring(value, builder, l10n),
      (AsyncError(error: ColoringLockedException()), _) => const SizedBox(),
      (AsyncError(:final error), _) => _buildError(error, l10n),
      (_, AsyncError(:final error)) => _buildError(error, l10n),
      _ => _buildLoading(l10n),
    };
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PaperBackground(
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(child: body),
              if (!_showCompletion || coloring.value == null)
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
    );
  }

  /// A spinner, with the download share while a CDN picture comes in.
  Widget _buildLoading(AppLocalizations l10n) {
    final progress = ref.watch(
      pictureDownloadProgressProvider(widget.request.pictureId),
    );
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(value: progress),
          const SizedBox(height: 12),
          Text(l10n.coloringLoading, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildError(Object error, AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              error is ColoringNotFoundException
                  ? l10n.coloringNotFound
                  : l10n.coloringLoadError,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              children: [
                BookButton(
                  kind: BookButtonKind.text,
                  onPressed: _leave,
                  label: l10n.back,
                ),
                BookButton(
                  onPressed: () {
                    if (ref.read(fillRendererProvider).hasError) {
                      ref.invalidate(fillRendererProvider);
                    }
                    _controller.retry();
                  },
                  label: l10n.coloringRetry,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColoring(
    ColoringState state,
    FillRendererBuilder renderer,
    AppLocalizations l10n,
  ) {
    final game = _gameFor(state, renderer);
    final controller = _controller;
    final recent = ref.watch(recentColorsProvider);
    final eraser = state.tool == ColoringTool.eraser;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - _gap * 3;
        final height = constraints.maxHeight - _gap * 2;
        final canvasWidth = (width - _minPanelWidth)
            .clamp(0.0, height * 4 / 3)
            .toDouble();
        final canvasHeight = canvasWidth * 3 / 4;
        final panelWidth = width - canvasWidth;
        return Stack(
          children: [
            Padding(
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
                        child: ColoringCanvas(
                          key: ObjectKey(game),
                          game: game,
                          brushDrags: state.mode == ColoringMode.magic,
                          onTap: (x, y, tolerance) =>
                              controller.tap(x, y, tolerance: tolerance),
                          onLongPress: (x, y, tolerance) =>
                              controller.hint(x, y, tolerance: tolerance),
                          onStrokeStart: (x, y, tolerance) {
                            controller
                              ..beginStroke()
                              ..strokeTo(x, y, tolerance: tolerance);
                          },
                          onStrokeUpdate: (x, y, tolerance) =>
                              controller.strokeTo(x, y, tolerance: tolerance),
                          onStrokeEnd: (x, y, tolerance) {
                            controller
                              ..strokeTo(x, y, tolerance: tolerance)
                              ..endStroke();
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: _gap),
                  SizedBox(
                    width: panelWidth,
                    height: height,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ColoringToolbar(
                          mode: state.mode,
                          canUndo: state.canUndo,
                          canFinish: state.canFinish,
                          eraserSelected: eraser,
                          onUndo: controller.undo,
                          onEraser: () => eraser
                              ? controller.selectColor(state.selectedColor)
                              : controller.selectEraser(),
                          onClear: controller.clearAll,
                          onDone: controller.finish,
                          onModeChanged: controller.setMode,
                        ),
                        const SizedBox(height: _gap),
                        Expanded(
                          child: PalettePanel(
                            mode: state.mode,
                            picturePalette: state.picturePalette,
                            selectedColor: state.selectedColor,
                            onColorSelected: controller.selectColor,
                            recent: recent,
                            progress: state.paletteProgress,
                            eraserSelected: eraser,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_showCompletion)
              Positioned.fill(
                child: CompletionOverlay(
                  onKeepColoring: () => setState(() => _showCompletion = false),
                  onBack: _leave,
                ),
              ),
          ],
        );
      },
    );
  }
}
