/// Subscription state for hideip.net Premium.
///
/// The store (StoreKit / Play Billing) is the source of truth: state changes
/// only in response to store events (see PurchaseService). A copy is persisted
/// locally so the UI knows the standing across launches; server-side receipt
/// validation arrives together with the provisioning backend.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum PremiumStatus { none, trial, active, expired }

enum PremiumPlan { monthly, yearly }

/// Store product identifiers, identical on both stores by design.
class PremiumProducts {
  static const monthly = 'net.hideip.vpn.premium.monthly';
  static const yearly = 'net.hideip.vpn.premium.yearly';
  static const all = {monthly, yearly};

  static String idOf(PremiumPlan plan) =>
      plan == PremiumPlan.yearly ? yearly : monthly;

  static PremiumPlan? planOf(String productId) => switch (productId) {
        monthly => PremiumPlan.monthly,
        yearly => PremiumPlan.yearly,
        _ => null,
      };
}

/// Display data for the two variants of the single Premium plan. Prices are
/// USD fallbacks for when the store catalog has not loaded (yet); live,
/// locale-priced values come through [withPrice].
class PlanInfo {
  final String name;
  final String price;
  final String per;
  final String note;

  /// Whether the first period is the 7-day free trial (yearly only).
  final bool trial;

  const PlanInfo(this.name, this.price, this.per, this.note,
      {this.trial = false});

  static const yearly =
      PlanInfo('Yearly', r'$29.99', 'year', '7-day free trial', trial: true);
  static const monthly =
      PlanInfo('Monthly', r'$4.99', 'month', 'billed monthly');

  static PlanInfo of(PremiumPlan plan) =>
      plan == PremiumPlan.yearly ? yearly : monthly;

  /// The same plan with the store's localized price string.
  PlanInfo withPrice(String price) =>
      PlanInfo(name, price, per, note, trial: trial);
}

class Premium {
  static const _kPrefs = 'premium_v1';

  final PremiumStatus status;
  final PremiumPlan? plan;
  final DateTime? renews;

  const Premium.none()
      : status = PremiumStatus.none,
        plan = null,
        renews = null;

  const Premium({required this.status, this.plan, this.renews});

  bool get isOn =>
      status == PremiumStatus.trial || status == PremiumStatus.active;

  /// Load the persisted standing. A subscription whose period lapsed while
  /// the app was closed comes back as [PremiumStatus.expired]; the next store
  /// event (a renewal arriving on the purchase stream) un-expires it.
  static Future<Premium> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrefs);
    if (raw == null || raw.isEmpty) return const Premium.none();
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      var status = PremiumStatus.values.byName(map['status'] as String);
      final planName = map['plan'] as String?;
      final renewsMs = map['renews'] as int?;
      final renews = renewsMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(renewsMs);
      if (renews != null &&
          renews.isBefore(DateTime.now()) &&
          (status == PremiumStatus.trial || status == PremiumStatus.active)) {
        status = PremiumStatus.expired;
      }
      return Premium(
        status: status,
        plan: planName == null ? null : PremiumPlan.values.byName(planName),
        renews: renews,
      );
    } catch (_) {
      return const Premium.none();
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kPrefs,
        jsonEncode({
          'status': status.name,
          'plan': plan?.name,
          'renews': renews?.millisecondsSinceEpoch,
        }));
  }
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "Jul 26, 2026", matching the prototype's date style without pulling intl.
String formatPremiumDate(DateTime d) =>
    '${_months[d.month - 1]} ${d.day}, ${d.year}';
