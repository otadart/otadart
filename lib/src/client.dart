import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:meta/meta.dart';
import 'models.dart';
import 'native_bridge.dart';

/// Connects your Flutter app to OTADart.
///
/// ```dart
/// OtaDart.start(appId: 'YOUR-APP-ID'); // after runApp: checks, downloads,
///                                      // confirms the launch, rechecks
/// ```
///
/// Or step by step:
///
/// ```dart
/// final updates = await OtaDart.initialize(appId: 'YOUR-APP-ID');
/// await updates.checkForUpdate();        // download + verify in the background
/// await updates.markCurrentBootHealthy(); // once your app is working
/// ```
///
/// Updates are applied on the next launch; the running app is never restarted.
class OtaDart {
  final NativeBridge _native;
  final Uri endpoint;
  final Map<String, Object?> release;
  final String installationId;

  /// Release version (pubspec.yaml at `otadart release`), if the build has it.
  final String? releaseVersion;

  /// Build flavor, if the release used one.
  final String? flavor;
  final HttpClient _http;
  final Duration timeout;
  final _progress = StreamController<UpdateProgress>.broadcast();
  Future<UpdateResult>? _inFlight;
  UpdateProgress _lastProgress = const UpdateProgress(UpdatePhase.idle);
  bool _closed = false;

