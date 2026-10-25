import '../data/models.dart';
import '../data/provider_addresses.dart';

export '../data/provider_addresses.dart' show providerPortalUrl;

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

/// The operator explicitly moved this service from its old domain to this IP.
/// Migrate only that exact previous portal; unrelated providers remain signed out.
Session? restoreConfiguredSession(Session? saved) {
  if (saved == null) return null;
  if (usesConfiguredPortal(saved)) return saved;
  try {
    if (normalizeServerUri(saved.credentials.serverUrl) !=
        normalizeServerUri(previousProviderPortalUrl)) {
      return null;
    }
    return Session(
      credentials: portalCredentials(
        saved.credentials.username,
        saved.credentials.password,
      ),
      userInfo: saved.userInfo,
      serverInfo: saved.serverInfo,
    );
  } on FormatException {
    return null;
  }
}
