import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design_system.dart';
import '../core/providers.dart';
import '../core/provider_config.dart';
import '../core/update_controller.dart';
import '../data/xtream_api.dart';
import '../widgets/tv_controls.dart';
import '../widgets/tv_glass_theme.dart';
import '../widgets/tv_text_entry_dialog.dart';
import 'connection_diagnosis_screen.dart';
import 'app_updates_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _tvUsername = FocusNode(debugLabel: 'Login username');
  final _tvPassword = FocusNode(debugLabel: 'Login password');
  final _tvConnect = FocusNode(debugLabel: 'Login connect');
  final _tvUpdates = FocusNode(debugLabel: 'Login updates');
  final _tvDiagnosis = FocusNode(debugLabel: 'Login diagnosis');
  bool _obscured = true;
  bool _busy = false;
  bool _editing = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _tvUsername.dispose();
    _tvPassword.dispose();
    _tvConnect.dispose();
    _tvUpdates.dispose();
    _tvDiagnosis.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_busy || _editing) return;
    if (ref.read(isTvProvider)) {
      if (_username.text.trim().isEmpty || _password.text.isEmpty) {
        setState(
          () => _error = _username.text.trim().isEmpty
              ? 'Enter your username'
              : 'Enter your password',
        );
        (_username.text.trim().isEmpty ? _tvUsername : _tvPassword)
            .requestFocus();
        return;
      }
    } else if (!_form.currentState!.validate()) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await ref
          .read(apiProvider)
          .authenticate(portalCredentials(_username.text, _password.text));
      await ref.read(storeProvider).saveSession(session);
      if (mounted) ref.read(sessionProvider.notifier).state = session;
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is XtreamApiException
              ? error.message
              : 'The account could not be saved or sign-in could not finish. Check device storage and run Connection diagnosis.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tv = ref.watch(isTvProvider);
    if (tv) {
      return _tvLogin(
        context,
        hasUpdate: ref.watch(updateControllerProvider).update != null,
      );
    }
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

  Future<void> _editTvField(bool password) async {
    if (_busy || _editing) return;
    _editing = true;
    bool? committed;
    try {
      final route = DialogRoute<bool>(
        context: context,
        builder: (_) => TvTextEntryDialog(
          controller: password ? _password : _username,
          label: password ? 'Password' : 'Username',
          password: password,
        ),
      );
      committed = await Navigator.of(context).push(route);
      await route.completed;
    } finally {
      _editing = false;
    }
    if (!mounted) return;
    setState(() => _error = null);
    final current = password ? _tvPassword : _tvUsername;
    final next = password ? _tvConnect : _tvPassword;
    (committed == true ? next : current).requestFocus();
  }

  KeyEventResult _tvKey(
    KeyEvent event, {
    FocusNode? up,
    FocusNode? down,
    FocusNode? left,
    FocusNode? right,
  }) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final destination = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => up,
      LogicalKeyboardKey.arrowDown => down,
      LogicalKeyboardKey.arrowLeft => left,
      LogicalKeyboardKey.arrowRight => right,
      _ => null,
    };
    if ([
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
    ].contains(event.logicalKey)) {
      destination?.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _tvLogin(
    BuildContext context, {
    required bool hasUpdate,
  }) => TvGlassScope(
    child: Theme(
      data: TvGlass.theme(Theme.of(context)),
      child: Scaffold(
        backgroundColor: TvGlass.canvas,
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, size) => SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: 1024,
                  height: size.maxHeight * 1024 / size.maxWidth,
                  child: TvGlassBackdrop(
                    child: Column(
                      children: [
                        SizedBox(
                          height: 64,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 26),
                            child: Row(
                              children: [
                                const StreamlineMark(size: 25, wordmark: true),
                                const Spacer(),
                                TvControl(
                                  focusNode: _tvDiagnosis,
                                  label: 'Connection diagnosis',
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 13,
                                    vertical: 9,
                                  ),
                                  onKeyEvent: (_, event) => _tvKey(
                                    event,
                                    down: _tvUsername,
                                    right: _tvUpdates,
                                  ),
                                  onPressed: () {
                                    if (!_busy) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              ConnectionDiagnosisScreen(
                                                credentials: portalCredentials(
                                                  _username.text,
                                                  _password.text,
                                                ),
                                              ),
                                        ),
                                      );
                                    }
                                  },
                                  child: const Text(
                                    'Connection diagnosis',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                if (hasUpdate)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 12),
                                    child: Text(
                                      'Update available',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: TvGlass.accent,
                                      ),
                                    ),
                                  ),
                                TvControl(
                                  style: TvControlStyle.primary,
                                  focusNode: _tvUpdates,
                                  label: 'App updates',
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 15,
                                    vertical: 9,
                                  ),
                                  onKeyEvent: (_, event) => _tvKey(
                                    event,
                                    down: _tvUsername,
                                    left: _tvDiagnosis,
                                  ),
                                  onPressed: () {
                                    if (!_busy) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              const AppUpdatesScreen(),
                                        ),
                                      );
                                    }
                                  },
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.system_update, size: 15),
                                      SizedBox(width: 7),
                                      Text(
                                        'App updates',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 52),
                            child: Row(
                              children: [
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'LIVE TELEVISION. FILMS. SERIES.',
                                        style: TextStyle(
                                          fontSize: 10,
                                          letterSpacing: 1.8,
                                          color: TvGlass.accent,
                                        ),
                                      ),
                                      SizedBox(height: 20),
                                      Text(
                                        'Your channels.\nYour cinema.',
                                        style: TextStyle(
                                          fontSize: 44,
                                          height: 1.06,
                                          letterSpacing: -1.4,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      SizedBox(height: 18),
                                      Text(
                                        'One place for what you love watching.\nReady when you are.',
                                        style: TextStyle(
                                          fontSize: 14,
                                          height: 1.6,
                                          color: TvGlass.muted,
                                        ),
                                      ),
                                      SizedBox(height: 28),
                                      Text(
                                        'Select a field and press OK to enter text.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: TvGlass.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 60),
                                SizedBox(
                                  width: 400,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: const Color(0x14FFFFFF),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(22),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          const Text(
                                            'Connect your account',
                                            style: TextStyle(
                                              fontSize: 23,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 7),
                                          const Text(
                                            'Enter your username and password.',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: TvGlass.muted,
                                            ),
                                          ),
                                          const SizedBox(height: 18),
                                          _tvLoginField(password: false),
                                          const SizedBox(height: 10),
                                          _tvLoginField(password: true),
                                          SizedBox(
                                            height: 42,
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: Semantics(
                                                liveRegion: true,
                                                child: Text(
                                                  _error ?? '',
                                                  maxLines: 3,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    height: 1.25,
                                                    color: AppColors.danger,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          TvControl(
                                            style: TvControlStyle.primary,
                                            focusNode: _tvConnect,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 12,
                                            ),
                                            onKeyEvent: (_, event) => _tvKey(
                                              event,
                                              up: _tvPassword,
                                              left: _tvDiagnosis,
                                              right: _tvUpdates,
                                            ),
                                            onPressed: _signIn,
                                            child: Center(
                                              child: Text(
                                                _busy
                                                    ? 'Connecting…'
                                                    : 'Connect & start watching',
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 14),
                                          const Text(
                                            'Your account is saved securely on this device.',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: TvGlass.muted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(
                          height: 42,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 26),
                            child: Row(
                              children: [
                                Text(
                                  'Ultravpn-player does not supply channels or content.',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: TvGlass.muted,
                                  ),
                                ),
                                Spacer(),
                                Text(
                                  'D-pad  Browse     OK  Select',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: TvGlass.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _tvLoginField({required bool password}) {
    final value = password ? _password.text : _username.text;
    final label = password ? 'Password' : 'Username';
    return TvControl(
      focusNode: password ? _tvPassword : _tvUsername,
      autofocus: !password,
      label: '$label${value.isEmpty ? ', not entered' : ', entered'}',
      onKeyEvent: (_, event) => password
          ? _tvKey(
              event,
              up: _tvUsername,
              down: _tvConnect,
              left: _tvDiagnosis,
              right: _tvUpdates,
            )
          : _tvKey(
              event,
              up: _tvUpdates,
              down: _tvPassword,
              left: _tvDiagnosis,
              right: _tvUpdates,
            ),
      onPressed: () => _editTvField(password),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: const TextStyle(fontSize: 10)),
          const SizedBox(height: 5),
          Text(
            value.isEmpty
                ? 'Press OK to enter ${label.toLowerCase()}'
                : password
                ? List.filled(value.length.clamp(0, 24), '•').join()
                : value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: value.isEmpty ? 12 : 15),
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
                  'Enter your username and password to start watching.',
                  style: theme.bodyMedium?.copyWith(
                    color: AppColors.muted,
                    height: 1.6,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _username,
                  enabled: !_busy,
                  autofocus: tv,
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
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => ConnectionDiagnosisScreen(
                              credentials: portalCredentials(
                                _username.text,
                                _password.text,
                              ),
                            ),
                          ),
                        ),
                  icon: const Icon(Icons.network_check),
                  label: const Text('Connection diagnosis'),
                ),
                const UpdateNotice(),
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const AppUpdatesScreen(),
                          ),
                        ),
                  icon: const Icon(Icons.system_update),
                  label: const Text('App updates'),
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
              'Ultravpn-player does not supply channels or content.',
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
                      : ref.watch(isDesktopProvider)
                      ? 'Windows desktop · F11 fullscreen'
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