  /// Initialize using public app identity. The compatible runtime supplies the
  /// immutable release configuration and persistent installation identifier.
  /// [publicKey] optionally checks the bundled raw base64 Ed25519 public key.
  static Future<OtaDart> initialize({
    required String appId,
    String? publicKey,
    String? runtimeLibraryPath,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final native = await NativeBridge.open(libraryPath: runtimeLibraryPath);
    try {
      final configuration = await native.call({
        'operation': 'clientConfiguration',
      });
      final manifest = Map<String, Object?>.from(
        configuration['manifest'] as Map,
      );
      final runtime = Map<String, Object?>.from(manifest['runtime'] as Map);
      if (runtime['appId'] != appId ||
          (publicKey != null && runtime['publicKey'] != publicKey)) {
        throw const OtaDartException(
          'App identity does not match this release',
        );
      }
      return await _withManifest(
        manifest: manifest,
        installationId: configuration['installationId'] as String,
        timeout: timeout,
        native: native,
      );
    } catch (_) {
      await native.close();
      rethrow;
    }
  }

  /// True when this app was built with `otadart release` and can receive
  /// patches. Returns false in `flutter run` debug builds and plain builds.
  static Future<bool> isSupported({String? runtimeLibraryPath}) async {
    try {
      final native = await NativeBridge.open(libraryPath: runtimeLibraryPath);
      try {
        await native.call({'operation': 'clientConfiguration'});
        return true;
      } finally {
        await native.close();
      }
    } catch (_) {
      return false;
    }
  }

  /// Like [initialize], but returns null instead of throwing when the app
  /// was not built with OTADart (for example during `flutter run`).
  static Future<OtaDart?> tryInitialize({
    required String appId,
    String? publicKey,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    try {
      return await initialize(
        appId: appId,
        publicKey: publicKey,
        timeout: timeout,
      );
    } catch (_) {
      return null;
    }
  }

  /// The recommended setup in one call. Returns null in `flutter run` and in
  /// builds not made with `otadart release`, so it is safe everywhere.
  ///
  /// ```dart
  /// runApp(const MyApp());
  /// OtaDart.start(appId: 'YOUR-APP-ID');
  /// ```
  ///
  /// Defaults (all optional):
  /// - [checkOnLaunch] `true`: check right away, after [firstCheckAfter]
  ///   (default no delay). A patch downloads in the background and applies
  ///   on the next launch.
  /// - [autoCheck] `true`: keep checking while the app runs, every
  ///   [checkEvery] (15 minutes to 7 days; default `check_interval_seconds`
  ///   from otadart.yaml, 6 hours). Turn it on or off later with
  ///   [startAutomaticUpdates] / [stopAutomaticUpdates].
  /// - [healthyAfter] 10 seconds: confirm this launch works. If a patch
  ///   crashes the app before that, the next launch rolls back to the
  ///   previous code. Pass null to confirm it yourself with
  ///   [markCurrentBootHealthy].
  ///
  /// ```dart
  /// OtaDart.start(
  ///   appId: 'YOUR-APP-ID',
  ///   checkEvery: const Duration(hours: 1),
  ///   firstCheckAfter: const Duration(seconds: 5),
  /// );
  /// OtaDart.start(appId: 'YOUR-APP-ID', autoCheck: false); // launch only
  /// ```
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
    final updates = await tryInitialize(
      appId: appId,
      publicKey: publicKey,
      timeout: timeout,
    );
    if (updates == null) return null;
    final every = checkEvery ?? updates._checkInterval;
    if (autoCheck) {
      updates.startAutomaticUpdates(
        UpdatePolicy(
          automatic: true,
          interval: every,
          initialDelay: checkOnLaunch ? firstCheckAfter : every,
        ),
      );
    } else {
      updates.stopAutomaticUpdates();
      if (checkOnLaunch) {
        Timer(firstCheckAfter, () async {
          if (updates._closed) return;
          try {
            await updates.checkForUpdate();
          } catch (_) {
            // Reported through progress; keep the running app.
          }
        });
      }
    }
    if (healthyAfter != null) {
      Timer(healthyAfter, () async {
        if (updates._closed) return;
        try {
          await updates.markCurrentBootHealthy();
        } catch (_) {
          // The engine records the launch; nothing to do here.
        }
      });
    }
    return updates;
  }

  Timer? _automaticTimer;
  Duration _checkInterval = const Duration(hours: 6);
  int _scheduleGeneration = 0;
  OtaDart._(
    this._native,
    this.endpoint,
    this.release,
    this.installationId,
    this.timeout, {
    this.releaseVersion,
    this.flavor,
  }) : _http = HttpClient() {
    _http.connectionTimeout = timeout;
  }

  /// Update progress events (checking, downloading, ready, failed…).
  Stream<UpdateProgress> get progress => _progress.stream;

  /// The most recent progress event.
  UpdateProgress get currentProgress => _lastProgress;

  /// Check for updates on a schedule (e.g. every 6 hours).
  void startAutomaticUpdates(UpdatePolicy policy) {
    policy.validate();
    stopAutomaticUpdates();
    if (!policy.automatic || _closed) return;
    final generation = _scheduleGeneration;
    void schedule(Duration delay) {
      _automaticTimer = Timer(delay, () async {
        try {
          await checkForUpdate();
        } catch (_) {
          /* Reported through progress; keep the running app. */
        }
        if (!_closed && generation == _scheduleGeneration) {
          schedule(policy.interval);
        }
      });
    }

    schedule(policy.initialDelay);
  }

  /// True while scheduled checks are on (see [startAutomaticUpdates]).
  bool get automaticUpdatesEnabled => _automaticTimer != null;

  /// Stop scheduled checks started by [startAutomaticUpdates].
  void stopAutomaticUpdates() {
    _scheduleGeneration++;
    _automaticTimer?.cancel();
    _automaticTimer = null;
  }

  /// Attach to the runtime already initialized by the custom engine BEFORE Dart.
  /// release must match the immutable, embedded release manifest.
  @internal
  static Future<OtaDart> attachEngine({
    required Uri endpoint,
    required Map<String, Object?> release,
    required String installationId,
    String? engineLibraryPath,
    Duration timeout = const Duration(seconds: 15),
    bool allowLocalhost = false,
  }) async {
    _validate(endpoint, release, installationId, allowLocalhost);
    return OtaDart._(
      await NativeBridge.open(libraryPath: engineLibraryPath),
      endpoint,
      Map.unmodifiable(release),
      installationId,
      timeout,
    );
  }

  /// Pass the immutable bundled otadart.release.json, e.g. decoded from Flutter
  /// rootBundle. Automatic checks are enabled only when its policy requests it.
  @internal
  static Future<OtaDart> attachManifest({
    required Map<String, Object?> manifest,
    required String installationId,
    String? engineLibraryPath,
    Duration timeout = const Duration(seconds: 15),
  }) => _withManifest(
    manifest: manifest,
    installationId: installationId,
    engineLibraryPath: engineLibraryPath,
    timeout: timeout,
  );

  static Future<OtaDart> _withManifest({
    required Map<String, Object?> manifest,
    required String installationId,
    String? engineLibraryPath,
    required Duration timeout,
    NativeBridge? native,
  }) async {
    if (manifest['schema'] != 1 ||
        manifest['runtime'] is! Map ||
        manifest['endpoint'] is! String) {
      throw const OtaDartException('Invalid embedded release manifest');
    }
    final runtime = Map<String, Object?>.from(manifest['runtime'] as Map);
    final release = {
      for (final key in [
        'appId',
        'releaseId',
        'platform',
        'arch',
        'runtimeId',
        'baseHash',
        'nativeHash',
        'channel',
      ])
        key: runtime[key],
    };
    final update = Map<String, Object?>.from(manifest['update'] as Map? ?? {});
    if (update['autoUpdate'] is! bool ||
        update['checkIntervalSeconds'] is! int ||
        update['activation'] != 'next_launch' ||
        update['verification'] != 'strict') {
      throw const OtaDartException('Unsupported embedded update policy');
    }
    final policy = UpdatePolicy(
      automatic: update['autoUpdate'] as bool,
      interval: Duration(seconds: update['checkIntervalSeconds'] as int),
    );
    policy.validate();
    final endpoint = Uri.parse(manifest['endpoint'] as String);
    _validate(endpoint, release, installationId, false);
    final client = OtaDart._(
      native ?? await NativeBridge.open(libraryPath: engineLibraryPath),
      endpoint,
      Map.unmodifiable(release),
      installationId,
      timeout,
      // Newer engines pass the top-level version; every engine passes `update`.
      releaseVersion: manifest['version'] is String
          ? manifest['version'] as String
          : (manifest['update'] as Map?)?['releaseVersion'] as String?,
      flavor: manifest['flavor'] is String
          ? manifest['flavor'] as String
          : null,
    );
    client._checkInterval = policy.interval;
    client.startAutomaticUpdates(policy);
    return client;
  }

  /// Own a standalone native runtime. Intended for embedder experiments and tests;
  /// a Flutter app must normally use attachEngine to share its engine's handle.
  @internal
  static Future<OtaDart> openNative({
    required String libraryPath,
    required Map<String, Object?> config,
    required Uri endpoint,
    required String installationId,
    Duration timeout = const Duration(seconds: 15),
    bool allowLocalhost = false,
  }) async {
    final release = {
      for (final key in [
        'appId',
        'releaseId',
        'platform',
        'arch',
        'runtimeId',
        'baseHash',
        'nativeHash',
        'channel',
      ])
        key: config[key],
    };
    _validate(endpoint, release, installationId, allowLocalhost);
    return OtaDart._(
      await NativeBridge.open(libraryPath: libraryPath, config: config),
      endpoint,
      Map.unmodifiable(release),
      installationId,
      timeout,
    );
  }

  static void _validate(
    Uri endpoint,
    Map<String, Object?> release,
    String clientId,
    bool allowLocalhost,
  ) {
    final loopback = ['localhost', '127.0.0.1', '::1'].contains(endpoint.host);
    if (endpoint.scheme != 'https' &&
        !(allowLocalhost && endpoint.scheme == 'http' && loopback)) {
      throw const OtaDartException(
        'HTTPS required; localhost HTTP must be explicitly enabled for development',
      );
    }
    if (endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.hasQuery ||
        endpoint.hasFragment ||
        (endpoint.path.isNotEmpty && endpoint.path != '/')) {
      throw const OtaDartException('Endpoint must be an origin URL');
    }
    final identifier = RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._+-]{0,127}$');
    const requiredFields = [
      'appId',
      'releaseId',
      'platform',
      'arch',
      'runtimeId',
      'baseHash',
      'nativeHash',
      'channel',
    ];
    if (!identifier.hasMatch(clientId) ||
        requiredFields.any(
          (key) => release[key] is! String || (release[key] as String).isEmpty,
        )) {
      throw const OtaDartException(
        'Release identity and persistent installation ID required',
      );
    }
  }

