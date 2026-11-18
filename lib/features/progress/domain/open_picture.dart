import '../../coloring/model/work.dart';

/// What a tap on a picture in the catalog opens.
sealed class OpenPicture {
  const OpenPicture();
}

/// Open the saved work [workId].
final class ContinueWork extends OpenPicture {
  const ContinueWork(this.workId);

  final String workId;

  @override
  bool operator ==(Object other) =>
      other is ContinueWork && other.workId == workId;

  @override
  int get hashCode => workId.hashCode;

  @override
  String toString() => 'ContinueWork($workId)';
}

/// Ask for a mode and start a new work.
final class PickMode extends OpenPicture {
  const PickMode();

  @override
  bool operator ==(Object other) => other is PickMode;

  @override
  int get hashCode => (PickMode).hashCode;

  @override
  String toString() => 'PickMode()';
}

/// Decision S2-D1: the most recently modified work of the picture is
/// continued unless it is completed; with no works, or a completed latest
/// one, a new work starts. Equal `modified` times go to the larger id.
OpenPicture decideOpen(Iterable<Work> worksOfPicture) {
  Work? latest;
  for (final work in worksOfPicture) {
    if (latest == null ||
        work.modified.isAfter(latest.modified) ||
        (work.modified.isAtSameMomentAs(latest.modified) &&
            work.id.compareTo(latest.id) > 0)) {
      latest = work;
    }
  }
  if (latest == null || latest.completed) return const PickMode();
  return ContinueWork(latest.id);
}
