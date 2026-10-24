import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../core/constants.dart';
import '../../providers.dart';

@immutable
class PurchaseState {
  const PurchaseState({
    this.initialized = false,
    this.storeAvailable = false,
    this.product,
    this.pending = false,
    this.message,
  });

  final bool initialized;
  final bool storeAvailable;
  final ProductDetails? product;
  final bool pending;
  final String? message;

  /// ストアから取得した実際の表示価格。取得できなければ既定表記。
  String get priceLabel => product?.price ?? IapProducts.fallbackPrice;

  PurchaseState copyWith({
    bool? initialized,
    bool? storeAvailable,
    ProductDetails? product,
    bool? pending,
    String? message,
    bool clearMessage = false,
  }) => PurchaseState(
    initialized: initialized ?? this.initialized,
    storeAvailable: storeAvailable ?? this.storeAvailable,
    product: product ?? this.product,
    pending: pending ?? this.pending,
    message: clearMessage ? null : (message ?? this.message),
  );
}

/// 買い切り課金（非消費型）の状態管理。
///
/// サーバーを持たないためレシート検証はストア任せ。購入・復元の結果は
/// Keychain / Keystore に保存する。
class PurchaseController extends Notifier<PurchaseState> {
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  @override
  PurchaseState build() {
    ref.onDispose(() => _subscription?.cancel());
    scheduleMicrotask(_initialize);
    return const PurchaseState();
  }

  Future<void> _initialize() async {
    if (!_platformSupported) {
      state = state.copyWith(initialized: true, storeAvailable: false);
      return;
    }

    try {
      final available = await InAppPurchase.instance.isAvailable();
      if (!available) {
        state = state.copyWith(initialized: true, storeAvailable: false);
        return;
      }

      _subscription = InAppPurchase.instance.purchaseStream.listen(
        _handleUpdates,
        onError: (Object error) {
          state = state.copyWith(pending: false, message: '$error');
        },
      );

      final response = await InAppPurchase.instance.queryProductDetails(
        IapProducts.all,
      );
      // 0 件で返る理由は複数ある（ストア未登録・ID 不一致・テスター未設定など）。
      // notFoundIDs に ID が載っていればストア側に商品が無い、error があれば
      // 接続そのものが失敗している、と切り分けられる。
      if (response.productDetails.isEmpty) {
        debugPrint(
          'queryProductDetails returned nothing: '
          'notFoundIDs=${response.notFoundIDs} error=${response.error}',
        );
      }
      state = state.copyWith(
        initialized: true,
        storeAvailable: true,
        product: response.productDetails.isEmpty
            ? null
            : response.productDetails.first,
        message: response.productDetails.isEmpty
            ? 'ストアから商品情報を取得できませんでした'
            : null,
      );

      if (defaultTargetPlatform == TargetPlatform.android) {
        await _restoreInterruptedPurchase();
      }
    } catch (error) {
      debugPrint('PurchaseController init failed: $error');
      state = state.copyWith(initialized: true, storeAvailable: false);
    }
  }

  /// 起動時に一度だけ過去の購入を問い合わせる。
  ///
  /// Android の `purchaseStream` は購入コールバックしか流さず、過去の購入は
  /// `restorePurchases()` を呼んだときにしか届かない。決済直後にアプリが落ちて
  /// acknowledge できなかった購入をここで拾わないと、Google が 3 日後に
  /// 自動返金してしまう（[_handleUpdates] が completePurchase まで面倒を見る）。
  ///
  /// iOS で無条件に呼ぶと App Store のサインインを求められることがあるため、
  /// Android のときだけ実行する。
  ///
  /// 失敗しても購入導線そのものは生きているので、状態は変えずログだけ残す。
  Future<void> _restoreInterruptedPurchase() async {
    try {
      await InAppPurchase.instance.restorePurchases();
    } catch (error) {
      debugPrint('startup restorePurchases failed: $error');
    }
  }

  bool get _platformSupported =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.macOS;

  Future<void> buy() async {
    final product = state.product;
    if (product == null) {
      state = state.copyWith(message: '商品情報を取得できていません');
      return;
    }
    state = state.copyWith(pending: true, clearMessage: true);
    try {
      await InAppPurchase.instance.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
    } catch (error) {
      state = state.copyWith(pending: false, message: '購入を開始できませんでした: $error');
    }
  }

  Future<void> restore() async {
    if (!state.storeAvailable) {
      state = state.copyWith(message: 'ストアに接続できません');
      return;
    }
    state = state.copyWith(pending: true, clearMessage: true);
    try {
      await InAppPurchase.instance.restorePurchases();
      // 復元結果は purchaseStream 経由で届く。
      Future<void>.delayed(const Duration(seconds: 4), () {
        if (state.pending) {
          state = state.copyWith(pending: false, message: '復元できる購入はありませんでした');
        }
      });
    } catch (error) {
      state = state.copyWith(pending: false, message: '復元に失敗しました: $error');
    }
  }

  Future<void> _handleUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          state = state.copyWith(pending: true, clearMessage: true);

        case PurchaseStatus.error:
          state = state.copyWith(
            pending: false,
            message: purchase.error?.message ?? '購入処理でエラーが発生しました',
          );

        case PurchaseStatus.canceled:
          state = state.copyWith(pending: false, message: '購入をキャンセルしました');

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          if (purchase.productID == IapProducts.proLifetime) {
            await ref.read(proStatusProvider.notifier).unlock();
          }
          state = state.copyWith(
            pending: false,
            message: purchase.status == PurchaseStatus.restored
                ? 'Pro を復元しました'
                : 'Pro のご購入ありがとうございます',
          );
      }

      if (purchase.pendingCompletePurchase) {
        try {
          await InAppPurchase.instance.completePurchase(purchase);
        } catch (error) {
          debugPrint('completePurchase failed: $error');
        }
      }
    }
  }

  void clearMessage() => state = state.copyWith(clearMessage: true);
}

final purchaseControllerProvider =
    NotifierProvider<PurchaseController, PurchaseState>(PurchaseController.new);
