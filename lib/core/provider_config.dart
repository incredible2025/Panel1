import '../data/models.dart';
import '../data/provider_addresses.dart';
import '../data/managed_configuration.dart';
import '../data/local_store.dart';

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

/// Bind only this build's explicitly approved legacy service. Reseller builds
/// must opt into that one-time migration; arbitrary saved credentials are never
/// forwarded to a newly configured service.
Future<Session?> restoreManagedSession(
  LocalStore store,
  Session? saved,
  ManagedConfiguration config, {
  required bool migrateLegacy,
}) async {
  if (saved == null) return null;
  final service = saved.credentials.managedServiceId;
  if (service != null && service != config.serviceId) return null;
  if (service == null &&
      (!migrateLegacy || restoreConfiguredSession(saved) == null)) {
    return null;
  }
  return store.bindManagedAccount(
    Session(
      credentials: config.credentials(
        saved.credentials.username,
        saved.credentials.password,
      ),
      userInfo: saved.userInfo,
      serverInfo: saved.serverInfo,
      storageAccountId: saved.storageAccountId,
    ),
    legacyAccountId: service == null ? saved.accountId : saved.storageAccountId,
  );
}
