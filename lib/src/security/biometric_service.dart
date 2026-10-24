import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

enum BiometricOutcome { success, failed, unavailable, cancelled }

/// Face ID / 指紋 / 端末パスコードによるアプリロック。
///
/// 生体認証が未登録でも端末パスコードにフォールバックできるよう
/// `biometricOnly: false` で認証する。
class BiometricService {
  BiometricService({LocalAuthentication? auth})
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  /// 生体認証またはパスコードが利用できるか。
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (error) {
      debugPrint('BiometricService.isAvailable failed: $error');
      return false;
    }
  }

  /// 登録済みの生体認証の種類（設定画面の説明文に使う）。
  Future<String> describeEnrolled() async {
    try {
      final types = await _auth.getAvailableBiometrics();
      if (types.contains(BiometricType.face)) return 'Face ID / 顔認証';
      if (types.contains(BiometricType.fingerprint)) return '指紋認証';
      if (types.contains(BiometricType.iris)) return '虹彩認証';
      if (types.isNotEmpty) return '生体認証';
      return '端末のパスコード';
    } catch (_) {
      return '端末のパスコード';
    }
  }

  Future<BiometricOutcome> authenticate({
    String reason = '資産データを表示するために認証してください',
  }) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      return ok ? BiometricOutcome.success : BiometricOutcome.failed;
    } on LocalAuthException catch (error) {
      switch (error.code) {
        case LocalAuthExceptionCode.userCanceled:
        case LocalAuthExceptionCode.systemCanceled:
        case LocalAuthExceptionCode.timeout:
          return BiometricOutcome.cancelled;

        // 認証手段そのものが使えないケース。ロックを迂回させないと
        // ユーザーが自分のデータから締め出されるため区別する。
        case LocalAuthExceptionCode.noCredentialsSet:
        case LocalAuthExceptionCode.noBiometricsEnrolled:
        case LocalAuthExceptionCode.noBiometricHardware:
        case LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable:
        case LocalAuthExceptionCode.uiUnavailable:
          return BiometricOutcome.unavailable;

        default:
          debugPrint('BiometricService.authenticate error: ${error.code}');
          return BiometricOutcome.failed;
      }
    } catch (error) {
      debugPrint('BiometricService.authenticate failed: $error');
      return BiometricOutcome.unavailable;
    }
  }
}