  void _emit(UpdateProgress value) {
    _lastProgress = value;
    if (!_progress.isClosed) _progress.add(value);
  }

  Future<Map<String, Object?>> _publicCall(Map<String, Object?> request) =>
      _closed
      ? Future.error(const OtaDartException('Client is closed'))
      : _native.call(request);

  /// Current update state on this device.
  Future<Map<String, Object?>> status() => _publicCall({'operation': 'status'});
  @internal
  Future<Map<String, Object?>> bootInfo() =>
      _publicCall({'operation': 'bootInfo'});

  /// Host-test API. The real engine performs this before creating the Dart VM.
  @internal
  Future<Map<String, Object?>> beginLaunchForEmbedder() =>
      _publicCall({'operation': 'beginLaunch'});

  /// Call after your app-specific startup health checks pass, using the exact
  /// token from the engine's selected boot. Do not auto-acknowledge on download.
  @internal
  Future<Map<String, Object?>> markHealthy(String bootToken) =>
      _publicCall({'operation': 'markHealthy', 'bootToken': bootToken});

  /// False on mobile and desktop: a downloaded patch applies the next time
  /// the user opens the app. True on the web, where [restart] reloads the page.
  bool get canRestart => false;

  /// On the web, reloads onto the newest build. Elsewhere the patch applies on
  /// the next launch, so this throws [OtaDartException].
  Future<void> restart() async => throw const OtaDartException(
    'Restart the app to apply the update: it applies on the next launch.',
  );

