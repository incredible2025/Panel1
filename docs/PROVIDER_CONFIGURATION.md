# Embedded provider configuration

`lib/core/provider_config.dart` contains the operator-controlled portal, currently `http://liquidmetal.vip`. Login and pre-login connection diagnosis construct credentials from this constant and the entered username/password. No editable server field or provider URL is shown in Settings. API/player errors and exported diagnostic reports omit addresses; configuration repair instructions refer customers to support.

This is interface configuration, not a secrecy boundary: an embedded address can be recovered from an APK or network traffic. The configured HTTP portal also uses HTTP for API/stream URLs; hiding its address does not encrypt the connection. HTTPS can be enabled by changing the operator constant when the provider supports it.

At startup, a normalized matching stored session is retained unchanged so its account-scoped history/preferences remain intact. Unrelated saved portals are signed out without deleting their history. This avoids silently forwarding an unrelated provider's stored credentials to a new destination. The next sign-in uses the embedded portal and its own account identity.

Expiry parsing is shared by account display, sign-in and diagnostics. `exp_date: null` on an authorized Active/Unlimited line is treated as Xtream's no-expiry value, distinct from an absent key. Explicit unlimited/lifetime markers are also supported. A real date takes precedence. Missing/invalid information and connection-count limits are not treated as lifetime subscriptions. Account authorization, inactive status and expired timestamps are still enforced.
