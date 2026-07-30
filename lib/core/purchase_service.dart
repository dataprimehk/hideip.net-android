import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:in_app_purchase/in_app_purchase.dart';

import 'premium.dart';

/// Store-event logging. On iOS these lines reach the system log (os_log) in
/// release builds too, which is the only way to watch a sandbox purchase on a
/// device where a debugger cannot attach. Nothing sensitive is logged.
const bool kIapLog = bool.fromEnvironment('HIP_IAP_LOG');

void iapLog(String message) {
  // ignore: avoid_print
  if (kIapLog) print(message);
}

/// How a purchase attempt ended, from the paywall's point of view: a cancel
/// returns quietly to the plans, only a real failure shows the error state.
enum PurchaseOutcome { success, canceled, failed }

/// Bridges the store (StoreKit 2 on iOS, Play Billing on Android) to
/// [Premium]. Entitlement here is client-side: the transaction the store
/// hands back is decoded for display (plan, expiry, trial), and the
/// provisioning backend re-validates the same receipt server-side before any
/// server access is issued.
class PurchaseService {
  // Lazy: the first [InAppPurchase.instance] touch registers the platform
  // implementation, which must not happen merely on construction (tests build
  // an AppState with no store channel behind it).
  InAppPurchase? _iapCached;
  InAppPurchase get _iap => _iapCached ??= InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  final Map<PremiumPlan, ProductDetails> _products = {};
  bool _available = false;
  void Function(Premium premium, PurchasePayload? proof)? _onPremium;
  void Function()? _onAvailability;
  Completer<PurchaseOutcome>? _buyWait;
  bool _restoredAny = false;
  String? _lastError;

  /// Whether the store answered and the Premium catalog is purchasable.
  bool get available => _available && _products.isNotEmpty;

  /// The store's human message for the last failed purchase, if any.
  String? get lastError => _lastError;

  /// One short human-readable line for the error banner. Platform exceptions
  /// stringify with a full native stack trace; users never see that.
  static String _shortError(Object e) {
    var s = '$e';
    const marker = 'Stacktrace:';
    final cut = s.indexOf(marker);
    if (cut > 0) s = s.substring(0, cut);
    s = s.split('\n').first.replaceAll(RegExp(r'\(+$'), '').trim();
    if (s.length > 140) s = '${s.substring(0, 140)}…';
    return s;
  }

  /// Store-localized price for [plan], or null before the catalog loads.
  String? priceOf(PremiumPlan plan) => _products[plan]?.price;

  /// Subscribe to the purchase stream and load the catalog. Safe on every
  /// platform: where the store is missing this quietly leaves [available]
  /// false. [onPremium] fires for every entitlement the store reports,
  /// including renewals delivered on a later launch, together with the signed
  /// proof (iOS: the StoreKit 2 JWS; Android: the Play purchase token) the
  /// provisioning backend validates server-side. [onAvailability] fires once
  /// the catalog finishes loading (or fails to), so a paywall that was hidden
  /// while the store was still answering can appear when it turns out to be
  /// purchasable.
  Future<void> init({
    required void Function(Premium, PurchasePayload? proof) onPremium,
    void Function()? onAvailability,
  }) async {
    _onPremium = onPremium;
    _onAvailability = onAvailability;
    // Under flutter_test there is no store channel; registering the platform
    // would only raise async channel errors inside the test zone.
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    // Listen before anything else: transactions from a previous session are
    // delivered as soon as the platform side connects.
    _sub ??= _iap.purchaseStream.listen(_onPurchases);
    try {
      _available = await _iap.isAvailable();
    } catch (_) {
      _available = false;
    }
    if (!_available) {
      _onAvailability?.call();
      return;
    }
    await _loadCatalog(retries: 3);
    _onAvailability?.call();
  }

