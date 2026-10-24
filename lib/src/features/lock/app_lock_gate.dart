import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../providers.dart';
import '../../security/biometric_service.dart';
import '../../security/screen_guard.dart';

/// 生体認証（またはパスコード）でアプリ全体を保護するゲート。
///
/// バックグラウンド滞在が [_graceDuration] を超えたら再ロックする。
/// 認証手段が使えない端末では締め出しを避けるため素通しする。
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  static const Duration _graceDuration = Duration(seconds: 20);

  bool _unlocked = false;
  bool _authenticating = false;
  bool _lockRequired = true;
  String? _error;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapLock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_lockRequired) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgroundedAt = DateTime.now();
      return;
    }

    if (state == AppLifecycleState.resumed) {
      final since = _backgroundedAt;
      _backgroundedAt = null;
      if (since == null || !_unlocked) return;
      if (DateTime.now().difference(since) >= _graceDuration) {
        setState(() => _unlocked = false);
        _authenticate();
      }
    }
  }

  Future<void> _bootstrapLock() async {
    final settings = await ref.read(settingsProvider.future);

    // main() では既定値で遮蔽を有効にしているので、保存済みの設定に合わせ直す。
    await ScreenGuard.setBlockScreenshot(settings.blockScreenshot);

    // リマインダーは端末側の予約が消えている場合に備えて毎起動で貼り直す。
    if (settings.reminderEnabled) {
      await ref.read(reminderServiceProvider).schedule(
        day: settings.reminderDay,
        hour: settings.reminderHour,
      );
    }

    final enabled = settings.biometricLock;
    if (!mounted) return;

    if (!enabled) {
      setState(() {
        _lockRequired = false;
        _unlocked = true;
      });
      return;
    }

    final available = await ref.read(biometricServiceProvider).isAvailable();
    if (!mounted) return;

    if (!available) {
      // パスコードすら設定されていない端末。ロックしても解除手段がない。
      setState(() {
        _lockRequired = false;
        _unlocked = true;
      });
      return;
    }

    setState(() => _lockRequired = true);
    await _authenticate();
  }

  Future<void> _authenticate() async {
    if (_authenticating) return;
    setState(() {
      _authenticating = true;
      _error = null;
    });

    final outcome = await ref.read(biometricServiceProvider).authenticate();
    if (!mounted) return;

    setState(() {
      _authenticating = false;
      switch (outcome) {
        case BiometricOutcome.success:
          _unlocked = true;
          _error = null;
        case BiometricOutcome.unavailable:
          // 端末側で認証できなくなった場合は締め出さない。
          _lockRequired = false;
          _unlocked = true;
          _error = null;
        case BiometricOutcome.cancelled:
          _error = null;
        case BiometricOutcome.failed:
          _error = '認証できませんでした。もう一度お試しください。';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return widget.child;
    return _LockScreen(
      authenticating: _authenticating,
      error: _error,
      onUnlock: _authenticate,
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({
    required this.authenticating,
    required this.error,
    required this.onUnlock,
  });

  final bool authenticating;
  final String? error;
  final Future<void> Function() onUnlock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primary.withValues(alpha: 0.12),
                ),
                child: Icon(
                  Icons.fingerprint,
                  size: 44,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 28),
              Text(AppInfo.nameJa, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'あなたの資産データは端末の中だけにあります',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 20),
                Text(
                  error!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: authenticating ? null : () => onUnlock(),
                  icon: authenticating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lock_open_outlined),
                  label: Text(authenticating ? '認証中…' : 'ロックを解除'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
