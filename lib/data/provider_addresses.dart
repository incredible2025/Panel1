import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Approved destinations, in preference order. Never accept remote additions.
const providerPortalUrl = 'https://liquidmetal.vip';
const providerFallbackUrl = 'http://liquidmetal.vip';

/// Permanent local storage identity; changing transport must not change accounts.
const previousProviderPortalUrl = providerFallbackUrl;

bool isConfiguredProviderUri(Uri uri) =>
    uri == Uri.parse(providerPortalUrl) ||
    uri == Uri.parse(providerFallbackUrl);

/// Recognize the retired destination without embedding it as a usable address.
bool isRetiredProviderUri(Uri uri) =>
    sha256.convert(utf8.encode(uri.toString())).toString() ==
    'd31eb9c38688244998fb078460946d4967e021d88bfe296b307aa81b205acdb2';
