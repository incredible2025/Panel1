import '../data/models.dart';

/// Operator-managed portal. Customers enter only their account credentials.
const providerPortalUrl = 'http://liquidmetal.vip';

Credentials portalCredentials(String username, String password) => Credentials(
  serverUrl: providerPortalUrl,
  username: username.trim(),
  password: password,
);

/// Keep existing accounts on this portal, with their original account IDs.
/// An account from a different provider must sign in again rather than silently
/// forwarding its stored password to a different service.
bool usesConfiguredPortal(Session session) {
  try {
    return normalizeServerUri(session.credentials.serverUrl) ==
        normalizeServerUri(providerPortalUrl);
  } on FormatException {
    return false;
  }
}
