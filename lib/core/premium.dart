/// Subscription state for hideip.net Premium.
///
/// The store (StoreKit / Play Billing) is the source of truth once purchases
/// ship; nothing here is persisted locally. Until then the app stays in
/// [PremiumStatus.none] and the paywall flow is gated off by kPlansAvailable.
library;

enum PremiumStatus { none, trial, active, expired }

enum PremiumPlan { monthly, yearly }

/// Display data for the two variants of the single Premium plan.
class PlanInfo {
  final String name;
  final String price;
  final String per;
  final String note;
  const PlanInfo(this.name, this.price, this.per, this.note);

  static const yearly = PlanInfo('Yearly', r'$29.99', 'year', r'$2.50 per month');
  static const monthly = PlanInfo('Monthly', r'$4.99', 'month', 'billed monthly');

  static PlanInfo of(PremiumPlan plan) =>
      plan == PremiumPlan.yearly ? yearly : monthly;
}

class Premium {
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
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "Jul 26, 2026", matching the prototype's date style without pulling intl.
String formatPremiumDate(DateTime d) =>
    '${_months[d.month - 1]} ${d.day}, ${d.year}';
