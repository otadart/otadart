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

/// A patch installed on this device.
class OtaPatch {
  /// The patch number, the same on every platform of a release (1, 2, 3…).
  final int number;
  const OtaPatch(this.number);
  @override
  bool operator ==(Object other) => other is OtaPatch && other.number == number;
  @override
  int get hashCode => number.hashCode;
  @override
  String toString() => 'Patch #$number';
}

/// What the update service offers this device right now.
enum UpdateAvailability {
  /// The device already runs (or has staged) what its track serves.
  upToDate,

  /// A newer patch can be downloaded.
  patchAvailable,

  /// The track was rolled back to the store build.
  rollbackAvailable,

  /// An update is already downloaded and applies on the next launch.
  readyOnNextLaunch,
}

/// Result of [OtaDart.availableUpdate]: nothing is downloaded.
class AvailableUpdate {
  final UpdateAvailability availability;

  /// Patch number offered (0 when rolling back to the store build).
  final int patchNumber;

  /// Bytes to download, 0 when nothing needs downloading.
  final int downloadBytes;
  const AvailableUpdate(
    this.availability, {
    this.patchNumber = 0,
    this.downloadBytes = 0,
  });
  bool get hasUpdate =>
      availability == UpdateAvailability.patchAvailable ||
      availability == UpdateAvailability.rollbackAvailable;
  @override
  String toString() =>
      'AvailableUpdate(${availability.name}, '
      'patch: $patchNumber, bytes: $downloadBytes)';
}

/// Everything the app can know about its release and patches.
class OtaDartInfo {
  /// App ID from otadart.yaml.
  final String appId;

  /// Release version from pubspec.yaml at `otadart release` (e.g. 1.2.0+5).
  /// Null for releases built before this field existed.
  final String? releaseVersion;

  /// Build flavor, if the release used one.
  final String? flavor;

  /// OTADart release ID.
  final String releaseId;

  /// android, ios, macos, windows or linux.
  final String platform;

  /// CPU architecture, e.g. arm64.
  final String arch;

  /// Track this build receives patches from (e.g. stable, beta).
  final String track;

  /// Patch running right now, or null for the store build.
  final OtaPatch? currentPatch;

  /// Patch downloaded and applied on the next launch, if any.
  final OtaPatch? nextPatch;

  /// True when this launch has not been confirmed healthy yet.
  final bool healthCheckPending;

  /// True when the last patched launch failed and the app fell back.
  final bool recoveredFromFailedLaunch;

  /// Patches this device refused after a failed launch.
  final int failedPatchCount;

  /// Stable, anonymous ID used for staged rollouts.
  final String installationId;

  /// Update service URL.
  final Uri endpoint;

  const OtaDartInfo({
    required this.appId,
    required this.releaseVersion,
    required this.flavor,
    required this.releaseId,
    required this.platform,
    required this.arch,
    required this.track,
    required this.currentPatch,
    required this.nextPatch,
    required this.healthCheckPending,
    required this.recoveredFromFailedLaunch,
    required this.failedPatchCount,
    required this.installationId,
    required this.endpoint,
  });

  /// e.g. "1.2.0+5 · patch #3" or "1.2.0+5 · store build".
  String get label =>
      '${releaseVersion ?? 'release ${releaseId.replaceFirst('r-', '').substring(0, 8)}'} · '
      '${currentPatch == null ? 'store build' : 'patch #${currentPatch!.number}'}';

  Map<String, Object?> toJson() => {
    'appId': appId,
    'releaseVersion': releaseVersion,
    'flavor': flavor,
    'releaseId': releaseId,
    'platform': platform,
    'arch': arch,
    'track': track,
    'currentPatch': currentPatch?.number,
    'nextPatch': nextPatch?.number,
    'healthCheckPending': healthCheckPending,
    'recoveredFromFailedLaunch': recoveredFromFailedLaunch,
    'failedPatchCount': failedPatchCount,
    'installationId': installationId,
    'endpoint': endpoint.toString(),
  };
  @override
  String toString() => 'OtaDartInfo($label, track: $track, $platform/$arch)';
}

/// Track names for `update(track: …)`. Any custom track name works too,
/// e.g. `update(track: 'qa-internal')`.
abstract final class UpdateTrack {
  /// Everyone (the default for most apps).
  static const stable = 'stable';

  /// Testers trying a patch before everyone.
  static const beta = 'beta';

  /// Your team, before beta.
  static const staging = 'staging';
}
