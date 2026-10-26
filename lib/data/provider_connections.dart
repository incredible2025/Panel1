import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'provider_addresses.dart';

enum ProviderRoute { api, playback }

String _transportMessage(Object error) => error is http.ClientException
    ? error.message.toLowerCase()
    : error is SocketException
    ? error.message.toLowerCase()
    : '';

bool isCertificateFailure(Object error) {
  if (error is TlsException) return true;
  final text = _transportMessage(error);
  return ['certificate', 'handshake', 'ssl', 'tls'].any(text.contains);
}

bool isDnsFailure(Object error) {
  if (error is! SocketException && error is! http.ClientException) return false;
  final text = _transportMessage(error);
  return [
        'failed host lookup',
        'name or service not known',
        'no such host',
        'nodename nor servname',
        'name resolution',
        'cannot resolve',
      ].any(text.contains) ||
      error is SocketException &&
          [
            -2,
            -3,
            7,
            8,
            11001,
            11002,
            11003,
            11004,
          ].contains(error.osError?.errorCode);
}

/// Only transport reachability failures permit switching. Account responses,
/// HTTP errors, invalid payloads and certificate failures are never downgraded.
bool canSwitchProviderTransport(Object error) {
  if (isCertificateFailure(error) || isDnsFailure(error)) return false;
  if (error is TimeoutException || error is SocketException) return true;
  if (error is! http.ClientException) return false;
  final text = error.message.toLowerCase();
  return [
    'connection refused',
    'connection reset',
    'connection closed',
    'connection aborted',
    'network is unreachable',
    'network unreachable',
    'timed out',
    'broken pipe',
    'reset by peer',
  ].any(text.contains);
}

class _Selection {
  _Selection(this.base, this.at, this.order);
  final Uri base;
  final DateTime at;
  final int order;
}

/// Device-local, memory-only preferences. A fresh launch/resume prefers HTTPS.
/// API and media have independent selections; each operation tries at most two
/// exact approved roots. A short cooldown prevents repeated failed HTTPS probes.
class ProviderConnections {
  ProviderConnections({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;
  final Map<ProviderRoute, _Selection> _selected = {};
  static const cooldown = Duration(minutes: 5);
  int _revision = 0, _order = 0;
  bool _secureOnly = false;

  bool manages(Uri base) =>
      isConfiguredProviderUri(base) || isRetiredProviderUri(base);

  Uri preferred(ProviderRoute route) {
    if (_secureOnly) return Uri.parse(providerPortalUrl);
    final selected =
        _selected[route] ??
        (route == ProviderRoute.playback ? _selected[ProviderRoute.api] : null);
    if (selected != null &&
        !_clock().isBefore(selected.at) &&
        _clock().difference(selected.at) < cooldown) {
      return selected.base;
    }
    return Uri.parse(providerPortalUrl);
  }

  void reset() {
    _revision++;
    _selected.clear();
    _secureOnly = false;
  }

  Future<T> run<T>(
    Uri requested,
    ProviderRoute route,
    Future<T> Function(Uri base) operation,
  ) async {
    if (!manages(requested)) return operation(requested);
    final revision = _revision;
    final order = ++_order;
    final first = preferred(route);
    void remember(Uri base) {
      if (revision == _revision && order >= (_selected[route]?.order ?? 0)) {
        final prior = _selected[route];
        final at = prior != null && prior.base == base && first == base
            ? prior.at
            : _clock();
        _selected[route] = _Selection(base, at, order);
      }
    }

    try {
      final value = await operation(first);
      remember(first);
      return value;
    } catch (error) {
      if (isCertificateFailure(error)) _secureOnly = true;
      if (_secureOnly || !canSwitchProviderTransport(error)) rethrow;
      final second = Uri.parse(
        first.scheme == 'https' ? providerFallbackUrl : providerPortalUrl,
      );
      try {
        final value = await operation(second);
        remember(second);
        return value;
      } catch (error) {
        if (isCertificateFailure(error)) _secureOnly = true;
        rethrow;
      }
    }
  }
}

/// A bounded, headers-only media request verifies this device's route and TLS
/// before opening a native decoder. It does not download or start a video body.
/// Normal TLS verification is retained and redirects are left to the player.
Future<void> probeProviderStream(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
  try {
    await (() async {
      final request = await client.openUrl('HEAD', uri);
      request.followRedirects = false;
      await request.close();
    })().timeout(const Duration(seconds: 6));
  } finally {
    client.close(force: true);
  }
}
