import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../data/models.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _server = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _obscured = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _server.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await ref
          .read(apiProvider)
          .authenticate(
            Credentials(
              serverUrl: _server.text.trim(),
              username: _username.text.trim(),
              password: _password.text,
            ),
          );
      await ref.read(storeProvider).saveSession(session);
      if (mounted) ref.read(sessionProvider.notifier).state = session;
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not sign in. Check your server address and account details, and make sure the provider is available.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTv = ref.watch(isTvProvider);
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.75, -0.75),
            radius: 1.65,
            colors: [Color(0xFF153D41), Color(0xFF080E1B)],
            stops: [0, .8],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(isTv ? 32 : 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isTv ? 860 : 430),
                child: FocusTraversalGroup(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth > 650;
                      final brand = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: const Color(0xFF54E1C1),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Color(0xFF0A2227),
                              size: 42,
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'STREAMLINE',
                            style: TextStyle(
                              fontSize: 14,
                              letterSpacing: 4,
                              color: Color(0xFF54E1C1),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Your screen.\nYour streaming.',
                            style: Theme.of(context).textTheme.headlineLarge
                                ?.copyWith(
                                  fontSize: isTv ? 38 : 34,
                                  fontWeight: FontWeight.w800,
                                  height: 1.14,
                                ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Live channels, films and series.\nOne place to pick up where you left off.',
                            style: TextStyle(
                              color: Color(0xFFA4B7C8),
                              fontSize: 15,
                              height: 1.6,
                            ),
                          ),
                          const SizedBox(height: 28),
                          const Row(
                            children: [
                              Icon(
                                Icons.tv,
                                size: 17,
                                color: Color(0xFF78999E),
                              ),
                              SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  'Made for mobile & Android TV',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF91A4B9),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                      final form = Container(
                        padding: const EdgeInsets.all(26),
                        decoration: BoxDecoration(
                          color: const Color(0xF0121D2E),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xFF2A3C4B)),
                        ),
                        child: Form(
                          key: _form,
                          child: AutofillGroup(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Connect your account',
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Enter the Xtream Codes details from your IPTV provider.',
                                  style: TextStyle(
                                    color: Color(0xFF91A4B9),
                                    height: 1.5,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                TextFormField(
                                  controller: _server,
                                  enabled: !_busy,
                                  autofocus: isTv,
                                  decoration: const InputDecoration(
                                    labelText: 'Server URL',
                                    hintText: 'https://provider.example:8080',
                                    prefixIcon: Icon(Icons.dns_outlined),
                                  ),
                                  keyboardType: TextInputType.url,
                                  textInputAction: TextInputAction.next,
                                  autocorrect: false,
                                  validator: (value) {
                                    final uri = Uri.tryParse(
                                      value?.trim() ?? '',
                                    );
                                    if (uri == null ||
                                        ![
                                          'http',
                                          'https',
                                        ].contains(uri.scheme) ||
                                        uri.host.isEmpty) {
                                      return 'Enter an http:// or https:// server URL';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _username,
                                  enabled: !_busy,
                                  autofillHints: const [AutofillHints.username],
                                  autocorrect: false,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: 'Username',
                                    prefixIcon: Icon(Icons.person_outline),
                                  ),
                                  validator: (value) =>
                                      value == null || value.trim().isEmpty
                                      ? 'Enter your username'
                                      : null,
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _password,
                                  enabled: !_busy,
                                  obscureText: _obscured,
                                  autofillHints: const [AutofillHints.password],
                                  autocorrect: false,
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) => _signIn(),
                                  decoration: InputDecoration(
                                    labelText: 'Password',
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    suffixIcon: IconButton(
                                      tooltip: _obscured
                                          ? 'Show password'
                                          : 'Hide password',
                                      onPressed: () => setState(
                                        () => _obscured = !_obscured,
                                      ),
                                      icon: Icon(
                                        _obscured
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                      ),
                                    ),
                                  ),
                                  validator: (value) =>
                                      value == null || value.isEmpty
                                      ? 'Enter your password'
                                      : null,
                                ),
                                if (_error != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 18),
                                    child: Text(
                                      _error!,
                                      style: const TextStyle(
                                        color: Color(0xFFFFB3AB),
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 24),
                                FilledButton(
                                  onPressed: _busy ? null : _signIn,
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 17,
                                    ),
                                  ),
                                  child: _busy
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text('Connect & start watching'),
                                ),
                                const SizedBox(height: 18),
                                const Text(
                                  'Use a subscription you are authorised to access.\nStreamline does not supply channels or content.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Color(0xFF7C93A8),
                                    fontSize: 11,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                      if (wide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(child: brand),
                            const SizedBox(width: 50),
                            Expanded(child: form),
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [brand, const SizedBox(height: 30), form],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
