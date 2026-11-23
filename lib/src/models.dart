enum UpdatePhase {
  idle,
  checking,
  downloading,
  reconstructing,
  ready,
  upToDate,
  failed,
}

/// UI-facing update events. No app restart is forced by this package.
class UpdateProgress {
  final UpdatePhase phase;
  final int receivedBytes;
  final int totalBytes;
  final String? message;
  const UpdateProgress(
    this.phase, {
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.message,
  });
  double? get fraction => totalBytes > 0 ? receivedBytes / totalBytes : null;
}

class UpdateResult {
  final bool readyOnNextLaunch;
  final bool rollbackToBase;
  final int patchNumber;
  const UpdateResult({
    required this.readyOnNextLaunch,
    this.rollbackToBase = false,
    this.patchNumber = 0,
  });
}

class OtaDartException implements Exception {
  final String message;
  const OtaDartException(this.message);
  @override
  String toString() => 'OtaDartException: $message';
}

class UpdatePolicy {
  final bool automatic;
  final Duration interval;
  final Duration initialDelay;
  const UpdatePolicy({
    this.automatic = false,
    this.interval = const Duration(hours: 6),
    this.initialDelay = const Duration(seconds: 2),
  });
  void validate() {
    if (interval < const Duration(minutes: 15) ||
        interval > const Duration(days: 7) ||
        initialDelay.isNegative) {
      throw const OtaDartException(
        'Automatic update interval must be 15 minutes–7 days, with a non-negative initial delay',
      );
    }
  }
}
