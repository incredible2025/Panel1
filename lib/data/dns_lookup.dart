import 'dart:io';

enum DnsFamily { ipv4, ipv6, system }

enum DnsError {
  timeout,
  temporary,
  notFound,
  noAddress,
  unreachable,
  refused,
  permission,
  parse,
  noNetwork,
  networkChanged,
  busy,
  system,
}

class DnsObservation {
  const DnsObservation(
    this.family, {
    this.responseCode,
    this.error,
    this.addressCount = 0,
    this.osCode,
    this.elapsedMs,
  });
  final DnsFamily family;
  final int? responseCode, osCode, elapsedMs;
  final DnsError? error;
  final int addressCount;

  String get evidence {
    final label = switch (family) {
      DnsFamily.ipv4 => 'A / IPv4',
      DnsFamily.ipv6 => 'AAAA / IPv6',
      DnsFamily.system => 'System lookup',
    };
    final reason = error != null
        ? switch (error!) {
            DnsError.timeout => 'lookup deadline exceeded',
            DnsError.temporary => 'temporary resolver failure',
            DnsError.notFound =>
              'system resolver reported name/address not found',
            DnsError.noAddress => 'no usable address returned',
            DnsError.unreachable => 'network or resolver route unavailable',
            DnsError.refused => 'connection to the resolver refused',
            DnsError.permission => 'operating system denied the lookup',
            DnsError.parse => 'Android could not parse the DNS answer',
            DnsError.noNetwork => 'no active network available',
            DnsError.networkChanged => 'active network changed during lookup',
            DnsError.busy => 'device resolver worker unavailable',
            DnsError.system =>
              'system resolver error; no DNS response code available',
          }
        : responseCode != null
        ? '${switch (responseCode) {
            0 => 'NOERROR',
            1 => 'FORMERR',
            2 => 'SERVFAIL',
            3 => 'NXDOMAIN',
            4 => 'NOTIMP',
            5 => 'REFUSED',
            _ => 'DNS response',
          }} ($responseCode); $addressCount usable address(es)'
        : '$addressCount usable address(es); DNS response code unavailable';
    return '$label: $reason${osCode == null ? '' : '; OS code $osCode'}${elapsedMs == null ? '' : '; $elapsedMs ms'}.';
  }
}

class DnsLookupResult {
  const DnsLookupResult(
    this.addresses, {
    this.observations = const [],
    this.androidResolver = false,
    this.cacheBypassed = false,
    this.networkChanged = false,
  });
  final List<InternetAddress> addresses;
  final List<DnsObservation> observations;
  final bool androidResolver, cacheBypassed, networkChanged;

  /// Only allowlisted enums and bounded numeric metadata leave the bridge.
  /// Native strings, resolver names, hostnames and returned IPs are never
  /// interpolated into evidence or the copied report.
  factory DnsLookupResult.fromPlatform(Map<dynamic, dynamic> raw) {
    int? number(dynamic value, int max) =>
        value is int && value >= 0 && value <= max ? value : null;
    final addresses = <InternetAddress>[];
    if (raw['addresses'] case final List values) {
      for (final value in values.take(64)) {
        final ip = value is String ? InternetAddress.tryParse(value) : null;
        if (ip != null && !addresses.any((a) => a.address == ip.address)) {
          addresses.add(ip);
        }
      }
    }
    final observations = <DnsObservation>[];
    if (raw['queries'] case final List queries) {
      for (final query in queries.take(2)) {
        if (query is! Map) continue;
        final errorName = query['error'];
        final error = errorName == null
            ? null
            : DnsError.values.where((e) => e.name == errorName).firstOrNull ??
                  DnsError.system;
        observations.add(
          DnsObservation(
            switch (query['family']) {
              'A' => DnsFamily.ipv4,
              'AAAA' => DnsFamily.ipv6,
              _ => DnsFamily.system,
            },
            responseCode: number(query['rcode'], 4095),
            error: error,
            addressCount: number(query['count'], 65535) ?? 0,
            osCode:
                query['osCode'] is int &&
                    (query['osCode'] as int).abs() <= 2147483647
                ? query['osCode'] as int
                : null,
            elapsedMs: number(query['elapsedMs'], 60000),
          ),
        );
      }
    }
    return DnsLookupResult(
      List.unmodifiable(addresses),
      observations: List.unmodifiable(observations),
      androidResolver: raw['mode'] == 'android',
      cacheBypassed: raw['cacheBypassed'] == true,
      networkChanged: raw['networkChanged'] == true,
    );
  }
}
