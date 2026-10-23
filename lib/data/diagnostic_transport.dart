import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'dns_lookup.dart';

class DeviceNetwork {
  const DeviceNetwork({
    this.connected,
    this.validated,
    this.captivePortal = false,
    this.vpn,
    this.privateDns,
    this.privateDnsStrict,
    this.dnsServerCount,
    this.metered,
    this.transports = const [],
  });
  final bool? connected, validated, vpn, privateDns, privateDnsStrict, metered;
  final int? dnsServerCount;
  final bool captivePortal;
  final List<String> transports;
}

class ProbeResponse {
  const ProbeResponse(this.status, this.bytes, {this.contentType = ''});
  final int status;
  final List<int> bytes;
  final String contentType;
}

/// Deliberately contains no native error message, host, URL or credentials.
class ProbeFailure implements Exception {
  const ProbeFailure(this.code);
  final String code;
  @override
  String toString() => 'ProbeFailure($code)';
}

abstract class DiagnosticTransport {
  Future<DeviceNetwork> network();
  Future<DnsLookupResult> lookup(String host);
  Future<void> connect(String host, int port);
  Future<void> tls(String host, int port);
  Future<ProbeResponse> get(Uri uri, {bool stream = false});
  void close();
}

/// Short-lived, bounded probes. Normal platform certificate checks stay on.
/// Redirects are reported, never followed with Xtream credentials.
class IoDiagnosticTransport implements DiagnosticTransport {
  IoDiagnosticTransport({
    this.timeout = const Duration(seconds: 8),
    bool? useNativeDns,
    Future<List<InternetAddress>> Function(String)? systemLookup,
  }) : useNativeDns = useNativeDns ?? Platform.isAndroid,
       _systemLookup = systemLookup ?? InternetAddress.lookup;
  final Duration timeout;
  final bool useNativeDns;
  final Future<List<InternetAddress>> Function(String) _systemLookup;
  static const _platform = MethodChannel('streamline/platform');
  static int _nextDnsId = 0;
  final _dnsIds = <String>{};
  static const apiLimit = 512 * 1024;
  static const streamLimit = 64 * 1024;
  final _clients = <HttpClient>{};
  final _sockets = <Socket>{};
  bool _closed = false;
  void _check() {
    if (_closed) throw const ProbeFailure('cancelled');
  }

  @override
  Future<DeviceNetwork> network() async {
    _check();
    try {
      final raw = await const MethodChannel('streamline/platform')
          .invokeMapMethod<String, dynamic>('networkDiagnosis')
          .timeout(const Duration(seconds: 3));
      _check();
      if (raw == null) return const DeviceNetwork();
      bool? flag(String key) => raw[key] is bool ? raw[key] as bool : null;
      final names = raw['transports'];
      return DeviceNetwork(
        connected: flag('connected'),
        validated: flag('validated'),
        captivePortal: flag('captivePortal') == true,
        vpn: flag('vpn'),
        privateDns: flag('privateDns'),
        privateDnsStrict: flag('privateDnsStrict'),
        dnsServerCount:
            raw['dnsServerCount'] is int &&
                (raw['dnsServerCount'] as int) >= 0 &&
                (raw['dnsServerCount'] as int) <= 64
            ? raw['dnsServerCount'] as int
            : null,
        metered: flag('metered'),
        transports: names is List
            ? names
                  .whereType<String>()
                  .where(
                    const {
                      'Wi-Fi',
                      'Ethernet',
                      'Mobile',
                      'VPN',
                      'Other',
                    }.contains,
                  )
                  .toList()
            : const [],
      );
    } on ProbeFailure {
      rethrow;
    } catch (_) {
      return const DeviceNetwork();
    }
  }

  @override
  Future<DnsLookupResult> lookup(String host) async {
    _check();
    if (useNativeDns) {
      final id = 'dns-${++_nextDnsId}';
      _dnsIds.add(id);
      try {
        final raw = await _platform
            .invokeMapMethod<dynamic, dynamic>('dnsDiagnosis', {
              'host': host,
              'id': id,
              'timeoutMs': timeout.inMilliseconds.clamp(100, 8000),
            })
            .timeout(timeout + const Duration(seconds: 1));
        _check();
        return DnsLookupResult.fromPlatform(raw ?? const {});
      } on MissingPluginException {
        // Older app embeddings and non-Android development environments.
      } on TimeoutException {
        _check();
        return const DnsLookupResult(
          [],
          observations: [
            DnsObservation(DnsFamily.system, error: DnsError.timeout),
          ],
        );
      } on ProbeFailure {
        rethrow;
      } catch (_) {
        _check();
        return const DnsLookupResult(
          [],
          observations: [
            DnsObservation(DnsFamily.system, error: DnsError.system),
          ],
        );
      } finally {
        _dnsIds.remove(id);
        _cancelDns(id);
      }
    }
    final watch = Stopwatch()..start();
    try {
      final addresses = await _systemLookup(host).timeout(timeout);
      _check();
      return DnsLookupResult(
        addresses,
        observations: [
          DnsObservation(
            DnsFamily.system,
            addressCount: addresses.length,
            error: addresses.isEmpty ? DnsError.noAddress : null,
            elapsedMs: watch.elapsedMilliseconds,
          ),
        ],
      );
    } on ProbeFailure {
      rethrow;
    } catch (error) {
      _check();
      return DnsLookupResult(
        [],
        observations: [
          DnsObservation(
            DnsFamily.system,
            error: error is TimeoutException
                ? DnsError.timeout
                : DnsError.system,
            osCode: error is SocketException ? error.osError?.errorCode : null,
            elapsedMs: watch.elapsedMilliseconds,
          ),
        ],
      );
    }
  }

