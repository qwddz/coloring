import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/catalog/categories_screen.dart';
import '../features/catalog/category_screen.dart';
import '../features/catalog/data/manifest_provider.dart';
import '../features/coloring/coloring_screen.dart';
import '../features/settings/about_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/subscription/data/purchase_providers.dart';
import '../features/subscription/paywall_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (context, state) =>
            _fadePage(state, const CategoriesScreen()),
      ),
      GoRoute(
        path: '/category/:id',
        pageBuilder: (context, state) => _fadePage(
          state,
          CategoryScreen(categoryId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) =>
            _fadePage(state, const SettingsScreen()),
      ),
      GoRoute(
        path: '/about',
        pageBuilder: (context, state) => _fadePage(state, const AboutScreen()),
      ),
      GoRoute(
        path: '/paywall',
        pageBuilder: (context, state) => _fadePage(
          state,
          PaywallScreen(
            pictureId: state.uri.queryParameters['from'],
            gatePassed: state.extra == paywallGatePassed,
          ),
        ),
      ),
      GoRoute(
        path: '/coloring/:id',
        // A locked picture opens the paywall, which asks the parental gate
        // first and returns to the picture after the purchase. The coloring
        // controller (Stage 1) must refuse it too, in case the catalog was not
        // loaded yet here.
        redirect: (context, state) {
          final id = state.pathParameters['id']!;
          final entry = ref.read(manifestProvider).value?.pictureById(id);
          if (entry == null || ref.read(canColorProvider(entry))) return null;
          return paywallRoute(pictureId: id);
        },
        pageBuilder: (context, state) {
          final id = state.pathParameters['id']!;
          return _fadePage(
            state,
            ColoringScreen(key: ValueKey(id), pictureId: id),
          );
        },
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// A short fade with a slight zoom in; instant when the system asks for
/// reduced motion.
Page<void> _fadePage(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 250),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        if (MediaQuery.disableAnimationsOf(context)) return child;
        final curve = CurveTween(curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: animation.drive(curve),
          child: ScaleTransition(
            scale: animation.drive(
              Tween<double>(begin: 0.96, end: 1).chain(curve),
            ),
            child: child,
          ),
        );
      },
    );
