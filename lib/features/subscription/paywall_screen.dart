import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/book_palette.dart';
import '../../app/widgets/book_button.dart';
import '../../app/widgets/paper_background.dart';
import '../../app/widgets/passe_partout.dart';
import '../../app/widgets/round_icon_button.dart';
import '../../l10n/app_localizations.dart';
import '../catalog/catalog_grid.dart';
import '../catalog/data/manifest_provider.dart';
import '../catalog/open_picture_flow.dart';
import '../settings/data/about_links.dart';
import 'data/purchase_providers.dart';
import 'data/review_access.dart';
import 'parental_gate.dart';
import 'review_code_dialog.dart';

/// [pictureId] is the picture to open once the full version is unlocked;
/// without it the paywall returns to the previous screen.
String paywallRoute({String? pictureId}) =>
    Uri(path: '/paywall', queryParameters: {'from': ?pictureId}).toString();

/// The go_router `extra` for [paywallRoute] once the parental gate passed.
const paywallGatePassed = #paywallGatePassed;

/// Asks the parental gate, then opens the paywall. Repeated taps while the
/// gate is up are ignored, so only one gate and one paywall open. With
/// [pictureId], that picture opens after the purchase. Completes once the
/// paywall closed, with whether it was shown (false when the gate failed).
Future<bool> openPaywallThroughGate(
  BuildContext context,
  WidgetRef ref, {
  String? pictureId,
}) async {
  if (!await showParentalGate(context, ref) || !context.mounted) return false;
  await context.push(
    paywallRoute(pictureId: pictureId),
    extra: paywallGatePassed,
  );
  return true;
}

/// Sells the "Full version". Never shown without the parental gate: opened
/// any other way than with [paywallGatePassed] (a locked picture link), it
/// asks the gate first and goes back if the gate is not passed.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key, this.pictureId, this.gatePassed = false});

  final String? pictureId;
  final bool gatePassed;

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  late bool _gatePassed = widget.gatePassed;

  @override
  void initState() {
    super.initState();
    if (!_gatePassed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _askGate());
    }
  }

  Future<void> _askGate() async {
    if (!mounted) return;
    final passed = await showParentalGate(context, ref);
    if (!mounted) return;
    if (passed) {
      setState(() => _gatePassed = true);
    } else {
      _back(context);
    }
  }

  Future<void> _leave(BuildContext context) async {
    final pictureId = widget.pictureId;
    if (pictureId != null) {
      final route = await openPictureFlow(context, ref, pictureId);
      if (!context.mounted) return;
      if (route != null) {
        context.pushReplacement(route);
      } else {
        _back(context);
      }
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  void _back(BuildContext context) =>
      context.canPop() ? context.pop() : context.go('/');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final header = CatalogHeader(
      title: l10n.fullVersionTitle,
      leading: RoundIconButton(
        tooltip: l10n.back,
        icon: Icons.arrow_back_rounded,
        onPressed: () => _back(context),
      ),
    );
    if (!_gatePassed) {
      return Scaffold(
        body: PaperBackground(
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [header],
            ),
          ),
        ),
      );
    }
    ref.listen(fullAccessProvider, (previous, next) {
      if (next.value == true && previous?.value != true) _leave(context);
    });
    ref.listen(purchaseControllerProvider, (_, status) {
      final message = switch (status) {
        PurchaseStatus.cancelled => l10n.purchaseCancelled,
        PurchaseStatus.pending => l10n.purchasePending,
        PurchaseStatus.failed => l10n.purchaseFailed,
        PurchaseStatus.restoreFailed => l10n.restoreFailed,
        PurchaseStatus.nothingToRestore => l10n.nothingToRestore,
        _ => null,
      };
      if (message != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      }
    });
    final owned = ref.watch(fullAccessProvider).value ?? false;
    final status = ref.watch(purchaseControllerProvider);
    final busy = status == PurchaseStatus.busy;
    final reviewCodeEnabled = ref.watch(reviewCodeSha256Provider).isNotEmpty;
    final controller = ref.read(purchaseControllerProvider.notifier);
    final pictureCount = ref.watch(manifestProvider).value?.pictures.length;
    final offer = ref.watch(purchaseOfferProvider);
    final bodyStyle = theme.textTheme.bodyLarge?.copyWith(
      color: BookPalette.text,
    );
    return Scaffold(
      body: PaperBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        PassePartout(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Shown once there are pictures to count.
                                if (pictureCount != null && pictureCount > 0)
                                  Text(
                                    l10n.fullVersionIncludes(pictureCount),
                                    style: theme.textTheme.titleMedium,
                                    textAlign: TextAlign.center,
                                  ),
                                const SizedBox(height: 8),
                                Text(
                                  l10n.fullVersionDrawingTools,
                                  style: bodyStyle,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  l10n.oneTimePurchase,
                                  style: bodyStyle,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                if (owned)
                                  Text(
                                    l10n.fullVersionUnlocked,
                                    style: theme.textTheme.titleMedium,
                                    textAlign: TextAlign.center,
                                  )
                                else
                                  switch (offer) {
                                    AsyncData(:final value) => Column(
                                      children: [
                                        BookButton(
                                          onPressed: busy
                                              ? null
                                              : controller.purchase,
                                          label: l10n.buyFor(value.price),
                                        ),
                                        if (value.testStore)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 4,
                                            ),
                                            child: Text(
                                              l10n.testStore,
                                              style: theme.textTheme.bodySmall,
                                            ),
                                          ),
                                      ],
                                    ),
                                    AsyncError() => Column(
                                      children: [
                                        Text(l10n.priceLoadError),
                                        const SizedBox(height: 8),
                                        BookButton(
                                          kind: BookButtonKind.secondary,
                                          onPressed: () => ref.invalidate(
                                            purchaseOfferProvider,
                                          ),
                                          label: l10n.retry,
                                        ),
                                      ],
                                    ),
                                    _ => const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  },
                                if (busy)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 12),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  ),
                                if (!owned) ...[
                                  const SizedBox(height: 12),
                                  Center(
                                    child: BookButton(
                                      kind: BookButtonKind.secondary,
                                      onPressed: busy
                                          ? null
                                          : controller.restore,
                                      label: l10n.restorePurchases,
                                    ),
                                  ),
                                  if (reviewCodeEnabled)
                                    Center(
                                      child: BookButton(
                                        kind: BookButtonKind.text,
                                        onPressed: busy
                                            ? null
                                            : () => showReviewCodeDialog(
                                                context,
                                                ref,
                                              ),
                                        label: l10n.haveAccessCode,
                                      ),
                                    ),
                                ],
                                const SizedBox(height: 8),
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 8,
                                  children: [
                                    BookButton(
                                      kind: BookButtonKind.text,
                                      onPressed: () => ref.read(
                                        externalLinkLauncherProvider,
                                      )(privacyPolicyUrl),
                                      label: l10n.privacyPolicy,
                                    ),
                                    BookButton(
                                      kind: BookButtonKind.text,
                                      onPressed: () => ref.read(
                                        externalLinkLauncherProvider,
                                      )(termsOfUseUrl),
                                      label: l10n.termsOfUse,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
