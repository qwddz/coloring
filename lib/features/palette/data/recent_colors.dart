import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/data/settings_controller.dart';

/// The last colors the child used, as ARGB ints, most recent first.
/// App-wide, not per work.
class RecentColorsController extends Notifier<List<int>> {
  static const key = 'recent_colors';
  static const maxCount = 8;

  @override
  List<int> build() {
    final stored =
        ref.read(sharedPreferencesProvider).getStringList(key) ?? const [];
    final colors = <int>[];
    for (final hex in stored) {
      final value = int.tryParse(hex, radix: 16);
      if (value != null && !colors.contains(value)) colors.add(value);
    }
    return colors.take(maxCount).toList();
  }

  /// Moves [argb] to the front, dropping a duplicate and anything past 8.
  void add(int argb) {
    state = [argb, ...state.where((c) => c != argb)].take(maxCount).toList();
    ref.read(sharedPreferencesProvider).setStringList(key, [
      for (final c in state) c.toRadixString(16).padLeft(8, '0'),
    ]);
  }
}

final recentColorsProvider =
    NotifierProvider<RecentColorsController, List<int>>(
      RecentColorsController.new,
    );
