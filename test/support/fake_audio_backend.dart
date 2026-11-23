import 'package:coloring/features/audio/audio_controller.dart';

/// Records audio calls instead of touching platform channels.
class FakeAudioBackend implements AudioBackend {
  final calls = <String>[];

  List<Sfx> get effects => [
    for (final call in calls)
      if (call.startsWith('effect:'))
        Sfx.values.byName(call.substring('effect:'.length)),
  ];

  @override
  Future<void> preload() async => calls.add('preload');

  @override
  void playEffect(Sfx sfx) => calls.add('effect:${sfx.name}');

  @override
  void playMusic() => calls.add('playMusic');

  @override
  void pauseMusic() => calls.add('pauseMusic');

  @override
  void dispose() => calls.add('dispose');
}