  /// Call only after your app's startup health checks have passed.
  Future<Map<String, Object?>> markCurrentBootHealthy() async {
    final info = await bootInfo();
    final token = info['bootToken'];
    return token is String ? markHealthy(token) : status();
  }

  /// The track this build receives patches from (e.g. stable, beta).
  String get track => release['channel'] as String;

  /// The app ID this build was released for.
  String get appId => release['appId'] as String;

  /// The patch running right now, or null when the store build is running.
  Future<OtaPatch?> currentPatch() async {
    int number;
    try {
      number = (await bootInfo())['patchNumber'] as int? ?? 0;
    } on OtaDartException {
      number = (await status())['activePatch'] as int? ?? 0;
    }
    return number > 0 ? OtaPatch(number) : null;
  }

  /// The patch already downloaded that applies on the next launch, if any.
  Future<OtaPatch?> nextPatch() async {
    final state = await status();
    final next = state['nextPatch'] as int? ?? 0;
    final current = (await currentPatch())?.number ?? 0;
    return next > 0 && next != current ? OtaPatch(next) : null;
  }

  /// Everything about this release and its patches, in one call.
  Future<OtaDartInfo> info() async {
    final state = await status();
    Map<String, Object?> boot = const {};
    try {
      boot = await bootInfo();
    } on OtaDartException {
      // Standalone runtimes have no engine launch record.
    }
    final current =
        (boot['patchNumber'] as int?) ?? (state['activePatch'] as int? ?? 0);
    final next = state['nextPatch'] as int? ?? 0;
    return OtaDartInfo(
      appId: appId,
      releaseVersion: releaseVersion,
      flavor: flavor,
      releaseId: release['releaseId'] as String,
      platform: release['platform'] as String,
      arch: release['arch'] as String,
      track: track,
      currentPatch: current > 0 ? OtaPatch(current) : null,
      nextPatch: next > 0 && next != current ? OtaPatch(next) : null,
      healthCheckPending: state['bootPending'] == true,
      recoveredFromFailedLaunch: boot['recoveredFromFailedBoot'] == true,
      failedPatchCount: state['badPatchCount'] as int? ?? 0,
      installationId: installationId,
      endpoint: endpoint,
    );
  }

