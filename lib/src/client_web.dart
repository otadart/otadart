import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';

import 'package:web/web.dart' as web;

import 'models.dart';

/// OTADart for Flutter web.
///
/// A web app updates when you deploy a new build, but open tabs keep running
/// the old one. On the web this client compares the running build with the
/// `version.json` Flutter writes next to your site, tells you when a newer
/// build is live, and reloads onto it with [restart]. Same API as on mobile,
/// so one code path works everywhere.
class OtaDart {
  OtaDart._(this.appId, this._running, this.installationId, this.timeout);

  /// The app ID you passed to [initialize].
  final String appId;

  /// Anonymous ID kept in this browser.
  final String installationId;
  final Duration timeout;
  final String _running;
  String? _waiting;
  bool _closed = false;
  final _progress = StreamController<UpdateProgress>.broadcast();
  UpdateProgress _lastProgress = const UpdateProgress(UpdatePhase.idle);

  /// Connects to the running web build. Throws when the site has no
  /// `version.json` (for example in `flutter run -d chrome`).
  static Future<OtaDart> initialize({
    required String appId,
    String? publicKey,
    String? runtimeLibraryPath,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final running = await _fetchVersion(timeout);
    return OtaDart._(appId, running, _browserId(), timeout);
  }

  /// True when the site serves a `version.json` (any `flutter build web`).
  static Future<bool> isSupported({String? runtimeLibraryPath}) async {
    try {
      await _fetchVersion(const Duration(seconds: 15));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Like [initialize], but returns null instead of throwing.
  static Future<OtaDart?> tryInitialize({
    required String appId,
    String? publicKey,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    try {
      return await initialize(appId: appId, timeout: timeout);
    } catch (_) {
      return null;
    }
  }

  static Future<String> _fetchVersion(Duration timeout) async {
    final url = Uri.base
        .resolve('version.json')
        .replace(
          queryParameters: {
            'otadart': '${DateTime.now().millisecondsSinceEpoch}',
          },
        );
    final response = await web.window
        .fetch(url.toString().toJS, web.RequestInit(cache: 'no-store'))
        .toDart
        .timeout(timeout);
    if (!response.ok) {
      throw OtaDartException('No version.json at $url (${response.status})');
    }
    final body = jsonDecode((await response.text().toDart).toDart);
    if (body is! Map || body['version'] == null) {
      throw const OtaDartException('version.json has no version');
    }
    final build = body['build_number'];
    return build == null || '$build'.isEmpty
        ? '${body['version']}'
        : '${body['version']}+$build';
  }

  static String _browserId() {
    const key = 'otadart.installationId';
    try {
      final saved = web.window.localStorage.getItem(key);
      if (saved != null && saved.isNotEmpty) return saved;
      final random = Random.secure();
      final id = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      web.window.localStorage.setItem(key, id);
      return id;
    } catch (_) {
      return 'web';
    }
  }

  /// Update progress (checking, ready, up to date, failed).
  Stream<UpdateProgress> get progress => _progress.stream;

  /// The last progress event.
  UpdateProgress get currentProgress => _lastProgress;

  void _emit(UpdateProgress value) {
    _lastProgress = value;
    if (!_progress.isClosed) _progress.add(value);
  }

  /// The running build version, e.g. `1.2.0+5`.
  String? get releaseVersion => _running;

  /// Web builds have no flavor.
  String? get flavor => null;

  /// Web sites serve one build, so the track is always `stable`.
  String get track => UpdateTrack.stable;

  /// Accepted for API compatibility; a web site serves one build to everyone.
  String? preferredTrack;

  /// True on the web: [restart] reloads the page onto the new build.
  bool get canRestart => true;

  Future<Map<String, Object?>> status() async => {
    'platform': 'web',
    'version': _running,
    'waitingVersion': _waiting,
  };

  /// Nothing to confirm on the web; kept so one code path works everywhere.
  Future<Map<String, Object?>> markCurrentBootHealthy() async => {
    'healthy': true,
  };

  /// Web builds have no patches.
  Future<OtaPatch?> currentPatch() async => null;

  /// Web builds have no patches.
  Future<OtaPatch?> nextPatch() async => null;

  Future<OtaDartInfo> info() async => OtaDartInfo(
    appId: appId,
    releaseVersion: _running,
    flavor: null,
    releaseId: 'web',
    platform: 'web',
    arch: 'js',
    track: track,
    currentPatch: null,
    nextPatch: null,
    healthCheckPending: false,
    recoveredFromFailedLaunch: false,
    failedPatchCount: 0,
    installationId: installationId,
    endpoint: Uri.base,
  );

  /// Checks whether a newer web build is deployed. Nothing is downloaded.
  Future<AvailableUpdate> availableUpdate({String? track}) async {
    if (_closed) throw const OtaDartException('Client is closed');
    final live = await _fetchVersion(timeout);
    if (live == _running) {
      return const AvailableUpdate(UpdateAvailability.upToDate);
    }
    return AvailableUpdate(
      _waiting == live
          ? UpdateAvailability.readyOnNextLaunch
          : UpdateAvailability.patchAvailable,
      version: live,
    );
  }

  /// Same as [checkForUpdate].
  Future<UpdateResult> update({String? track}) => checkForUpdate(track: track);

  /// Checks for a newer web build. When there is one, the result says
  /// `readyOnNextLaunch`: call [restart] (or let the user reload) to run it.
  Future<UpdateResult> checkForUpdate({String? track}) async {
    if (_closed) throw const OtaDartException('Client is closed');
    _emit(const UpdateProgress(UpdatePhase.checking));
    try {
      final live = await _fetchVersion(timeout);
      if (live == _running) {
        _emit(const UpdateProgress(UpdatePhase.upToDate));
        return const UpdateResult(readyOnNextLaunch: false);
      }
      _waiting = live;
      _emit(UpdateProgress(UpdatePhase.ready, message: live));
      return const UpdateResult(readyOnNextLaunch: true);
    } catch (error) {
      _emit(UpdateProgress(UpdatePhase.failed, message: '$error'));
      rethrow;
    }
  }

  /// The recommended setup in one call, with the same options as on Android
  /// and iOS: checks for a newer web build on launch and every [checkEvery]
  /// (default 6 hours). [healthyAfter] has no effect on the web.
  static Future<OtaDart?> start({
    required String appId,
    String? publicKey,
    bool checkOnLaunch = true,
    bool autoCheck = true,
    Duration? checkEvery,
    Duration firstCheckAfter = Duration.zero,
    Duration? healthyAfter = const Duration(seconds: 10),
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final updates = await tryInitialize(appId: appId, timeout: timeout);
    if (updates == null) return null;
    final every = checkEvery ?? const Duration(hours: 6);
    if (autoCheck) {
      updates.startAutomaticUpdates(
        UpdatePolicy(
          automatic: true,
          interval: every,
          initialDelay: checkOnLaunch ? firstCheckAfter : every,
        ),
      );
    } else if (checkOnLaunch) {
      Timer(firstCheckAfter, () {
        if (!updates._closed) updates.checkForUpdate().ignore();
      });
    }
    return updates;
  }

  /// True while scheduled checks are on (see [startAutomaticUpdates]).
  bool get automaticUpdatesEnabled => _automaticTimer != null;

  Timer? _automaticTimer;

  /// Checks for a newer web build on a schedule (see [UpdatePolicy]).
  void startAutomaticUpdates(UpdatePolicy policy) {
    policy.validate();
    stopAutomaticUpdates();
    if (!policy.automatic || _closed) return;
    Future<void> tick() async {
      try {
        await checkForUpdate();
      } catch (_) {
        // Offline or the site is redeploying: try again next time.
      }
    }

    _automaticTimer = Timer(policy.initialDelay, () {
      if (_closed) return;
      tick();
      _automaticTimer = Timer.periodic(policy.interval, (_) => tick());
    });
  }

  /// Stops scheduled checks.
  void stopAutomaticUpdates() {
    _automaticTimer?.cancel();
    _automaticTimer = null;
  }

  /// The site this web build is served from.
  Uri get endpoint => Uri.base;

  /// Release details, as on mobile.
  Map<String, Object?> get release => {
    'appId': appId,
    'platform': 'web',
    'arch': 'js',
    'channel': track,
    'version': _running,
  };

  /// Reloads the page so the newest deployed build runs.
  Future<void> restart() async {
    web.window.location.reload();
  }

  Future<void> close() async {
    _closed = true;
    stopAutomaticUpdates();
    await _progress.close();
  }
}
