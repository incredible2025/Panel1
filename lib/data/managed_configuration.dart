import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'models.dart';
import 'provider_addresses.dart';

const androidApplicationId = String.fromEnvironment(
  'ANDROID_APPLICATION_ID',
  defaultValue: 'com.streamline.iptv',
);
const managedProfileJson = String.fromEnvironment(
  'MANAGED_PROFILE',
  defaultValue: primaryManagedProfileJson,
);
const managedLegacyServiceId = String.fromEnvironment(
  'MANAGED_LEGACY_SERVICE_ID',
  defaultValue: primaryLegacyServiceId,
);

/// A build-time trust anchor. Only its public verification key enters the APK.
class ManagedProfile {
  ManagedProfile({
    required this.appId,
    required this.packageId,
    required this.configUrl,
    required this.verificationKey,
    required this.bootstrap,
  });
  final String appId, packageId, verificationKey;
  final Uri configUrl;
  final Map<String, dynamic> bootstrap;

  factory ManagedProfile.parse(
    String source, {
    String packageId = androidApplicationId,
  }) {
    final data = objectValue(jsonDecode(source));
    final appId = data['appId'];
    final key = data['verificationKey'];
    if (appId is! String ||
        !RegExp(r'^[a-z][a-z0-9-]{2,63}$').hasMatch(appId) ||
        data['packageId'] != packageId ||
        key is! String ||
        _decode(key).length != 32) {
      throw const FormatException('Invalid app configuration.');
    }
    return ManagedProfile(
      appId: appId,
      packageId: packageId,
      configUrl: _address(data['configUrl'], httpsOnly: true),
      verificationKey: key,
      bootstrap: objectValue(data['bootstrap']),
    );
  }

  Future<ManagedConfiguration> verify(Map<String, dynamic> envelope) async {
    final encoded = envelope['payload'];
    final signature = envelope['signature'];
    if (encoded is! String || signature is! String || encoded.length > 88000) {
      throw const FormatException('Invalid app configuration.');
    }
    final bytes = _decode(encoded);
    final signatureBytes = _decode(signature);
    if (signatureBytes.length != 64 ||
        !await Ed25519().verify(
          bytes,
          signature: Signature(
            signatureBytes,
            publicKey: SimplePublicKey(
              _decode(verificationKey),
              type: KeyPairType.ed25519,
            ),
          ),
        )) {
      throw const FormatException('App configuration could not be verified.');
    }
    final payload = objectValue(jsonDecode(utf8.decode(bytes)));
    final revision = payload['revision'];
    final serviceId = payload['serviceId'];
    final endpoints = payload['endpoints'];
    if (payload['schemaVersion'] != 1 ||
        payload['appId'] != appId ||
        payload['packageId'] != packageId ||
        revision is! int ||
        revision < 1 ||
        revision > 9007199254740991 ||
        serviceId is! String ||
        !RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        ).hasMatch(serviceId) ||
        endpoints is! List ||
        endpoints.isEmpty ||
        endpoints.length > 2 ||
        payload['issuedAt'] is! String ||
        DateTime.tryParse(payload['issuedAt']) == null) {
      throw const FormatException('Unsupported app configuration.');
    }
    final roots = endpoints
        .map((value) => _address(value, root: true))
        .toList();
    if (roots.toSet().length != roots.length) {
      throw const FormatException('Invalid app configuration.');
    }
    return ManagedConfiguration(
      serviceId: serviceId,
      revision: revision,
      endpoints: List.unmodifiable(roots),
      updateManifestUrl: _address(
        payload['updateManifestUrl'],
        httpsOnly: true,
      ).toString(),
      envelope: Map.unmodifiable({'payload': encoded, 'signature': signature}),
    );
  }
}

List<int> _decode(String value) {
  if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
    throw const FormatException('Invalid encoded configuration.');
  }
  return base64Url.decode(base64Url.normalize(value));
}

Uri _address(dynamic value, {bool httpsOnly = false, bool root = false}) {
  final uri = value is String ? Uri.tryParse(value) : null;
  if (uri == null ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      !{'http', 'https'}.contains(uri.scheme) ||
      httpsOnly && uri.scheme != 'https' ||
      RegExp(r'[\x00-\x20\\]').hasMatch(value as String)) {
    throw const FormatException('Invalid configuration address.');
  }
  // Force validation of a supplied port. Preserve a provider's path prefix.
  if (uri.port < 1 || uri.port > 65535) {
    throw const FormatException('Invalid configuration address.');
  }
  return root
      ? uri.replace(path: uri.path.replaceFirst(RegExp(r'/+$'), ''))
      : uri;
}

