import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/design_system.dart';
import '../core/app_version.dart';
import '../core/app_brand.dart';
import 'connection_diagnosis_screen.dart';
import 'app_updates_screen.dart';
import 'speed_test_screen.dart';
import '../core/providers.dart';
import '../core/settings_controller.dart';
import '../data/app_settings.dart';
import '../data/models.dart';
import '../widgets/parental_access.dart';
import '../widgets/status_view.dart';
import '../widgets/tv_page_navigation.dart';
import '../widgets/tv_controls.dart';
import '../widgets/tv_settings_view.dart';
import '../widgets/tv_utility_scaffold.dart';
import 'tv_licences_screen.dart';
import '../widgets/tv_pin_entry.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.embedded = false, this.groupIndex});
  final bool embedded;
  final int? groupIndex;
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _refreshing = false;
  String? _notice;
  Future<void> _save(Map<String, dynamic> values) async {
    final saved = await ref.read(settingsProvider.notifier).patch(values);
    if (!saved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preferences could not be saved. Please try again.'),
        ),
      );
    }
  }

  Future<void> _refreshAccount() async {
    if (_refreshing) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    setState(() => _refreshing = true);
    try {
      final next = await ref
          .read(apiProvider)
          .authenticate(session.credentials);
      await ref.read(storeProvider).saveSession(next);
      if (mounted &&
          ref.read(sessionProvider)?.accountId == session.accountId) {
        ref.read(sessionProvider.notifier).state = next;
        setState(() => _notice = 'Account information refreshed.');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice =
              'Account information could not be refreshed. Check your connection.',
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _setPin() async {
    String? pin;
    if (ref.read(isLargeScreenProvider)) {
      final first = await showTvPinEntry(context, 'New PIN');
      if (first == null || !mounted) return;
      final second = await showTvPinEntry(context, 'Confirm PIN');
      if (second == null || !mounted) return;
      if (first != second) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The PINs do not match. Please try again.'),
          ),
        );
        return;
      }
      pin = first;
    } else {
      pin = await showDialog<String>(
        context: context,
        builder: (_) => const _NewPinDialog(),
      );
    }
    final account = ref.read(sessionProvider)?.accountId;
    if (pin == null || account == null || !mounted) return;
    setState(() => _refreshing = true);
    try {
      await ref.read(storeProvider).setPin(account, pin);
      ref.invalidate(pinConfiguredProvider);
      ref.read(parentalSessionProvider.notifier).unlock();
      if (mounted) {
        setState(() => _notice = 'Parental PIN saved. Lock categories below.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _notice = 'PIN could not be saved. Try again.');
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      ) ==
      true;
  Future<void> _removePin() async {
    if (!await _confirm(
      'Remove parental protection?',
      'This removes the PIN and unlocks protected categories.',
    )) {
      return;
    }
    final account = ref.read(sessionProvider)?.accountId;
    if (account == null) return;
    final previous = ref.read(settingsProvider.notifier).current;
    if (!await ref.read(settingsProvider.notifier).patch({
      'lockedCategories': <String>[],
    })) {
      return;
    }
    try {
      await ref.read(storeProvider).removePin(account);
      ref.invalidate(pinConfiguredProvider);
    } catch (_) {
      await ref.read(settingsProvider.notifier).patch({
        'lockedCategories': previous.lockedCategories.toList(),
      });
      if (mounted) setState(() => _notice = 'PIN could not be removed.');
    }
  }

  Future<void> _clearCache() async {
    if (!await _confirm(
      'Clear provider cache?',
      'Cached programme data will be downloaded again. Your login, preferences, My List and watch history stay on this device.',
    )) {
      return;
    }
    final account = ref.read(sessionProvider)?.accountId;
    if (account == null) return;
    try {
      await ref.read(storeProvider).clearCache(account);
      _refreshLibrary();
      if (mounted) setState(() => _notice = 'Provider cache cleared.');
    } catch (_) {
      if (mounted) setState(() => _notice = 'Cache could not be cleared.');
    }
  }

  void _refreshLibrary() {
    ref.invalidate(itemsProvider);
    ref.invalidate(categoriesProvider);
    ref.invalidate(epgProvider);
    ref.invalidate(movieDetailProvider);
    ref.invalidate(seriesDetailProvider);
    ref.read(guideRefreshProvider.notifier).state++;
    if (mounted) {
      setState(() => _notice = 'Library and programme guide will refresh.');
    }
  }

  Future<void> _reset() async {
    if (!await _confirm(
      'Reset preferences?',
      'Restore playback, appearance and browsing defaults. Watch history, My List and parental PIN/category locks are retained.',
    )) {
      return;
    }
    final current = ref.read(settingsProvider.notifier).current;
    await _save({
      ...const AppSettings().toJson(),
      'lockedCategories': current.lockedCategories.toList(),
    });
  }

  Future<void> _signOut() async {
    if (!await _confirm(
      'Sign out?',
      'Your account’s viewing history and preferences stay on this device.',
    )) {
      return;
    }
    try {
      await ref.read(storeProvider).clearSession();
      ref.read(parentalSessionProvider.notifier).lock();
      ref.read(sessionProvider.notifier).state = null;
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (_) {
      if (mounted) setState(() => _notice = 'Could not sign out. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final pin = ref.watch(pinConfiguredProvider);
    final unlocked = ref.watch(parentalSessionProvider);
    final content = settings.when(
      loading: () =>
          const StatusView(title: 'Loading preferences', loading: true),
      error: (_, __) => StatusView(
        title: 'Preferences unavailable',
        message:
            'Reload before continuing so parental and account settings remain protected.',
        onRetry: () => ref.read(settingsProvider.notifier).reload(),
      ),
      data: (value) {
        if (pin.isLoading) {
          return const StatusView(title: 'Checking protection', loading: true);
        }
        if (pin.hasError) {
          return StatusView(
            title: 'Protection unavailable',
            onRetry: () => ref.invalidate(pinConfiguredProvider),
          );
        }
        if (pin.asData?.value == true && !unlocked) {
          return StatusView(
            title: 'Settings are protected',
            message:
                'Enter your parental PIN to change preferences or view account information.',
            onRetry: () => requestParentalAccess(context, ref),
          );
        }
        return _settings(value, pin.asData?.value == true);
      },
    );
    if (ref.watch(isLargeScreenProvider) && content is TvSettingsView) {
      return content;
    }
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: widget.embedded ? null : AppBar(title: const Text('Settings')),
      body: TvPageNavigation(
        enabled: ref.watch(isLargeScreenProvider),
        child: content,
      ),
    );
  }

  Widget _settings(AppSettings s, bool hasPin) {
    final session = ref.watch(sessionProvider);
    final account = session == null ? null : AccountInfo(session);
    final groups = <Widget>[
      _group('Playback', Icons.play_circle_outline, [
        _choice(
          'Default player',
          ref.watch(isDesktopProvider) ? 'compatibility' : s.engine.name,
          {
            if (!ref.watch(isDesktopProvider)) 'native': 'ExoPlayer · Standard',
            'compatibility': ref.watch(isDesktopProvider)
                ? 'Windows · media_kit'
                : 'Compatibility · media_kit',
          },
          (v) => _save({'engine': v}),
        ),
        _choice(
          'Hide player controls',
          s.controlsSeconds.toString(),
          {
            '3': 'After 3 seconds',
            '5': 'After 5 seconds',
            '8': 'After 8 seconds',
            '0': 'Never',
          },
          (v) => _save({'controlsSeconds': int.parse(v)}),
        ),
        _choice('Default picture', s.picture, {
          'fit': 'Fit · Show entire picture',
          'fill': 'Fill · Crop to screen',
          'stretch': 'Stretch',
        }, (v) => _save({'picture': v})),
        _toggle(
          'Automatically reconnect',
          'Up to three attempts after a stream interruption.',
          s.reconnect,
          (v) => _save({'reconnect': v}),
        ),
        _toggle(
          'Play the next episode',
          'Eight-second countdown with a Cancel button.',
          s.autoNext,
          (v) => _save({'autoNext': v}),
        ),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Override the player for an individual channel or title from its player’s options. Both engines use the same resume history.',
            style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.6),
          ),
        ),
      ]),
      _group('Audio & subtitles', Icons.graphic_eq, [
        _choice(
          'Preferred audio language',
          s.audioLanguage,
          _languages,
          (v) => _save({'audioLanguage': v}),
        ),
        _toggle(
          'Prefer stereo tracks',
          'Choose a supplied two-channel track where available. Automatic output uses the device’s supported audio formats.',
          s.stereo,
          (v) => _save({'stereo': v}),
        ),
        _toggle(
          'Subtitles by default',
          'Select a supplied subtitle track when available.',
          s.subtitles,
          (v) => _save({'subtitles': v}),
        ),
        _choice(
          'Preferred subtitle language',
          s.subtitleLanguage,
          _languages,
          (v) => _save({'subtitleLanguage': v}),
        ),
        _choice(
          'Subtitle text size',
          s.subtitleSize.round().toString(),
          {'18': 'Small', '22': 'Standard', '28': 'Large', '34': 'Extra large'},
          (v) => _save({'subtitleSize': int.parse(v)}),
        ),
        _toggle(
          'Subtitle background',
          'Improve text contrast over bright scenes.',
          s.subtitleBackground,
          (v) => _save({'subtitleBackground': v}),
        ),
      ]),
      _group('Appearance', Icons.palette_outlined, [
        _choice('Theme', s.theme, {
          'midnight': 'Glass · Blue & cyan',
          'cinema': 'Glass · Midnight',
        }, (v) => _save({'theme': v})),
        _toggle(
          'Larger posters',
          'Fewer titles per row with larger artwork.',
          s.largePosters,
          (v) => _save({'largePosters': v}),
        ),
        _toggle(
          'Compact layout',
          'Reduce spacing between shelves and controls.',
          s.compact,
          (v) => _save({'compact': v}),
        ),
        _toggle(
          'Reduce motion',
          'Disable focus scaling and nonessential transitions.',
          s.reducedMotion,
          (v) => _save({'reducedMotion': v}),
        ),
        _toggle(
          'Personal movie recommendations',
          'Based on watched films and your provider’s categories. Computed on this device; no history upload.',
          s.recommendations,
          (v) => _save({'recommendations': v}),
        ),
      ]),
      _group('Library & parental controls', Icons.shield_outlined, [
        _action(
          'Manage categories',
          'Hide, reorder or PIN-protect channel, movie and series categories.',
          Icons.tune,
          () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => const CategorySettingsScreen(),
            ),
          ),
        ),
        _action(
          'Reorder favourite channels',
          'Choose the order used by your Home and Live TV shelves.',
          Icons.reorder,
          () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => const FavoriteOrderScreen(),
            ),
          ),
        ),
        _action(
          hasPin ? 'Change parental PIN' : 'Set parental PIN',
          'Four to eight digits. Protected access relocks after five minutes or on backgrounding.',
          Icons.lock_outline,
          _refreshing ? null : _setPin,
        ),
        if (hasPin)
          _action(
            'Remove parental PIN',
            'Also unlocks protected categories.',
            Icons.lock_open,
            _refreshing ? null : _removePin,
          ),
        if (hasPin)
          _action(
            'Lock protected access now',
            'Hide protected content and lock Settings again.',
            Icons.shield,
            () => ref.read(parentalSessionProvider.notifier).lock(),
          ),
      ]),
      _group('Your account', Icons.account_circle_outlined, [
        _info('Username', session?.credentials.username ?? 'Not signed in'),
        _info('Status', account?.status ?? 'Not supplied'),
        _info('Expiry date', account?.expiryLabel ?? 'Not supplied'),
        _info(
          'Time remaining',
          account?.neverExpires == true
              ? 'Doesn’t expire'
              : account?.remainingDays == null
              ? 'Not supplied'
              : account!.remainingDays! <= 0 &&
                    account.expiry!.isBefore(DateTime.now())
              ? 'Expired'
              : '${account.remainingDays} days',
        ),
        _info(
          'Active connections',
          account?.count('active_cons') ?? 'Not supplied',
        ),
        _info(
          'Maximum connections',
          account?.count('max_connections') ?? 'Not supplied',
        ),
        _action(
          _refreshing ? 'Refreshing account…' : 'Refresh account information',
          'Fetch current status, expiry and connection counts from your provider.',
          Icons.refresh,
          _refreshing ? null : _refreshAccount,
        ),
      ]),
      _group('App & maintenance', Icons.settings_outlined, [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                appBrandArtwork,
                width: 160,
                height: 160,
                semanticLabel: appBrandName,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ),

        _action(
          'Speed test',
          'Measure download, upload, latency and jitter on this device’s current connection.',
          Icons.speed,
          () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const SpeedTestScreen()),
          ),
        ),
        _action(
          'Connection diagnosis',
          'Check the network, provider, HTTPS, account and library. See error explanations and practical next steps.',
          Icons.network_check,
          () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => const ConnectionDiagnosisScreen(),
            ),
          ),
        ),
        const UpdateNotice(),
        if (ref.read(isLargeScreenProvider))
          _action(
            'App updates',
            'Check for new versions and install updates',
            Icons.system_update,
            () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AppUpdatesScreen()),
            ),
          )
        else
          ListTile(
            leading: const Icon(Icons.system_update),
            title: const Text('App updates'),
            subtitle: const Text('Check for new versions and install updates'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AppUpdatesScreen()),
            ),
          ),
        _info(appBrandName, appVersion),
        _action(
          'Open source licences',
          'Licences for Flutter, the playback engines and bundled libraries.',
          Icons.description_outlined,
          () => ref.read(isLargeScreenProvider)
              ? Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const TvLicencesScreen(),
                  ),
                )
              : showLicensePage(
                  context: context,
                  applicationName: appBrandName,
                  applicationVersion: appVersion,
                ),
        ),
        _action(
          'Refresh library & guide',
          'Reload provider categories, titles and programme data.',
          Icons.sync,
          _refreshLibrary,
        ),
        _action(
          'Clear provider cache',
          'Keep login, watch history and My List.',
          Icons.cleaning_services_outlined,
          _clearCache,
        ),
        _action(
          'Reset preferences',
          'Restore defaults while retaining parental protection.',
          Icons.restore,
          _reset,
        ),
        _action(
          'Sign out',
          'Keep this account’s local collections for next time.',
          Icons.logout,
          _signOut,
        ),
      ]),
    ];
    if (ref.read(isLargeScreenProvider)) {
      return TvSettingsView(
        groups: groups.cast<TvSettingsGroup>(),
        initialGroup: widget.groupIndex ?? 0,
        notice: _notice,
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 1000;
        return SingleChildScrollView(
          padding: EdgeInsets.all(box.maxWidth > 700 ? 32 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Eyebrow('MAKE IT YOURS'),
              const SizedBox(height: 10),
              Text(
                widget.groupIndex == null
                    ? 'Settings'
                    : const [
                        'Playback',
                        'Audio & subtitles',
                        'Appearance',
                        'Library & parental controls',
                        'Your account',
                        'App & maintenance',
                      ][widget.groupIndex!],
                style: widget.groupIndex == null
                    ? Theme.of(context).textTheme.displaySmall
                    : Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 10),
              const Text(
                'Your picture. Your sound. Your space.',
                style: TextStyle(color: AppColors.muted),
              ),
              if (_notice != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    _notice!,
                    style: const TextStyle(color: AppColors.accent),
                  ),
                ),
              const SizedBox(height: 28),
              if (widget.groupIndex != null)
                groups[widget.groupIndex!.clamp(0, groups.length - 1)]
              else if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        children: [groups[0], groups[2], groups[4]],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        children: [groups[1], groups[3], groups[5]],
                      ),
                    ),
                  ],
                )
              else
                ...groups,
              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }

  static const _languages = {
    '': 'Automatic',
    'en': 'English',
    'es': 'Spanish',
    'fr': 'French',
    'de': 'German',
    'it': 'Italian',
    'pt': 'Portuguese',
    'ar': 'Arabic',
    'hi': 'Hindi',
    'tr': 'Turkish',
    'pl': 'Polish',
    'nl': 'Dutch',
  };
  Widget _group(String title, IconData icon, List<Widget> children) =>
      ref.read(isLargeScreenProvider)
      ? TvSettingsGroup(
          title: title,
          entries: children.whereType<TvSetting>().toList(),
        )
      : Container(
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Icon(icon, color: AppColors.accent, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ...children,
            ],
          ),
        );
  Widget _toggle(
    String title,
    String description,
    bool value,
    ValueChanged<bool> change,
  ) => ref.read(isLargeScreenProvider)
      ? TvSetting(
          title: title,
          value: value ? 'On' : 'Off',
          description: description,
          onPressed: () => change(!value),
        )
      : SwitchListTile(
          title: Text(
            title,
            style: TextStyle(
              fontSize: ref.read(isLargeScreenProvider) ? 18 : 14,
            ),
          ),
          subtitle: Text(
            description,
            style: TextStyle(
              fontSize: ref.read(isLargeScreenProvider) ? 16 : 12,
              color: AppColors.muted,
            ),
          ),
          value: value,
          onChanged: change,
        );
  Widget _choice(
    String title,
    String value,
    Map<String, String> options,
    ValueChanged<String> change,
  ) => ref.read(isLargeScreenProvider)
      ? TvSetting(
          title: title,
          value: options[value] ?? value,
          description: 'Choose your preferred ${title.toLowerCase()}.',
          onPressed: () async {
            final selected = await showTvMenu(context, title, options);
            if (selected != null) change(selected);
          },
        )
      : ListTile(
          title: Text(
            title,
            style: TextStyle(
              fontSize: ref.read(isLargeScreenProvider) ? 18 : 14,
            ),
          ),
          subtitle: Text(
            options[value] ?? value,
            style: TextStyle(
              color: AppColors.muted,
              fontSize: ref.read(isLargeScreenProvider) ? 16 : 12,
            ),
          ),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: () async {
            final selected = await showDialog<String>(
              context: context,
              builder: (context) => TvPageNavigation(
                enabled: ref.read(isLargeScreenProvider),
                child: SimpleDialog(
                  title: Text(title),
                  children: [
                    for (final option in options.entries)
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(context, option.key),
                        child: Row(
                          children: [
                            Expanded(child: Text(option.value)),
                            if (value == option.key)
                              const Icon(Icons.check, color: AppColors.accent),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );
            if (selected != null) change(selected);
          },
        );
  Widget _action(
    String title,
    String description,
    IconData icon,
    VoidCallback? action,
  ) => ref.read(isLargeScreenProvider)
      ? TvSetting(title: title, description: description, onPressed: action)
      : ListTile(
          enabled: action != null,
          leading: Icon(icon, size: 20),
          title: Text(
            title,
            style: TextStyle(
              fontSize: ref.read(isLargeScreenProvider) ? 18 : 14,
            ),
          ),
          subtitle: Text(
            description,
            style: TextStyle(
              color: AppColors.muted,
              fontSize: ref.read(isLargeScreenProvider) ? 16 : 12,
            ),
          ),
          onTap: action,
        );
  Widget _info(String name, String value) => ref.read(isLargeScreenProvider)
      ? TvSetting(title: name, value: value)
      : Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: ref.read(isLargeScreenProvider) ? 16 : 12,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: ref.read(isLargeScreenProvider) ? 18 : 13,
                  ),
                ),
              ),
            ],
          ),
        );
}

