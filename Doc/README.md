# Privacy Asset Checker — 設計ドキュメント

> **サーバーを持たない資産管理アプリ。** 資産データは端末内の AES-256 暗号化 DB にだけ保存し、
> 鍵は iOS Keychain / Android Keystore に置く。Flutter で iOS・Android の両方に対応。

<table>
<tr>
<td width="25%"><img src="screenshots/01-allocation.png" alt="資産配分"></td>
<td width="25%"><img src="screenshots/11-trend-pro.png" alt="資産推移"></td>
<td width="25%"><img src="screenshots/10-editor-duplicate.png" alt="資産を記録"></td>
<td width="25%"><img src="screenshots/16-lock.png" alt="ロック"></td>
</tr>
<tr>
<td align="center">資産配分</td>
<td align="center">推移と元本ライン</td>
<td align="center">前回を 1 タップ複製</td>
<td align="center">生体認証ロック</td>
</tr>
</table>

## プロジェクト概要

| 項目 | 内容 |
|---|---|
| 種別 | スマートフォンアプリ（個人開発・Google Play 公開準備中） |
| 対応 OS | Android 7.0 以上（動作確認済み）／ iOS（コードは対応、ビルド未検証） |
| 担当 | 企画・要件定義・UI 設計・実装・テスト・ストア準備まですべて 1 人 |
| 規模 | Dart 約 9,200 行（`lib/`）＋ テスト 81 ケース ／ 17 画面 |
| 収益モデル | 買い切り 1,200 円（Pro）。広告・トラッキングなし |

### 技術スタック

| 分類 | 技術 |
|---|---|
| 言語 / フレームワーク | Dart 3.12 / Flutter 3.44 |
| 状態管理 | Riverpod 2（コード生成なし、手書きの Provider） |
| データベース | SQLite + SQLCipher（`sqflite_sqlcipher`）による AES-256 暗号化 |
| 秘密情報の保管 | `flutter_secure_storage`（iOS Keychain / Android Keystore） |
| 暗号 | PBKDF2-HMAC-SHA256（210,000 回）、AES-256-GCM（`encrypt`, `crypto`） |
| グラフ | `fl_chart` |
| 端末機能 | `local_auth`（生体認証）、`flutter_local_notifications`、`mobile_scanner`（QR）、`in_app_purchase` |
| ネイティブ | Kotlin（`FLAG_SECURE`）、Swift（タスク切替時のブラー）を `MethodChannel` で自作 |
| 品質 | `flutter_lints`（警告 0）、`flutter test`（81 ケース） |

---

## このプロジェクトで伝えたいこと

### 1. 「通信しない」を設計の制約として貫いた

「プライバシー重視」を宣伝文句にせず、**アーキテクチャの制約**として扱いました。HTTP クライアント・解析 SDK・広告 SDK を一切入れず、QR 読み取りの ML Kit もモデルを動的ダウンロードしないバンドル版を選んでいます。通信が発生する 2 つの場面（ストア課金・LAN 引き継ぎ）は README・アプリ内の約束一覧・設定画面の 3 か所に同じ文言で明記し、機能を足すたびに同期させています。

### 2. 暗号を「使う」だけでなく「検証する」

- DB 全体を SQLCipher で暗号化し、256bit 乱数鍵を Keychain / Keystore に保管
- バックアップは PBKDF2 → gzip → AES-256-GCM の封筒形式を自前で設計
- テストで **PBKDF2 の既知ベクタとの一致**、**生成ファイルに平文が残っていないこと**まで確認
- 鍵導出（1〜2 秒）は `Isolate.run` で別 isolate に逃がし、UI を止めない

### 3. サーバーなしで機種変更を実現した

端末同士を直接つなぐ引き継ぎを、2 つの経路で実装しました。

| 経路 | 仕組み |
|---|---|
| LAN 直接転送 | 旧端末が空きポートで HTTP 待ち受け。QR には待ち合わせ情報（約 50 文字）だけを載せる |
| 分割 QR | LAN が使えない環境向け。220ms ごとにフレームを切り替え、**順不同・重複ありでも復元**できる |

受信側は QR の中身で経路を自動判別するため、ユーザーは経路を意識しません。暗号鍵は毎回生成する 8 桁のコードから導出し、QR には載せないので、QR を撮影されても中身は読めません。プロトコルは純 Dart で切り出し、**実ソケットを使った往復まで単体テスト**しています。

### 4. 外部仕様の変化に強いパーサ

証券会社の CSV は予告なく書式が変わるため、列名を決め打ちせず**スコアリングでヘッダーを探索**します（完全一致 > 部分一致。SBI の「銘柄コード」列を名前列と誤認しない）。文字コードは BOM → 厳密 UTF-8 → Shift-JIS の順に判定します。

### 5. 課金まわりの落とし穴を塞いだ