class ManagedConfiguration {
  ManagedConfiguration({
    required this.serviceId,
    required this.revision,
    required this.endpoints,
    required this.updateManifestUrl,
    required this.envelope,
  });
  final String serviceId, updateManifestUrl;
  final int revision;
  final List<Uri> endpoints;
  final Map<String, dynamic> envelope;

  Credentials credentials(String username, String password) => Credentials(
    serverUrl: endpoints.first.toString(),
    username: username.trim(),
    password: password,
    managedServiceId: serviceId,
  );
}

/// Last verified settings remain usable offline. Revision checks are performed
/// against both the build bootstrap and a separate, durable signed cache.
class ManagedConfigurationManager extends ChangeNotifier {
  ManagedConfigurationManager({
    required this.profile,
    required this.readCache,
    required this.writeCache,
    http.Client Function()? clientFactory,
    this.deadline = const Duration(seconds: 3),
    this.refreshInterval = const Duration(minutes: 5),
  }) : _clientFactory = clientFactory ?? http.Client.new;
  final ManagedProfile profile;
  final Future<String?> Function() readCache;
  final Future<void> Function(String) writeCache;
  final http.Client Function() _clientFactory;
  final Duration deadline, refreshInterval;
  late ManagedConfiguration current;
  Future<bool>? _refreshing;
  Timer? _timer;
  http.Client? _client;
  Completer<void>? _abort;
  bool _disposed = false;

  Future<void> initialize() async {
    current = await profile.verify(profile.bootstrap);
    try {
      final cache = await readCache();
      if (cache != null) {
        final saved = await profile.verify(objectValue(jsonDecode(cache)));
        if (saved.revision > current.revision) current = saved;
      }
    } catch (_) {
      /* The signed build bootstrap remains available. */
    }
    await refresh();
  }

  void foreground(bool active, {bool refreshNow = true}) {
    _timer?.cancel();
    _timer = null;
    if (!active || _disposed) return;
    if (refreshNow) unawaited(refresh());
    _timer = Timer.periodic(refreshInterval, (_) => unawaited(refresh()));
  }

  Future<bool> refresh() {
    if (_disposed) return Future.value(false);
    return _refreshing ??= _fetch().whenComplete(() => _refreshing = null);
  }

  Future<bool> _fetch() async {
    final client = _clientFactory();
    final abort = Completer<void>();
    _client = client;
    _abort = abort;
    try {
      final candidate =
          await (() async {
            final request =
                http.AbortableRequest(
                    'GET',
                    profile.configUrl,
                    abortTrigger: abort.future,
                  )
                  ..followRedirects = false
                  ..headers['Accept'] = 'application/json';
            final response = await client.send(request);
            if (response.statusCode != 200 ||
                (response.contentLength ?? 0) > 65536) {
              throw const FormatException('Configuration unavailable.');
            }
            final bytes = <int>[];
            await for (final chunk in response.stream) {
              bytes.addAll(chunk);
              if (bytes.length > 65536) {
                throw const FormatException('Configuration too large.');
              }
            }
            return profile.verify(objectValue(jsonDecode(utf8.decode(bytes))));
          })().timeout(
            deadline,
            onTimeout: () {
              if (!abort.isCompleted) abort.complete();
              client.close();
              throw TimeoutException('Configuration check ended.');
            },
          );
      if (_disposed || candidate.revision < current.revision) return false;
      if (candidate.revision == current.revision) return false;
      // Persist before applying, so an accepted revision survives process death.
      await writeCache(jsonEncode(candidate.envelope));
      if (_disposed) return false;
      current = candidate;
      notifyListeners();
      return true;
    } catch (_) {
      return false; // Never expose network addresses, raw responses or signatures.
    } finally {
      if (!abort.isCompleted) abort.complete();
      client.close();
      if (identical(_client, client)) {
        _client = null;
        _abort = null;
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    if (_abort?.isCompleted == false) _abort!.complete();
    _client?.close();
    super.dispose();
  }
}
