import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design_system.dart';
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
    final tv = ref.watch(isTvProvider);
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Stack(
        children: [
          const Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _AperturePainter()),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, viewport) {
                final wide = viewport.maxWidth >= 800;
                final horizontal = tv
                    ? 64.0
                    : wide
                    ? 40.0
                    : 26.0;
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    horizontal,
                    tv ? 36 : 26,
                    horizontal,
                    28,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: math.max(
                        0.0,
                        viewport.maxHeight - (tv ? 64 : 54),
                      ),
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1180),
                        child: FocusTraversalGroup(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _brandHeader(wide),
                              SizedBox(height: wide ? 28 : 30),
                              if (wide)
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      flex: 6,
                                      child: _introduction(context, true, tv),
                                    ),
                                    SizedBox(width: tv ? 84 : 64),
                                    Expanded(
                                      flex: 5,
                                      child: _accountForm(context, tv),
                                    ),
                                  ],
                                )
                              else ...[
                                _introduction(context, false, tv),
                                const SizedBox(height: 30),
                                _accountForm(context, tv),
                              ],
                              SizedBox(height: wide ? 28 : 32),
                              _footer(context, wide, tv),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _brandHeader(bool wide) {
    return Row(
      children: [
        const StreamlineMark(size: 34, wordmark: true),
        const Spacer(),
        if (wide)
          const Text(
            'YOUR PERSONAL SCREEN',
            style: TextStyle(
              color: AppColors.subdued,
              letterSpacing: 2.8,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }

  Widget _introduction(BuildContext context, bool wide, bool tv) {
    final theme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('LIVE TELEVISION. FILMS. SERIES.'),
        SizedBox(height: wide ? 28 : 20),
        Text(
          'Your channels.\nYour cinema.',
          style: theme.displayLarge?.copyWith(
            color: AppColors.text,
            fontSize: tv
                ? 76
                : wide
                ? 66
                : 46,
            height: 1.03,
            letterSpacing: -2.4,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (wide) ...[
          const SizedBox(height: 24),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 350),
            child: Text(
              'One place for what you love watching.\nReady when you are.',
              style: theme.bodyLarge?.copyWith(
                color: AppColors.muted,
                height: 1.65,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(height: 42),
          const SizedBox(width: 48, child: Divider(color: AppColors.accent)),
          const SizedBox(height: 18),
          Row(
            children: [
              const Icon(
                Icons.history_rounded,
                color: AppColors.accent,
                size: 19,
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  'Pick up where you left off.',
                  style: theme.bodyMedium?.copyWith(color: AppColors.muted),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _accountForm(BuildContext context, bool tv) {
    final theme = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: .88),
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .18),
            blurRadius: 44,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(tv ? 28 : 24),
        child: Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Expanded(child: Eyebrow('PROVIDER SIGN IN')),
                    Icon(
                      Icons.north_east_rounded,
                      color: AppColors.accent,
                      size: 18,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Connect your account',
                  style: theme.headlineSmall?.copyWith(
                    color: AppColors.text,
                    fontSize: tv ? 29 : 25,
                    letterSpacing: -.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Enter the Xtream Codes details from your IPTV provider.',
                  style: theme.bodyMedium?.copyWith(
                    color: AppColors.muted,
                    height: 1.6,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _server,
                  enabled: !_busy,
                  autofocus: tv,
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    hintText: 'https://provider.example:8080',
                    prefixIcon: Icon(Icons.language_rounded, size: 20),
                  ),
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  enableSuggestions: false,
                  validator: (value) {
                    final uri = Uri.tryParse(value?.trim() ?? '');
                    if (uri == null ||
                        !['http', 'https'].contains(uri.scheme) ||
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
                  enableSuggestions: false,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
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
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _signIn(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(
                      Icons.lock_outline_rounded,
                      size: 20,
                    ),
                    suffixIcon: IconButton(
                      tooltip: _obscured ? 'Show password' : 'Hide password',
                      onPressed: _busy
                          ? null
                          : () => setState(() => _obscured = !_obscured),
                      icon: Icon(
                        _obscured
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 20,
                      ),
                    ),
                  ),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Enter your password'
                      : null,
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: AppColors.danger,
                          fontSize: 13,
                          height: 1.55,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _signIn,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_busy) ...[
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: MediaQuery.disableAnimationsOf(context)
                              ? const Icon(
                                  Icons.hourglass_empty_rounded,
                                  size: 18,
                                )
                              : const CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Flexible(
                        child: Text(
                          _busy ? 'Connecting…' : 'Connect & start watching',
                        ),
                      ),
                      if (!_busy) ...[
                        const SizedBox(width: 14),
                        const Icon(Icons.arrow_forward_rounded, size: 19),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.lock_outline_rounded,
                      size: 14,
                      color: AppColors.subdued,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your account is saved securely on this device.',
                        style: theme.bodySmall?.copyWith(
                          color: AppColors.subdued,
                          height: 1.5,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _footer(BuildContext context, bool wide, bool tv) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(color: AppColors.border, height: 1),
        const SizedBox(height: 20),
        Flex(
          direction: wide ? Axis.horizontal : Axis.vertical,
          crossAxisAlignment: wide
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Text(
              'Streamline does not supply channels or content.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.subdued,
                fontSize: 11,
                height: 1.5,
              ),
            ),
            if (wide) const Spacer() else const SizedBox(height: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  tv ? Icons.settings_remote_outlined : Icons.devices_rounded,
                  size: 15,
                  color: AppColors.subdued,
                ),
                const SizedBox(width: 8),
                Text(
                  tv
                      ? 'Use your remote to navigate and select'
                      : 'Mobile & Android TV',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.subdued,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// Static aperture outlines and grazing light create atmosphere without an
/// invented content catalog, network assets, or continuous animation.
class _AperturePainter extends CustomPainter {
  const _AperturePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(bounds, Paint()..color = AppColors.canvas);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.8, -.3),
          radius: 1.2,
          colors: [
            AppColors.accent.withValues(alpha: .075),
            AppColors.canvas.withValues(alpha: 0),
          ],
        ).createShader(bounds),
    );
    canvas.save();
    canvas.translate(size.width * .18, size.height * .42);
    canvas.rotate(-.38);
    final extent = math.max(size.width, size.height);
    for (var i = 0; i < 6; i++) {
      final inset = i * extent * .048;
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: extent * .72 + inset,
        height: extent * 1.1 + inset,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(80)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = i == 0 ? 1.2 : .65
          ..color = AppColors.accent.withValues(
            alpha: i == 0 ? .12 : .025 + i * .009,
          ),
      );
    }
    canvas.restore();
    final beam = Path()
      ..moveTo(size.width * .07, 0)
      ..lineTo(size.width * .38, 0)
      ..lineTo(size.width * .8, size.height)
      ..lineTo(size.width * .72, size.height)
      ..close();
    canvas.drawPath(
      beam,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.accent.withValues(alpha: .025),
            Colors.transparent,
          ],
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(covariant _AperturePainter oldDelegate) => false;
}
