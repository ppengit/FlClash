part of '../action.dart';

class _CoreRestartRequired implements Exception {
  const _CoreRestartRequired();
}

@Riverpod(keepAlive: true)
class CoreAction extends _$CoreAction {
  CoreController get _core => ref.read(coreHandlerProvider);

  int _requestedRestartRevision = 0;
  Future<bool>? _restartOperation;

  @override
  void build() {}

  Future<void> initCore() async {
    final isInit = await _core.isInit;

    final version = ref.read(versionProvider);
    if (!isInit) {
      await _core.init(version);
    } else {
      await ref.read(proxiesActionProvider.notifier).updateGroups();
      await ref.read(providersProvider.notifier).syncProviders();
    }
  }

  Future<void> startCore() async {
    ref.read(coreStatusProvider.notifier).value = CoreStatus.connecting;
    try {
      final result = await startLifecycle();
      await _applyLifecycleResult(result);
    } catch (error) {
      _markStopped(error);
      dialogs.showBanner(
        ref.read(coreStopReasonProvider) ?? '',
        level: BannerLevel.error,
      );
    }
  }

  void _markStopped(Object error) {
    ref.read(coreStatusProvider.notifier).value = CoreStatus.disconnected;
    final reason = userFacingErrorMessage(error, currentAppLocalizations);
    ref.read(coreStopReasonProvider.notifier).value = reason.isEmpty
        ? null
        : reason;
  }

  @protected
  Future<CoreLifecycleResult> startLifecycle() {
    return _core.start();
  }

  @protected
  Future<CoreLifecycleResult> restartLifecycle() {
    return _core.restart();
  }

  // Nothing in lib/ calls CoreController.stop(); only close() (app exit)
  // supersedes a start/restart. statusFirst lets onCrash catch a crash
  // during initCore itself (it early-returns unless status is connected).
  Future<bool> _applyLifecycleResult(
    CoreLifecycleResult result, {
    bool statusFirst = false,
  }) async {
    if (result.outcome == CoreLifecycleOutcome.superseded) {
      return false;
    }
    if (statusFirst) {
      ref.read(coreStatusProvider.notifier).value = CoreStatus.connected;
      await initCore();
    } else {
      await initCore();
      ref.read(coreStatusProvider.notifier).value = CoreStatus.connected;
    }
    if (rsFeature && ref.read(patchClashConfigProvider).mitm.enable) {
      unawaited(ref.read(mitmTrustStateProvider.notifier).refresh());
    }
    return true;
  }

  Future<void> closeConnection(String id) async {
    await _core.closeConnection(id);
  }

  Future<void> closeConnections() async {
    await _core.closeConnections();
  }

  Future<void> reportNetworkChange() async {
    if (ref.read(coreStatusProvider) != CoreStatus.connected) {
      return;
    }
    try {
      await _core.reportNetworkChange();
    } catch (error) {
      commonPrint.log(
        'reportNetworkChange error: $error',
        logLevel: coreFailureLogLevel(error),
      );
    }
  }

  Future<void> forceGc() async {
    await _core.forceGc();
  }

  Future<void> crash() async {
    await _core.crash();
  }

  Future<bool> restartCore() {
    _requestedRestartRevision++;
    final activeOperation = _restartOperation;
    if (activeOperation != null) {
      return activeOperation;
    }

    final operation = _runRestartWorker();
    _restartOperation = operation;
    return operation;
  }

  Future<bool> _runRestartWorker() async {
    var authorizedRestart = false;
    try {
      var restartRequired = true;
      var appliedRevision = 0;
      var applied = true;
      while (restartRequired || appliedRevision < _requestedRestartRevision) {
        if (restartRequired) {
          ref.read(coreStatusProvider.notifier).value = CoreStatus.connecting;
          final result = await restartLifecycle();
          if (!await _applyLifecycleResult(result, statusFirst: true)) {
            return false;
          }
          restartRequired = false;
        }
        final revision = _requestedRestartRevision;
        try {
          applied = await ref
              .read(setupActionProvider.notifier)
              .restoreAfterCoreRestart();
        } on _CoreRestartRequired {
          // Setup cannot await the restart operation that is awaiting it.
          authorizedRestart = true;
          restartRequired = true;
          continue;
        }
        appliedRevision = revision;
      }
      return applied;
    } catch (error) {
      if (authorizedRestart) {
        ref.read(authorizedTunEnableProvider.notifier).value =
            TunAuthorizationState.none;
      }
      _markStopped(error);
      rethrow;
    } finally {
      _restartOperation = null;
    }
  }
}