  void _cancelDns(String id) {
    unawaited(
      _platform
          .invokeMethod<void>('cancelDnsDiagnosis', {'id': id})
          .then<void>((_) {}, onError: (Object _) {}),
    );
  }

  Future<void> _socket(String host, int port) async {
    _check();
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      _sockets.add(socket);
      _check();
    } catch (error) {
      throw _failure(error);
    } finally {
      socket?.destroy();
      _sockets.remove(socket);
    }
  }

  @override
  Future<void> connect(String host, int port) => _socket(host, port);
  @override
  Future<void> tls(String host, int port) async {
    _check();
    final client = HttpClient()..connectionTimeout = timeout;
    _clients.add(client);
    try {
      // getUrl establishes the connection and verifies TLS before returning.
      // Abort before sending an HTTP request; force-close also cancels a stalled
      // handshake, which SecureSocket.connect's TCP timeout alone does not cover.
      final request = await client
          .getUrl(Uri(scheme: 'https', host: host, port: port))
          .timeout(timeout);
      unawaited(request.done.then<void>((_) {}, onError: (Object _) {}));
      request.abort();
      _check();
    } catch (error) {
      throw _failure(error);
    } finally {
      client.close(force: true);
      _clients.remove(client);
    }
  }

  @override
  Future<ProbeResponse> get(Uri uri, {bool stream = false}) async {
    _check();
    final client = HttpClient()..connectionTimeout = timeout;
    _clients.add(client);
    try {
      return await (() async {
        final request = await client.getUrl(uri);
        _check();
        request.followRedirects = false;
        request.headers.set(
          HttpHeaders.acceptHeader,
          stream ? '*/*' : 'application/json',
        );
        request.headers.set(
          HttpHeaders.userAgentHeader,
          'UltraVPNPlayer-Diagnostics',
        );
        if (stream &&
            (uri.pathSegments.contains('movie') ||
                uri.pathSegments.contains('series'))) {
          request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-65535');
        }
        final response = await request.close();
        _check();
        final status = response.statusCode;
        final contentType = response.headers.contentType?.mimeType ?? '';
        // An error body may contain credentials or be arbitrarily large.
        if (status < 200 || status >= 300) {
          return ProbeResponse(status, const [], contentType: contentType);
        }
        final limit = stream ? streamLimit : apiLimit;
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response) {
          _check();
          final remaining = limit - bytes.length;
          if (!stream && chunk.length > remaining) {
            throw const ProbeFailure('response_too_large');
          }
          bytes.add(
            chunk.length > remaining ? chunk.sublist(0, remaining) : chunk,
          );
          if (stream && bytes.length >= limit) break;
        }
        return ProbeResponse(
          status,
          bytes.takeBytes(),
          contentType: contentType,
        );
      })().timeout(timeout);
    } catch (error) {
      throw _failure(error);
    } finally {
      client.close(force: true);
      _clients.remove(client);
    }
  }

  ProbeFailure _failure(Object error) {
    if (_closed) return const ProbeFailure('cancelled');
    if (error is ProbeFailure) return error;
    if (error is TimeoutException) return const ProbeFailure('timeout');
    if (error is CertificateException) return const ProbeFailure('certificate');
    if (error is HandshakeException) {
      final reason = '${error.message} ${error.osError?.message ?? ''}'
          .toLowerCase();
      return ProbeFailure(
        reason.contains('certificate') ? 'certificate' : 'tls_handshake',
      );
    }
    if (error is SocketException) {
      final code = error.osError?.errorCode;
      if ({111, 61, 10061}.contains(code)) return const ProbeFailure('refused');
      if ({110, 60, 10060}.contains(code)) return const ProbeFailure('timeout');
      if ({101, 113, 51, 65, 10051, 10065}.contains(code)) {
        return const ProbeFailure('unreachable');
      }
      return const ProbeFailure('socket');
    }
    if (error is HttpException) return const ProbeFailure('http_protocol');
    return const ProbeFailure('unexpected');
  }

  @override
  void close() {
    _closed = true;
    for (final id in _dnsIds.toList()) {
      _cancelDns(id);
    }
    _dnsIds.clear();
    for (final client in _clients.toList()) {
      client.close(force: true);
    }
    for (final socket in _sockets.toList()) {
      socket.destroy();
    }
    _clients.clear();
    _sockets.clear();
  }
}
