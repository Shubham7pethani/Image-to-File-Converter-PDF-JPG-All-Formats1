import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

class AppUpdateDecision {
  const AppUpdateDecision._({
    required this.mustUpdateFromStore,
    required this.storeUpdateAvailable,
    required this.shorebirdRestartRequired,
  });

  final bool mustUpdateFromStore;
  final bool storeUpdateAvailable;
  final bool shorebirdRestartRequired;

  static const none = AppUpdateDecision._(
    mustUpdateFromStore: false,
    storeUpdateAvailable: false,
    shorebirdRestartRequired: false,
  );

  AppUpdateDecision copyWith({
    bool? mustUpdateFromStore,
    bool? storeUpdateAvailable,
    bool? shorebirdRestartRequired,
  }) {
    return AppUpdateDecision._(
      mustUpdateFromStore: mustUpdateFromStore ?? this.mustUpdateFromStore,
      storeUpdateAvailable: storeUpdateAvailable ?? this.storeUpdateAvailable,
      shorebirdRestartRequired:
          shorebirdRestartRequired ?? this.shorebirdRestartRequired,
    );
  }
}

class UpdateService {
  UpdateService({
    Connectivity? connectivity,
    ShorebirdUpdater? shorebirdUpdater,
  }) : _connectivity = connectivity ?? Connectivity(),
       _shorebirdUpdater = shorebirdUpdater ?? ShorebirdUpdater();

  final Connectivity _connectivity;
  final ShorebirdUpdater _shorebirdUpdater;

  Future<bool> hasInternetConnection() async {
    final results = await _connectivity.checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  Future<String?> readCurrentPatchLabel() async {
    if (!_shorebirdUpdater.isAvailable) {
      return null;
    }
    try {
      final patch = await _shorebirdUpdater.readCurrentPatch();
      if (patch == null) return null;
      return 'Patch ${patch.number}';
    } on Exception {
      return null;
    }
  }

  Future<AppUpdateDecision> checkAndMaybeApplyUpdates({
    required bool platformIsAndroid,
  }) async {
    if (!await hasInternetConnection()) {
      return AppUpdateDecision.none;
    }

    var decision = AppUpdateDecision.none;

    // 1) Play Store updates (new AAB).
    if (platformIsAndroid) {
      final storeUpdateAvailable = await _isPlayStoreUpdateAvailable();
      // Default to force-update if Play Store has a newer AAB.
      // (We can soften this later if you want optional updates.)
      decision = decision.copyWith(
        storeUpdateAvailable: storeUpdateAvailable,
        mustUpdateFromStore: storeUpdateAvailable,
      );
    }

    // If a store update is required, skip Shorebird patch download.
    if (decision.mustUpdateFromStore) {
      return decision;
    }

    // 2) Shorebird patch updates (Dart-only changes).
    decision = decision.copyWith(
      shorebirdRestartRequired: await _checkAndApplyShorebirdPatch(),
    );

    return decision;
  }

  Future<bool> _checkAndApplyShorebirdPatch() async {
    if (!_shorebirdUpdater.isAvailable) {
      return false;
    }

    try {
      final status = await _shorebirdUpdater.checkForUpdate();
      if (status == UpdateStatus.outdated) {
        await _shorebirdUpdater.update();
        // After installing a patch, Shorebird expects restart.
        return true;
      }
      if (status == UpdateStatus.restartRequired) {
        return true;
      }
      return false;
    } on Exception {
      return false;
    }
  }

  Future<bool> _isPlayStoreUpdateAvailable() async {
    try {
      final info = await InAppUpdate.checkForUpdate();
      return info.updateAvailability == UpdateAvailability.updateAvailable;
    } on Exception {
      // This can throw when not installed from Play Store.
      return false;
    }
  }

  Future<bool> performImmediateAndroidUpdate() async {
    try {
      await InAppUpdate.performImmediateUpdate();
      return true;
    } on Exception {
      return false;
    }
  }
}
