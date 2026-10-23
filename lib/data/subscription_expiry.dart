import 'models.dart';

/// An absent timestamp alone does not mean an unlimited subscription.
class SubscriptionExpiry {
  const SubscriptionExpiry(this.values);
  final Map<String, dynamic> values;

  int? get seconds {
    final value = int.tryParse(textValue(values['exp_date']));
    return value != null && value > 0 && value <= 8640000000000 ? value : null;
  }

  bool get neverExpires {
    final raw = textValue(values['exp_date']).trim().toLowerCase();
    const markers = {
      'unlimited',
      'lifetime',
      'never',
      'no expiry',
      'never expires',
    };
    final absent = {'', '0', 'null'}.contains(raw) || markers.contains(raw);
    if (!absent || seconds != null) return false;
    bool flag(String key) =>
        values[key] == true || textValue(values[key]) == '1';
    // Xtream's explicit null on an authorized active line denotes no expiry.
    // A missing key, invalid date, or unlimited connection count does not.
    final explicitNull =
        values.containsKey('exp_date') &&
        values['exp_date'] == null &&
        (values['auth'] == true || textValue(values['auth']) == '1') &&
        {
          'active',
          'unlimited',
        }.contains(textValue(values['status']).trim().toLowerCase());
    return explicitNull ||
        markers.contains(raw) ||
        flag('is_lifetime') ||
        flag('no_expiry') ||
        ['expiry', 'expiration', 'subscription_type', 'status'].any(
          (key) =>
              markers.contains(textValue(values[key]).trim().toLowerCase()),
        );
  }

  bool get activeStatus {
    final status = textValue(values['status']).trim().toLowerCase();
    return status.isEmpty || status == 'active' || status == 'unlimited';
  }
}
