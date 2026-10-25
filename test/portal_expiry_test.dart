import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:streamline_iptv/core/provider_config.dart';
import 'package:streamline_iptv/data/app_settings.dart';
import 'package:streamline_iptv/data/models.dart';
import 'package:streamline_iptv/data/xtream_api.dart';

import 'connection_diagnostics_test.dart'
    show FakeDiagnosticTransport, diagnose, at;

Session account(
  Map<String, dynamic> user, {
  String server = providerPortalUrl,
}) => Session(
  credentials: Credentials(
    serverUrl: server,
    username: 'viewer',
    password: 'secret',
  ),
  userInfo: user,
  serverInfo: const {},
);

void main() {
  test(
    'configured portal normalizes existing sessions without changing account history identity',
    () {
      final a = account({});
      expect(
        portalCredentials(' viewer ', ' secret ').serverUrl,
        'http://167.235.169.168',
      );
      expect(portalCredentials(' viewer ', ' secret ').username, 'viewer');
      expect(portalCredentials('viewer', ' secret ').password, ' secret ');
      expect(usesConfiguredPortal(a), true);
      final normalized = account(
        {},
        server: 'http://167.235.169.168/player_api.php',
      );
      expect(usesConfiguredPortal(normalized), true);
      expect(a.accountId, normalized.accountId);
      expect(
        usesConfiguredPortal(account({}, server: 'https://other.example')),
        false,
      );
    },
  );

  for (final marker in [
    {'auth': 1, 'status': 'Active', 'exp_date': null},
    {'exp_date': 'unlimited'},
    {'exp_date': 'Unlimited'},
    {'exp_date': null, 'subscription_type': 'unlimited'},
    {'exp_date': '', 'status': 'Unlimited'},
    {'exp_date': '0', 'is_lifetime': '1'},
    {'no_expiry': true},
  ]) {
    test('explicit unlimited marker has no expiry: $marker', () {
      final info = AccountInfo(account(marker));
      expect(info.neverExpires, true);
      expect(info.expiryLabel, 'Doesn’t expire');
      expect(info.expiring, false);
      expect(info.remainingDays, isNull);
    });
  }
  for (final values in [
    <String, dynamic>{},
    {'auth': 1, 'status': 'Active'},
    {'exp_date': null},
    {'exp_date': 0},
    {'exp_date': 'invalid'},
    {'max_connections': 'unlimited'},
    {'max_connections': '0'},
    {'exp_date': 'invalid', 'is_lifetime': true},
  ]) {
    test(
      'missing, invalid or unlimited connections do not imply unlimited time: $values',
      () {
        final info = AccountInfo(account(values));
        expect(info.neverExpires, false);
        expect(info.expiryLabel, 'Not supplied');
      },
    );
  }

  test(
    'a supplied date takes precedence over an unlimited marker, including an expired date',
    () {
      final info = AccountInfo(account({'exp_date': 1, 'is_lifetime': true}));
      expect(info.neverExpires, false);
      expect(info.expiryLabel, isNot('Doesn’t expire'));
      expect(info.expiring, true);
    },
  );

  test(
    'unlimited status authenticates and diagnostics agree without weakening auth or expiry checks',
    () async {
      final user = {'auth': 1, 'status': 'Unlimited', 'exp_date': null};
      final api = XtreamApi(
        client: MockClient(
          (_) async => http.Response(jsonEncode({'user_info': user}), 200),
        ),
      );
      addTearDown(api.dispose);
      expect(
        AccountInfo(
          await api.authenticate(portalCredentials('viewer', 'secret')),
        ).neverExpires,
        true,
      );
      final t = FakeDiagnosticTransport()..user = user;
      final r = await diagnose(t);
      expect(at(r, 'account').finding.code, 'ACCOUNT_ACTIVE');
      expect(at(r, 'account').finding.description, contains('doesn’t expire'));
      expect(t.calls, contains('get_live_categories'));
      for (final invalid in [
        {'auth': 0, 'status': 'Unlimited', 'exp_date': null},
        {'auth': 1, 'status': 'Unlimited', 'exp_date': 1},
        {'auth': 1, 'status': 'Banned', 'is_lifetime': true},
      ]) {
        final reject = XtreamApi(
          client: MockClient(
            (_) async => http.Response(jsonEncode({'user_info': invalid}), 200),
          ),
        );
        await expectLater(
          reject.authenticate(portalCredentials('viewer', 'secret')),
          throwsA(isA<XtreamApiException>()),
        );
        reject.dispose();
      }
    },
  );
}
