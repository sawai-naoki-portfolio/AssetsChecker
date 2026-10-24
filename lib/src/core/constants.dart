/// アプリ全体で共有する定数。
class AppInfo {
  const AppInfo._();

  static const String name = 'Privacy Asset Checker';
  static const String nameJa = 'プライバシー資産チェッカー';
  static const String version = '1.0.0';

  /// このアプリが行わないことの宣言。設定画面でそのまま表示する。
  ///
  /// 1 行目は以前「通信量 0 Byte」と書いていたが、端末間の引き継ぎで
  /// LAN 通信を行うようになったため、実態に合わせて書き換えている。
  static const List<String> privacyPledges = [
    'このアプリのためのサーバーは存在しません。資産データを預かりません',
    '通信するのは、課金の処理と、あなたが始めた端末間の引き継ぎだけです',
    'トラッキング SDK・広告 SDK を組み込んでいません',
    '資産データは AES-256 で暗号化して端末内のみに保存します',
    '暗号キーは iOS Keychain / Android Keystore に保管します',
    'バックアップの保存先はあなたが選んだ場所だけです',
  ];
}

/// Free プランの制限値。
///
/// データを「守る」機能（バックアップ・ロック・リマインダー）は Free でも
/// 制限しない。端末内完結のアプリでバックアップに課金するのは、
/// ユーザーがデータを失う唯一の経路に値段をつけることになるため。
class FreePlanLimits {
  const FreePlanLimits._();

  /// 登録できる口座数の上限。
  static const int maxAccounts = 3;

  /// 資産推移グラフで遡れる月数。
  static const int trendMonths = 3;
}

/// バックアップの督促を出すまでの日数。
const int kBackupReminderDays = 30;

/// アプリ内課金のプロダクト定義。
///
/// App Store Connect / Google Play Console 側で同じ ID の
/// 「非消費型（買い切り）」アイテムを作成してください。
class IapProducts {
  const IapProducts._();

  static const String proLifetime = 'com.naokisawai.assetchecker.pro_lifetime';

  /// ストアから価格を取得できなかった場合に表示する既定表記。
  static const String fallbackPrice = '¥1,200';

  static const Set<String> all = {proLifetime};
}

/// [app_settings] テーブルのキー。
class SettingKeys {
  const SettingKeys._();

  static const String biometricLock = 'biometric_lock';
  static const String blockScreenshot = 'block_screenshot';
  static const String lastBackupAt = 'last_backup_at';

  /// 毎月の入力リマインダー。
  static const String reminderEnabled = 'reminder_enabled';
  static const String reminderDay = 'reminder_day';
  static const String reminderHour = 'reminder_hour';

  /// 目標資産額（円）。0 なら未設定。
  static const String goalAmount = 'goal_amount';
}

/// リマインダーの既定値。給与振込後・月末に寄せている。
class ReminderDefaults {
  const ReminderDefaults._();

  static const int day = 25;
  static const int hour = 20;
}
