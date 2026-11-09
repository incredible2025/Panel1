import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Legacy bootstrap destinations. Managed builds use only signed configurations
/// verified against the public key and app identity embedded at build time.
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

/// Public trust anchor and signed offline bootstrap for the primary brand.
const primaryManagedProfileJson =
    r'''{"appId":"ultravpn-player","packageId":"com.streamline.iptv","configUrl":"https://185.245.83.92/app-manager/api/v1/apps/ultravpn-player/config","verificationKey":"TdnRJiXZBSU97UM4IYTHiL383vC23n1p0jLn-q70X_k","bootstrap":{"payload":"eyJzY2hlbWFWZXJzaW9uIjoxLCJhcHBJZCI6InVsdHJhdnBuLXBsYXllciIsInBhY2thZ2VJZCI6ImNvbS5zdHJlYW1saW5lLmlwdHYiLCJzZXJ2aWNlSWQiOiIxNmMzODhiMS1jOTE0LTQ1ZDYtOGE3Ni1kYTVjODhmMjMxZjkiLCJyZXZpc2lvbiI6MSwiZW5kcG9pbnRzIjpbImh0dHBzOi8vbGlxdWlkbWV0YWwudmlwIiwiaHR0cDovL2xpcXVpZG1ldGFsLnZpcCJdLCJ1cGRhdGVNYW5pZmVzdFVybCI6Imh0dHBzOi8vdWx0cmEtdnBuLnN0b3JlL2RsL2FwcC91cGRhdGUuanNvbiIsImlzc3VlZEF0IjoiMjAyNi0xMS0wOVQwNzowODoyNiswMDowMCJ9","signature":"oojZAk4HPiCypOislFxE6qwhxCHF1y9nHPtQ15ee-FxcFGz5GuX7-9zWYkhR670TaAEhdx-AtzuWQEODcVMvAQ"}}''';
const primaryLegacyServiceId = '16c388b1-c914-45d6-8a76-da5c88f231f9';
