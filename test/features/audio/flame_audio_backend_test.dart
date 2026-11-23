import 'package:flutter_test/flutter_test.dart';
import 'package:coloring/features/audio/audio_controller.dart';

void main() {
  test('a failed music start is retried in full, not resumed', () async {
    final calls = <String>[];
    var failNext = true;
    final backend = FlameAudioBackend(
      startMusic: () async {
        calls.add('start');
        if (failNext) {
          failNext = false;
          throw StateError('boom');
        }
      },
      resumeMusic: () async => calls.add('resume'),
    );

    backend.playMusic();
    await Future<void>.delayed(Duration.zero);
    backend.playMusic();
    await Future<void>.delayed(Duration.zero);
    backend.playMusic();
    await Future<void>.delayed(Duration.zero);

    expect(calls, ['start', 'start', 'resume']);
  });
}
