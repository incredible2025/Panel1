import '../data/models.dart';
import '../data/provider_addresses.dart';

export '../data/provider_addresses.dart'
    show providerPortalUrl, providerFallbackUrl;

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
    return isConfiguredProviderUri(
      normalizeServerUri(session.credentials.serverUrl),
    );
  } on FormatException {
    return false;
  }
}

/// Canonicalize approved sessions and migrate only the exact retired destination.
Session? restoreConfiguredSession(Session? saved) {
  if (saved == null) return null;
  try {
    final address = normalizeServerUri(saved.credentials.serverUrl);
    if (address == Uri.parse(providerPortalUrl)) return saved;
    if (!isConfiguredProviderUri(address) && !isRetiredProviderUri(address)) {
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