  /// The track update checks use when none is given. Starts as the track
  /// the app was released with; set it (e.g. from a testers' menu) to follow
  /// beta or a custom track. `null` goes back to the built-in track.
  String? get preferredTrack => _preferredTrack;
  set preferredTrack(String? value) {
    if (value != null &&
        !RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._+-]{0,127}$').hasMatch(value)) {
      throw OtaDartException('Invalid track name: $value');
    }
    _preferredTrack = value;
  }

  String? _preferredTrack;

  /// Ask the update service what it offers, without downloading anything.
  /// [track] checks another track, e.g. `UpdateTrack.beta` or `'qa'`.
  Future<AvailableUpdate> availableUpdate({String? track}) async {
    if (_closed) throw const OtaDartException('Client is closed');
    final offer = await _fetchOffer(track);
    final plan = await _native.call({
      'operation': 'verifyOffer',
      'offer': offer,
      'nowMs': DateTime.now().millisecondsSinceEpoch,
    });
    final action = plan['action'];
    if (action == 'none') {
      return const AvailableUpdate(UpdateAvailability.upToDate);
    }
    final state = await status();
    final active = state['activePatch'] as int? ?? 0;
    final next = state['nextPatch'] as int? ?? 0;
    if (action == 'base') {
      if (next == 0) {
        return active == 0
            ? const AvailableUpdate(UpdateAvailability.upToDate)
            : const AvailableUpdate(UpdateAvailability.readyOnNextLaunch);
      }
      return const AvailableUpdate(UpdateAvailability.rollbackAvailable);
    }
    final number = plan['patchNumber'] as int;
    if (next == number) {
      return AvailableUpdate(
        active == number
            ? UpdateAvailability.upToDate
            : UpdateAvailability.readyOnNextLaunch,
        patchNumber: number,
      );
    }
    return AvailableUpdate(
      UpdateAvailability.patchAvailable,
      patchNumber: number,
      downloadBytes: plan['downloadRequired'] == true
          ? plan['transferSize'] as int? ?? 0
          : 0,
    );
  }

  /// Download and stage the update if one is available. Same as
  /// [checkForUpdate]; the update applies on the next launch.
  /// [track] follows another track, e.g. `update(track: UpdateTrack.beta)`.
  Future<UpdateResult> update({String? track}) => checkForUpdate(track: track);

  /// What the device runs and whether its last patched launch failed.
  /// Lets the console show adoption and roll a broken patch back for
  /// everyone. Contains no personal data.
  Future<Map<String, Object?>> _launchReport() async {
    try {
      Map<String, Object?> boot = const {};
      try {
        boot = await bootInfo();
      } on OtaDartException {
        // Standalone runtimes have no engine launch record.
      }
      final current =
          boot['patchNumber'] as int? ??
          (await status())['activePatch'] as int? ??
          0;
      final state = await status();
      return {
        'currentPatch': current,
        if (state['highestRevision'] is int)
          'highestRevision': state['highestRevision'],
        if (boot['recoveredFromFailedBoot'] == true) 'recovered': true,
      };
    } catch (_) {
      return const {};
    }
  }

  Future<Map<String, Object?>> _fetchOffer([String? track]) async {
    final wanted = track ?? _preferredTrack;
    if (wanted != null &&
        !RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._+-]{0,127}$').hasMatch(wanted)) {
      throw OtaDartException('Invalid track name: $wanted');
    }
    final request = await _http
        .postUrl(endpoint.resolve('/v1/check'))
        .timeout(timeout);
    request.followRedirects = false;
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode({
        ...release,
        'clientId': installationId,
        if (wanted != null && wanted != release['channel']) 'track': wanted,
        ...await _launchReport(),
      }),
    );
    final response = await request.close().timeout(timeout);
    if (response.statusCode != 200) {
      await response.take(1).drain<void>().timeout(timeout);
      throw OtaDartException('Update check failed (${response.statusCode})');
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(timeout)) {
      if (bytes.length + chunk.length > 65536) {
        throw const OtaDartException('Update response too large');
      }
      bytes.addAll(chunk);
    }
    return Map<String, Object?>.from(jsonDecode(utf8.decode(bytes)) as Map);
  }

  /// Check for a patch now and download it if there is one. It applies on the
  /// next launch. Concurrent calls share one check.
  Future<UpdateResult> checkForUpdate({String? track}) {
    if (_closed) {
      return Future.error(const OtaDartException('Client is closed'));
    }
    return _inFlight ??= _check(track).whenComplete(() {
      _inFlight = null;
    });
  }

  Future<UpdateResult> _check([String? track]) async {
    Directory? temporary;
    try {
      _emit(const UpdateProgress(UpdatePhase.checking));
      final offer = await _fetchOffer(track);
      final plan = await _native.call({
        'operation': 'verifyOffer',
        'offer': offer,
        'nowMs': DateTime.now().millisecondsSinceEpoch,
      });
      if (plan['action'] == 'none') {
        _emit(const UpdateProgress(UpdatePhase.upToDate));
        return const UpdateResult(readyOnNextLaunch: false);
      }
      String? artifact;
      if (plan['downloadRequired'] == true) {
        final path = plan['artifactPath'] as String;
        final size = plan['transferSize'] as int;
        if (!RegExp(r'^/v1/artifacts/[a-f0-9]{64}$').hasMatch(path) ||
            size <= 0 ||
            size > 33554432) {
          throw const OtaDartException('Invalid download plan');
        }
        temporary = await Directory.systemTemp.createTemp('otadart-transfer-');
        artifact = '${temporary.path}${Platform.pathSeparator}download';
        final downloadRequest = await _http
            .getUrl(endpoint.resolve(path))
            .timeout(timeout);
        downloadRequest.followRedirects = false;
        final download = await downloadRequest.close().timeout(timeout);
        if (download.statusCode != 200 ||
            (download.contentLength >= 0 && download.contentLength != size)) {
          await download.take(1).drain<void>().timeout(timeout);
          throw const OtaDartException(
            'Artifact download failed or size changed',
          );
        }
        final file = await File(artifact).open(mode: FileMode.write);
        int received = 0;
        final progressClock = Stopwatch()..start();
        int lastProgressMs = -100;
        try {
          await for (final chunk in download.timeout(timeout)) {
            received += chunk.length;
            if (received > size) {
              throw const OtaDartException('Download exceeded signed size');
            }
            await file.writeFrom(chunk);
            // Bound UI rebuild notifications even on very fast networks.
            if (received == size ||
                progressClock.elapsedMilliseconds - lastProgressMs >= 100) {
              lastProgressMs = progressClock.elapsedMilliseconds;
              _emit(
                UpdateProgress(
                  UpdatePhase.downloading,
                  receivedBytes: received,
                  totalBytes: size,
                ),
              );
            }
          }
          if (received != size) {
            throw const OtaDartException('Incomplete download');
          }
          await file.flush();
        } finally {
          await file.close();
        }
      }
      _emit(const UpdateProgress(UpdatePhase.reconstructing));
      final state = await _native.call({
        'operation': 'stage',
        'offer': offer,
        'artifactPath': artifact,
        'nowMs': DateTime.now().millisecondsSinceEpoch,
      });
      final number = plan['patchNumber'] as int;
      final rollback = plan['action'] == 'base';
      final changed = rollback
          ? state['activePatch'] != 0
          : state['activePatch'] != number;
      _emit(UpdateProgress(changed ? UpdatePhase.ready : UpdatePhase.upToDate));
      return UpdateResult(
        readyOnNextLaunch: changed,
        rollbackToBase: rollback,
        patchNumber: number,
      );
    } catch (error) {
      _emit(UpdateProgress(UpdatePhase.failed, message: error.toString()));
      rethrow;
    } finally {
      if (temporary != null && await temporary.exists()) {
        await temporary.delete(recursive: true);
      }
    }
  }

  /// Release resources. Call when the client is no longer needed.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    stopAutomaticUpdates();
    // Stop socket work; allow its cleanup to finish before closing the worker.
    _http.close(force: true);
    try {
      await _inFlight;
    } catch (_) {}
    await _native.close();
    await _progress.close();
  }
}