  /// Query the store for whatever part of the catalog is still missing.
  /// A flaky network, a just-rebooted store daemon, or slow product
  /// propagation can all drop the first ask; failures here are transient,
  /// never terminal ([buy] asks again on demand).
  Future<void> _loadCatalog({int retries = 1}) async {
    for (var attempt = 0;
        attempt < retries && _products.length < PremiumProducts.all.length;
        attempt++) {
      if (attempt > 0) await Future<void>.delayed(const Duration(seconds: 30));
      try {
        final resp = await _iap.queryProductDetails(PremiumProducts.all);
        for (final p in resp.productDetails) {
          final plan = PremiumProducts.planOf(p.id);
          if (plan != null) _products[plan] = p;
        }
        iapLog('[iap] catalog: '
            '${_products.entries.map((e) => '${e.key.name}=${e.value.price}').join(' ')}'
            '${resp.notFoundIDs.isEmpty ? '' : ' notFound=${resp.notFoundIDs}'}');
      } catch (e) {
        iapLog('[iap] catalog query failed: $e');
      }
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  /// Start the store's purchase flow for [plan] and wait for its outcome.
  Future<PurchaseOutcome> buy(PremiumPlan plan) async {
    var product = _products[plan];
    if (product == null) {
      // The launch-time load can race the network (e.g. right after a
      // reboot); ask the store again now that the user actually wants it.
      try {
        _available = await _iap.isAvailable();
      } catch (_) {}
      if (_available) await _loadCatalog();
      product = _products[plan];
    }
    if (product == null) {
      _lastError = 'The store is not reachable right now.';
      return PurchaseOutcome.failed;
    }
    _lastError = null;
    final wait = _buyWait = Completer<PurchaseOutcome>();
    try {
      await _iap.buyNonConsumable(
          purchaseParam: PurchaseParam(productDetails: product));
    } catch (e) {
      iapLog('[iap] buy threw: $e');
      _lastError = _shortError(e);
      if (!wait.isCompleted) wait.complete(PurchaseOutcome.failed);
    }
    // The sheet can be abandoned in states some platforms never report;
    // mirror the VPN-consent guard so the UI cannot wait forever.
    return wait.future.timeout(const Duration(minutes: 5),
        onTimeout: () => PurchaseOutcome.canceled);
  }

  /// Re-check the store for an existing subscription. True when at least one
  /// purchase came back.
  Future<bool> restore() async {
    if (!_available) return false;
    _restoredAny = false;
    try {
      await _iap.restorePurchases();
    } catch (e) {
      iapLog('[iap] restore threw: $e');
      _lastError = _shortError(e);
      return false;
    }
    // Restored purchases arrive on the stream after the call returns.
    await Future<void>.delayed(const Duration(seconds: 2));
    return _restoredAny;
  }

  void _onPurchases(List<PurchaseDetails> purchases) {
    for (final p in purchases) {
      iapLog('[iap] event: ${p.productID} ${p.status.name}'
          '${p.error == null ? '' : ' error=${p.error!.code}:${p.error!.message}'}'
          ' pendingComplete=${p.pendingCompletePurchase}');
      switch (p.status) {
        case PurchaseStatus.pending:
          break; // the overlay is already up; wait for the final status
        case PurchaseStatus.canceled:
          _finishBuy(PurchaseOutcome.canceled);
        case PurchaseStatus.error:
          _lastError =
              p.error == null ? null : _shortError(p.error!.message);
          _finishBuy(PurchaseOutcome.failed);
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final plan = PremiumProducts.planOf(p.productID);
          if (plan != null) {
            final premium = _premiumFrom(p, plan);
            // Always surface the store's view (an expired sub un-flags a
            // stale local entitlement), but only a live period counts as a
            // successful buy/restore: at launch the store replays old,
            // already-lapsed transactions and those must not masquerade as
            // a fresh purchase.
            _onPremium?.call(premium, _proofFrom(p));
            if (premium.isOn) {
              if (p.status == PurchaseStatus.restored) _restoredAny = true;
              _finishBuy(PurchaseOutcome.success);
            }
          }
      }
      // Mandatory acknowledge: on Android an un-acknowledged purchase is
      // auto-refunded by Google after three days; on iOS this finishes the
      // transaction so it stops replaying. Fires for every terminal status.
      if (p.pendingCompletePurchase) _iap.completePurchase(p);
    }
  }

  /// The signed proof for [p], tagged with the store it came from. On iOS the
  /// verification data is the StoreKit 2 JWS; on Android it is the Play
  /// purchase token. Both go to the provisioning backend, which re-validates
  /// server-side before issuing any access.
  PurchasePayload _proofFrom(PurchaseDetails p) {
    final data = p.verificationData.serverVerificationData;
    return Platform.isAndroid
        ? PurchasePayload.android(purchaseToken: data, productId: p.productID)
        : PurchasePayload.ios(jws: data, productId: p.productID);
  }

  void _finishBuy(PurchaseOutcome outcome) {
    final wait = _buyWait;
    if (wait != null && !wait.isCompleted) wait.complete(outcome);
  }

  /// Entitlement details for the UI. On iOS the verification data is the
  /// StoreKit 2 JWS whose payload carries the real expiry and whether the
  /// introductory (free-trial) offer applies; elsewhere fall back to a
  /// computed period end.
  Premium _premiumFrom(PurchaseDetails p, PremiumPlan plan) {
    DateTime? renews;
    var trial = false;
    final payload = _jwsPayload(p.verificationData.serverVerificationData);
    if (payload != null) {
      final exp = payload['expiresDate'];
      if (exp is num) {
        renews = DateTime.fromMillisecondsSinceEpoch(exp.toInt());
      }
      trial = payload['offerType'] == 1; // 1 = introductory offer
    }
    renews ??= DateTime.now().add(plan == PremiumPlan.yearly
        ? const Duration(days: 365)
        : const Duration(days: 30));
    final expired = renews.isBefore(DateTime.now());
    iapLog('[iap] entitlement: ${plan.name} expires=$renews'
        ' trial=$trial expired=$expired');
    return Premium(
      status: expired
          ? PremiumStatus.expired
          : trial
              ? PremiumStatus.trial
              : PremiumStatus.active,
      plan: plan,
      renews: renews,
    );
  }

  static Map<String, dynamic>? _jwsPayload(String data) {
    final parts = data.split('.');
    if (parts.length != 3) return null;
    try {
      final json =
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
