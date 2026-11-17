import 'dart:math';

/// A task for the grown-up before the paywall: multiply two digits.
class ParentalChallenge {
  const ParentalChallenge(this.a, this.b);

  /// Both factors in 2..9: no trivial `× 1`.
  factory ParentalChallenge.random([Random? random]) {
    final r = random ?? Random();
    return ParentalChallenge(2 + r.nextInt(8), 2 + r.nextInt(8));
  }

  final int a;
  final int b;

  bool check(String answer) => int.tryParse(answer.trim()) == a * b;
}