- Android で決済直後にアプリが落ちると、acknowledge されない購入は **3 日後に自動返金**される。起動時に `restorePurchases()` を呼んで拾い直す（iOS ではサインインを求められるため Android 限定）
- Pro 状態は DB ではなく Keychain / Keystore に保存し、**他人のバックアップを復元しても Pro が持ち込まれない**ようにした

### 6. 「作らない」判断を記録した

年別グラフ・カテゴリ色の編集・ホーム画面ウィジェットなど、**検討したうえで見送った機能とその理由**を README に残しています（→ [要件定義書 6 章](requirements.md#6-あえて作らなかったもの)）。

---

## 技術的な課題と解決

| 課題 | 原因 | 解決 |
|---|---|---|
| 画面遮蔽プラグインがビルドできない | `screen_protector` などが Flutter 3.44 の Built-in Kotlin と衝突 | `MethodChannel` で Android（Kotlin）・iOS（Swift）のネイティブ実装を自作 |
| Android ビルドが AGP 9 で失敗 | `path_provider_android 2.3.1` が引き込む `jni 1.0.1` が評価エラー | バージョンを `>=2.2.5 <2.3.0` に固定 |
| プラグインごとに JVM ターゲットが食い違う | 各プラグインの Java / Kotlin 設定の不一致 | `gradle.projectsEvaluated` で全サブプロジェクトを Java 17 に統一（評価後に上書きしないと AGP に戻される） |
| `adb screencap` が真っ黒 | `FLAG_SECURE` が正しく効いている | エミュレータのコンソール（`adb emu screenrecord screenshot`）経由で撮影 |
| ドキュメント用のデモデータがリリースに混入する恐れ | — | `kDebugMode` **かつ** `--dart-define=DEMO_MODE=true` のときだけ投入 |
| 書き込み後に画面ごとに再読込の処理が散らばる | Provider ごとの invalidate | 読み取り側すべてが `dbRevisionProvider` を watch し、書き込み後に 1 つ進めるだけに統一 |

---

## ドキュメント一覧

| ドキュメント | 内容 |
|---|---|
| [要件定義書](requirements.md) | 背景・目的・対象ユーザー・機能要件・非機能要件・あえて作らなかったもの |
| [画面定義書](screen-definitions.md) | 画面一覧（17 画面）・画面ごとの表示項目／操作／入力チェック |
| [設計書](design.md) | システム構成・レイヤー・クラス図・シーケンス図・ER 図／テーブル定義・セキュリティ設計 |
| [テスト仕様・結果](test-report.md) | テスト方針・81 ケースの内訳・結果・既知の課題 |
| [diagrams/](diagrams/) | PlantUML ソース（`src/`）と SVG（`svg/`） |
| [screenshots/](screenshots/) | 主要画面のスクリーンショット（Android エミュレータで撮影） |

### 図の一覧

| 図 | PlantUML | SVG |
|---|---|---|
| ユースケース図 | [usecase.puml](diagrams/src/usecase.puml) | [usecase.svg](diagrams/svg/usecase.svg) |
| システム構成図 | [architecture.puml](diagrams/src/architecture.puml) | [architecture.svg](diagrams/svg/architecture.svg) |
| クラス図（ドメインモデル） | [class-domain.puml](diagrams/src/class-domain.puml) | [class-domain.svg](diagrams/svg/class-domain.svg) |
| クラス図（サービス層） | [class-service.puml](diagrams/src/class-service.puml) | [class-service.svg](diagrams/svg/class-service.svg) |
| シーケンス図① 起動 | [seq-startup.puml](diagrams/src/seq-startup.puml) | [seq-startup.svg](diagrams/svg/seq-startup.svg) |
| シーケンス図② 記録 | [seq-record.puml](diagrams/src/seq-record.puml) | [seq-record.svg](diagrams/svg/seq-record.svg) |
| シーケンス図③ バックアップ | [seq-backup.puml](diagrams/src/seq-backup.puml) | [seq-backup.svg](diagrams/svg/seq-backup.svg) |
| シーケンス図④ 端末の引き継ぎ | [seq-transfer.puml](diagrams/src/seq-transfer.puml) | [seq-transfer.svg](diagrams/svg/seq-transfer.svg) |
| シーケンス図⑤ 課金 | [seq-purchase.puml](diagrams/src/seq-purchase.puml) | [seq-purchase.svg](diagrams/svg/seq-purchase.svg) |
| 画面遷移図 | [screen-transition.puml](diagrams/src/screen-transition.puml) | [screen-transition.svg](diagrams/svg/screen-transition.svg) |
| ER 図 | [er.puml](diagrams/src/er.puml) | [er.svg](diagrams/svg/er.svg) |

SVG の再生成：

```bash
cd Doc/diagrams/src
java -jar plantuml.jar -charset UTF-8 -tsvg -o ../svg *.puml
```
