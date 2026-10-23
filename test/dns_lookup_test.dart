import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:streamline_iptv/data/connection_diagnostics.dart';
import 'package:streamline_iptv/data/dns_lookup.dart';

import 'connection_diagnostics_test.dart'
    show FakeDiagnosticTransport, diagnose, at;

void main() {
  for (final entry in {
    3: 'DNS_NXDOMAIN',
    2: 'DNS_SERVFAIL',
    5: 'DNS_REFUSED',
    1: 'DNS_PROTOCOL',
    4: 'DNS_PROTOCOL',
  }.entries) {
    test(
      'DNS response ${entry.key} explains the observation and stops credentials',
      () async {
        final t = FakeDiagnosticTransport()
          ..dnsResult = DnsLookupResult(
            const [],
            androidResolver: true,
            cacheBypassed: true,
            observations: [
              DnsObservation(
                DnsFamily.ipv4,
                responseCode: entry.key,
                elapsedMs: 25,
              ),
              DnsObservation(
                DnsFamily.ipv6,
                responseCode: entry.key,
                elapsedMs: 27,
              ),
            ],
          );
        final report = await diagnose(t);
        final f = at(report, 'dns').finding;
        expect(f.code, entry.value);
        expect(f.status, DiagnosticStatus.failed);
        expect(f.evidence.join(' '), contains('(${entry.key})'));
        expect(f.evidence.join(' '), contains('25 ms'));
        expect(f.steps, isNotEmpty);
        expect(f.description, contains('do not prove an ISP block'));
        expect(t.uris, isEmpty);
        expect(at(report, 'tcp').finding.status, DiagnosticStatus.skipped);
      },
    );
  }

  test(
    'IPv4-only and IPv6-only hosts pass without a missing-family warning',
    () async {
      for (final ipv4 in [true, false]) {
        final t = FakeDiagnosticTransport()
          ..dnsResult = DnsLookupResult(
            [InternetAddress(ipv4 ? '192.0.2.1' : '2001:db8::1')],
            androidResolver: true,
            observations: [
              DnsObservation(
                DnsFamily.ipv4,
                responseCode: 0,
                addressCount: ipv4 ? 1 : 0,
              ),
              DnsObservation(
                DnsFamily.ipv6,
                responseCode: 0,
                addressCount: ipv4 ? 0 : 1,
              ),
            ],
          );
        final r = await diagnose(t);
        expect(at(r, 'dns').finding.code, 'DNS_RESOLVED');
        expect(r.warnings, 0);
        expect(t.calls, contains('api'));
        expect(r.toText(), isNot(contains('192.0.2.1')));
        expect(r.toText(), isNot(contains('2001:db8::1')));
      }
    },
  );

  test(
    'one family timeout warns but a usable address permits provider tests',
    () async {
      final t = FakeDiagnosticTransport()
        ..dnsResult = DnsLookupResult(
          [InternetAddress('192.0.2.1')],
          androidResolver: true,
          observations: const [
            DnsObservation(DnsFamily.ipv4, responseCode: 0, addressCount: 1),
            DnsObservation(
              DnsFamily.ipv6,
              error: DnsError.timeout,
              elapsedMs: 8000,
            ),
          ],
        );
      final r = await diagnose(t);
      expect(at(r, 'dns').finding.code, 'DNS_PARTIAL');
      expect(at(r, 'dns').finding.status, DiagnosticStatus.warning);
      expect(
        at(r, 'dns').finding.description,
        contains('No DNS response code'),
      );
      expect(t.calls, contains('api'));
    },
  );

  test(
    'mixed family errors preserve both explanations and codes in the report',
    () async {
      final t = FakeDiagnosticTransport()
        ..dnsResult = const DnsLookupResult(
          [],
          androidResolver: true,
          observations: [
            DnsObservation(DnsFamily.ipv4, responseCode: 2),
            DnsObservation(
              DnsFamily.ipv6,
              error: DnsError.timeout,
              osCode: 110,
            ),
          ],
        );
      final r = await diagnose(t);
      expect(at(r, 'dns').finding.code, 'DNS_MIXED_FAILURE');
      expect(r.toText(), contains('Observed: A / IPv4: SERVFAIL (2)'));
      expect(
        r.toText(),
        contains(
          'Observed: AAAA / IPv6: lookup deadline exceeded; OS code 110',
        ),
      );
      expect(
        at(r, 'dns').finding.description,
        contains('No DNS response code'),
      );
      expect(t.uris, isEmpty);
    },
  );

  test(
    'network change discards even successful DNS answers and skips provider requests',
    () async {
      final t = FakeDiagnosticTransport()
        ..dnsResult = DnsLookupResult([
          InternetAddress('192.0.2.1'),
        ], networkChanged: true);
      final r = await diagnose(t);
      expect(at(r, 'dns').finding.code, 'DNS_NETWORK_CHANGED');
      expect(t.uris, isEmpty);
      expect(t.calls, ['network', 'dns']);
    },
  );

  test(
    'NOERROR with no addresses fails honestly without inventing NXDOMAIN',
    () {
      final f = dnsFinding(
        const DnsLookupResult(
          [],
          androidResolver: true,
          observations: [
            DnsObservation(DnsFamily.ipv4, responseCode: 0),
            DnsObservation(DnsFamily.ipv6, responseCode: 0),
          ],
        ),
      );
      expect(f.code, 'DNS_NO_ADDRESS');
      expect(f.status, DiagnosticStatus.failed);
      expect(f.description, isNot(contains('NXDOMAIN')));
    },
  );

  test(
    'bridge data is bounded and untrusted strings never enter safe evidence',
    () {
      final result = DnsLookupResult.fromPlatform({
        'addresses': ['192.0.2.1', 'not an address', '192.0.2.1'],
        'mode': 'android',
        'cacheBypassed': true,
        'queries': [
          {
            'family': 'A',
            'rcode': 4096,
            'error': 'private-pass https://secret.example',
            'osCode': 34,
            'elapsedMs': -1,
            'count': 'secret',
          },
          {
            'family': 'secret.example',
            'rcode': 'secret',
            'osCode': 'private-pass',
            'elapsedMs': 9999999999,
          },
          {'family': 'AAAA', 'error': 'private-pass'},
        ],
      });
      expect(result.addresses.length, 1);
      expect(result.observations.length, 2);
      expect(result.observations.first.error, DnsError.system);
      expect(result.observations.first.responseCode, isNull);
      expect(result.observations.first.elapsedMs, isNull);
      expect(result.observations.first.osCode, 34);
      final text = DiagnosticReport(DateTime.utc(2026), [
        DiagnosticCheck('dns', dnsFinding(result), 1),
      ]).toText();
      for (final secret in ['private-pass', 'secret.example', '192.0.2.1']) {
        expect(text, isNot(contains(secret)));
      }
      expect(
        DnsLookupResult.fromPlatform({
          'queries': [null, 2],
          'addresses': 'secret',
        }).addresses,
        isEmpty,
      );
    },
  );

  test('older Android system errors do not assert a DNS response code', () {
    final f = dnsFinding(
      const DnsLookupResult(
        [],
        observations: [
          DnsObservation(DnsFamily.system, error: DnsError.system, osCode: 7),
        ],
      ),
    );
    expect(f.code, 'DNS_FAILED');
    expect(
      f.evidence.join(' '),
      contains('exact DNS response codes are unavailable'),
    );
    expect(f.evidence.join(' '), contains('OS code 7'));
    expect(f.description, isNot(contains('NXDOMAIN')));
  });
}
