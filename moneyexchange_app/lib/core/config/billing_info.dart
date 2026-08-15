/// Payment + billing facts shown across the app (activation screen, billing
/// page). Kept in one place so the numbers and prices never drift between screens.
class BillingInfo {
  const BillingInfo._();

  /// The accounts customers send their subscription payment to.
  static const String zaadNumber = '634480003';
  static const String edahabNumber = '654480003';

  /// The support line (also dialed by the home call button).
  static const String supportNumber = '+252634480003';

  /// Every subscription plan. Some are `visibleToCustomers: false` — they appear
  /// only in the admin billing view (and as a generate-code option), never on the
  /// customer-facing pricing page. Use [customerPlans] for the public page.
  static const List<BillingPlan> plans = [
    BillingPlan(
      name: '1 Month',
      priceUsd: 10,
      period: 'per month',
      tagline: 'Great to get started',
    ),
    BillingPlan(
      name: '1 Month',
      priceUsd: 5,
      period: 'per month',
      tagline: 'Discounted monthly (admin only)',
      visibleToCustomers: false,
    ),
    BillingPlan(
      name: '1 Year',
      priceUsd: 60,
      period: 'per year',
      tagline: 'Best value — save vs monthly',
      highlighted: true,
    ),
    BillingPlan(
      name: 'Full',
      priceUsd: 200,
      period: 'one-time',
      tagline: 'Lifetime access, pay once',
    ),
    BillingPlan(
      name: 'Free Unlimited',
      priceUsd: 0,
      period: 'unlimited',
      tagline: 'No cost, never expires',
    ),
  ];

  /// The plans shown on the customer-facing pricing page (the hidden admin-only
  /// ones, like the $5 monthly, are filtered out).
  static List<BillingPlan> get customerPlans =>
      plans.where((p) => p.visibleToCustomers).toList();
}

/// One subscription tier.
class BillingPlan {
  const BillingPlan({
    required this.name,
    required this.priceUsd,
    required this.period,
    required this.tagline,
    this.highlighted = false,
    this.visibleToCustomers = true,
  });

  final String name;
  final int priceUsd;
  final String period;
  final String tagline;

  /// Whether to visually feature this plan (the recommended one).
  final bool highlighted;

  /// Whether this plan appears on the customer-facing pricing page. Admin-only
  /// plans (e.g. the discounted $5 monthly) set this false — they still show in
  /// the admin billing view and as a generate-code option.
  final bool visibleToCustomers;
}