class _NewPinDialog extends StatefulWidget {
  const _NewPinDialog();
  @override
  State<_NewPinDialog> createState() => _NewPinDialogState();
}

class _NewPinDialogState extends State<_NewPinDialog> {
  final _first = TextEditingController(), _second = TextEditingController();
  String? _error;
  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Set parental PIN'),
    content: SizedBox(
      width: 350,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final field in [(_first, 'New PIN'), (_second, 'Confirm PIN')])
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextField(
                controller: field.$1,
                obscureText: true,
                autofocus: field.$1 == _first,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(8),
                ],
                decoration: InputDecoration(labelText: field.$2),
              ),
            ),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: AppColors.danger)),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_first.text.length < 4 || _first.text != _second.text) {
            setState(
              () => _error =
                  'Use four to eight digits and enter the same PIN twice.',
            );
            return;
          }
          Navigator.pop(context, _first.text);
        },
        child: const Text('Save PIN'),
      ),
    ],
  );
}

class CategorySettingsScreen extends ConsumerStatefulWidget {
  const CategorySettingsScreen({super.key});
  @override
  ConsumerState<CategorySettingsScreen> createState() =>
      _CategorySettingsScreenState();
}

class _CategorySettingsScreenState
    extends ConsumerState<CategorySettingsScreen> {
  MediaKind _kind = MediaKind.live;
  final _tvList = GlobalKey<TvRemoteListState>();
  final _tabs = {for (final k in MediaKind.values) k: FocusNode()};
  @override
  void dispose() {
    for (final node in _tabs.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings =
        ref.watch(settingsProvider).asData?.value ?? const AppSettings();
    final protection = ref.watch(pinConfiguredProvider);
    if (protection.isLoading) {
      return const Scaffold(
        body: StatusView(title: 'Checking protection', loading: true),
      );
    }
    if (protection.hasError || ref.watch(settingsProvider).hasError) {
      return Scaffold(
        appBar: AppBar(),
        body: StatusView(
          title: 'Protection unavailable',
          onRetry: () {
            ref.invalidate(pinConfiguredProvider);
            ref.read(settingsProvider.notifier).reload();
          },
        ),
      );
    }
    final pin = protection.asData?.value == true;
    if (pin && !ref.watch(parentalSessionProvider)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Categories')),
        body: StatusView(
          title: 'Categories are protected',
          onRetry: () => requestParentalAccess(context, ref),
        ),
      );
    }
    final categories = ref.watch(categoriesProvider(_kind));
    final content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            children: [
              for (final kind in MediaKind.values)
                Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onKeyEvent: (_, event) {
                    if (ref.read(isLargeScreenProvider) &&
                        (event is KeyDownEvent || event is KeyRepeatEvent) &&
                        event.logicalKey == LogicalKeyboardKey.arrowDown) {
                      _tvList.currentState?.focusSelected(remember: true);
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: ChoiceChip(
                    focusNode: _tabs[kind],
                    label: Text(switch (kind) {
                      MediaKind.live => 'Live TV',
                      MediaKind.movie => 'Movies',
                      MediaKind.series => 'Series',
                    }),
                    selected: _kind == kind,
                    onSelected: (_) => setState(() => _kind = kind),
                  ),
                ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Text(
            'Use the eye to hide a category and the lock to require a PIN. Drag or use the arrows to reorder.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ),
        Expanded(
          child: categories.when(
            loading: () =>
                const StatusView(title: 'Loading categories', loading: true),
            error: (_, __) => StatusView(
              title: 'Categories unavailable',
              onRetry: () => ref.invalidate(categoriesProvider(_kind)),
            ),
            data: (all) {
              final order = settings.categoryOrder[_kind.name] ?? [];
              final sorted = List<Category>.of(all)
                ..sort((a, b) {
                  final x = order.indexOf(a.id), y = order.indexOf(b.id);
                  return (x < 0 ? order.length + all.indexOf(a) : x).compareTo(
                    y < 0 ? order.length + all.indexOf(b) : y,
                  );
                });
              if (sorted.isEmpty) {
                return const StatusView(title: 'No categories supplied');
              }
              Future<void> reorder(int old, int next) async {
                final ids = sorted.map((category) => category.id).toList();
                if (next > old) next--;
                ids.insert(next, ids.removeAt(old));
                await ref
                    .read(settingsProvider.notifier)
                    .update(
                      (value) => value.patch({
                        'categoryOrder': {
                          ...value.categoryOrder,
                          _kind.name: ids,
                        },
                      }),
                    );
              }

              if (ref.watch(isLargeScreenProvider)) {
                return TvRemoteList(
                  key: _tvList,
                  autofocus: true,
                  extent: 54,
                  label: 'Manage category',
                  fullRows: true,
                  onTop: () => _tabs[_kind]!.requestFocus(),
                  onLeft: () => _tabs[_kind]!.requestFocus(),
                  onRight: () {},
                  entries: [
                    for (var i = 0; i < sorted.length; i++)
                      TvListEntry(
                        id: sorted[i].id,
                        title: sorted[i].name,
                        subtitle:
                            '${settings.hiddenCategories.contains(AppSettings.categoryKey(_kind, sorted[i].id))
                                ? 'Hidden'
                                : settings.lockedCategories.contains(AppSettings.categoryKey(_kind, sorted[i].id))
                                ? 'PIN protected'
                                : 'Visible'} · OK to manage',
                        onPressed: () =>
                            _manageCategory(sorted, i, settings, pin, reorder),
                      ),
                  ],
                );
              }
              return ReorderableListView.builder(
                itemCount: sorted.length,
                onReorder: reorder,
                buildDefaultDragHandles: false,
                itemBuilder: (context, index) {
                  final category = sorted[index],
                      key = AppSettings.categoryKey(_kind, sorted[index].id);
                  return ListTile(
                    key: ValueKey(key),
                    leading: ReorderableDragStartListener(
                      index: index,
                      child: const Icon(Icons.drag_handle),
                    ),
                    title: Text(category.name),
                    subtitle: Text(
                      settings.hiddenCategories.contains(key)
                          ? 'Hidden'
                          : settings.lockedCategories.contains(key)
                          ? 'PIN protected'
                          : 'Visible',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Move category up',
                          onPressed: index == 0
                              ? null
                              : () => reorder(index, index - 1),
                          icon: const Icon(Icons.arrow_upward, size: 18),
                        ),
                        IconButton(
                          tooltip: settings.hiddenCategories.contains(key)
                              ? 'Show category'
                              : 'Hide category',
                          onPressed: () => ref
                              .read(settingsProvider.notifier)
                              .update((value) {
                                final hidden = {...value.hiddenCategories};
                                if (!hidden.remove(key)) hidden.add(key);
                                return value.patch({
                                  'hiddenCategories': hidden.toList(),
                                });
                              }),
                          icon: Icon(
                            settings.hiddenCategories.contains(key)
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                        IconButton(
                          tooltip: settings.lockedCategories.contains(key)
                              ? 'Unlock category'
                              : 'Lock category',
                          onPressed: () {
                            if (!pin) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Set a parental PIN in Settings first.',
                                  ),
                                ),
                              );
                              return;
                            }
                            ref.read(settingsProvider.notifier).update((value) {
                              final locks = {...value.lockedCategories};
                              if (!locks.remove(key)) locks.add(key);
                              return value.patch({
                                'lockedCategories': locks.toList(),
                              });
                            });
                          },
                          icon: Icon(
                            settings.lockedCategories.contains(key)
                                ? Icons.lock
                                : Icons.lock_open_outlined,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
    return ref.watch(isLargeScreenProvider)
        ? TvUtilityScaffold(title: 'Manage categories', child: content)
        : Scaffold(
            appBar: AppBar(title: const Text('Manage categories')),
            body: content,
          );
  }

  Future<void> _manageCategory(
    List<Category> categories,
    int index,
    AppSettings settings,
    bool hasPin,
    Future<void> Function(int, int) reorder,
  ) async {
    final category = categories[index],
        key = AppSettings.categoryKey(_kind, categories[index].id);
    final action = await showTvMenu(context, category.name, {
      if (index > 0) 'up': 'Move up',
      if (index + 1 < categories.length) 'down': 'Move down',
      'visibility': settings.hiddenCategories.contains(key)
          ? 'Show category'
          : 'Hide category',
      'lock': settings.lockedCategories.contains(key)
          ? 'Unlock category'
          : 'Lock category',
      'close': 'Close',
    });
    if (!mounted || action == null || action == 'close') return;
    if (action == 'up' || action == 'down') {
      await reorder(index, action == 'up' ? index - 1 : index + 2);
      return;
    }
    if (action == 'lock' && !hasPin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set a parental PIN in Settings first.')),
      );
      return;
    }
    await ref.read(settingsProvider.notifier).update((s) {
      final set = action == 'lock'
          ? {...s.lockedCategories}
          : {...s.hiddenCategories};
      if (!set.remove(key)) set.add(key);
      return s.patch({
        action == 'lock' ? 'lockedCategories' : 'hiddenCategories': set
            .toList(),
      });
    });
  }
}

class FavoriteOrderScreen extends ConsumerWidget {
  const FavoriteOrderScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider).asData?.value ?? const AppSettings();
    final protection = ref.watch(pinConfiguredProvider);
    if (protection.isLoading || ref.watch(settingsProvider).isLoading) {
      return const Scaffold(
        body: StatusView(title: 'Checking protection', loading: true),
      );
    }
    if (protection.hasError || ref.watch(settingsProvider).hasError) {
      return Scaffold(
        appBar: AppBar(),
        body: StatusView(
          title: 'Protection unavailable',
          onRetry: () {
            ref.invalidate(pinConfiguredProvider);
            ref.read(settingsProvider.notifier).reload();
          },
        ),
      );
    }
    if (protection.asData?.value == true &&
        !ref.watch(parentalSessionProvider)) {
      return Scaffold(
        appBar: AppBar(),
        body: StatusView(
          title: 'Favourites are protected',
          onRetry: () => requestParentalAccess(context, ref),
        ),
      );
    }
    final favorites = ref.watch(favoritesProvider);
    final content = favorites.when(
      loading: () =>
          const StatusView(title: 'Loading favourites', loading: true),
      error: (_, __) => StatusView(
        title: 'Favourites unavailable',
        onRetry: () => ref.invalidate(favoritesProvider),
      ),
      data: (all) {
        final channels =
            all.where((item) => item.kind == MediaKind.live).toList()..sort(
              (a, b) => _rank(
                s.favoriteOrder,
                a,
              ).compareTo(_rank(s.favoriteOrder, b)),
            );
        if (channels.isEmpty) {
          return const StatusView(
            title: 'No favourite channels yet',
            message: 'Save channels using their star, then reorder them here.',
          );
        }
        Future<void> move(int old, int next) async {
          if (next > old) next--;
          final ids = channels.map(AppSettings.mediaKey).toList();
          ids.insert(next, ids.removeAt(old));
          await ref.read(settingsProvider.notifier).patch({
            'favoriteOrder': ids,
          });
        }

        if (ref.watch(isLargeScreenProvider)) {
          return TvRemoteList(
            autofocus: true,
            extent: 54,
            label: 'Favourite channel',
            fullRows: true,
            onLeft: () {},
            onRight: () {},
            onTop: () {},
            entries: [
              for (var i = 0; i < channels.length; i++)
                TvListEntry(
                  id: channels[i].id,
                  title: channels[i].name,
                  subtitle: 'Position ${i + 1} · OK to reorder',
                  onPressed: () async {
                    final action = await showTvMenu(context, channels[i].name, {
                      if (i > 0) 'up': 'Move up',
                      if (i + 1 < channels.length) 'down': 'Move down',
                      'close': 'Close',
                    });
                    if (action == 'up') await move(i, i - 1);
                    if (action == 'down') await move(i, i + 2);
                  },
                ),
            ],
          );
        }
        return ReorderableListView.builder(
          itemCount: channels.length,
          onReorder: move,
          buildDefaultDragHandles: false,
          itemBuilder: (context, index) => ListTile(
            key: ValueKey(channels[index].id),
            leading: ReorderableDragStartListener(
              index: index,
              child: const Icon(Icons.drag_handle),
            ),
            title: Text(channels[index].name),
            trailing: IconButton(
              tooltip: 'Move favourite up',
              onPressed: index == 0 ? null : () => move(index, index - 1),
              icon: const Icon(Icons.arrow_upward),
            ),
          ),
        );
      },
    );
    return ref.watch(isLargeScreenProvider)
        ? TvUtilityScaffold(title: 'Favourite channel order', child: content)
        : Scaffold(
            appBar: AppBar(title: const Text('Favourite channel order')),
            body: content,
          );
  }

  int _rank(List<String> order, MediaItem item) {
    final index = order.indexOf(AppSettings.mediaKey(item));
    return index < 0 ? order.length : index;
  }
}
