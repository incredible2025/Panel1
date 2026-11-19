import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/providers.dart';
import '../core/app_version.dart';
import '../widgets/tv_settings_view.dart';
import '../widgets/tv_page_navigation.dart';

class ManagementSupportScreen extends ConsumerStatefulWidget {
  const ManagementSupportScreen({super.key});
  @override
  ConsumerState<ManagementSupportScreen> createState() =>
      _ManagementSupportScreenState();
}

class _ManagementSupportScreenState
    extends ConsumerState<ManagementSupportScreen> {
  String? _code, _error;
  DateTime? _expires;
  bool _busy = false;
  Future<void> _pair() async {
    final activity = ref.read(managedConfigurationProvider)?.activity;
    if (activity == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _code = null;
    });
    try {
      final code = await activity.pairCode();
      if (mounted) {
        setState(() {
          _code = code;
          _expires = DateTime.now().add(const Duration(minutes: 10));
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Unable to create a code. Check your connection, or wait ten minutes before requesting another.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _contact(String address) async {
    try {
      final opened = await const MethodChannel(
        'streamline/platform',
      ).invokeMethod<bool>('openSupport', address);
      if (opened == true) return;
    } catch (_) {
      /* Copy remains available when no external app can open it. */
    }
    await Clipboard.setData(
      ClipboardData(text: address.replaceFirst('mailto:', '')),
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Support address copied.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final manager = ref.watch(managedConfigurationProvider);
    if (manager == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Support')),
        body: const Center(
          child: Text(
            'Remote management is not available on this installation.',
          ),
        ),
      );
    }
    return ListenableBuilder(
      listenable: Listenable.merge([
        manager,
        if (manager.activity != null) manager.activity!,
      ]),
      builder: (context, _) {
        final support = manager.current.support;
        final activity = manager.activity;
        const privacy =
            'Anonymous activity reporting counts this installation while the app is open. It sends the app version and applied settings revision. Account credentials, viewing history and hardware identifiers are never included. Reporting stops in the background; inactive records expire after 30 days.';
        final code = _code != null && _expires!.isAfter(DateTime.now())
            ? _code
            : null;
        final entries = <TvSetting>[
          TvSetting(
            title: 'Installed version',
            value: appVersion,
            description: 'Your installed app version and Android build number.',
          ),
          TvSetting(
            title: 'Configuration revision',
            value: '${manager.current.revision}',
            description:
                'The latest verified settings successfully applied on this device.',
          ),
          TvSetting(
            title: 'Activity reporting',
            value: activity?.lastReported == null
                ? 'Awaiting connection'
                : 'Connected',
            description: privacy,
          ),
          TvSetting(
            title: _busy ? 'Creating code…' : 'Link test device',
            value: code ?? '',
            description:
                _error ??
                (code == null
                    ? 'Only use this if your app administrator asks you to join testing. Request a code, then give it to the administrator within ten minutes. No account password is needed.'
                    : 'Pairing code: $code. Valid for ten minutes, one use only. The administrator enters this code in the management dashboard.'),
            onPressed: _busy ? null : _pair,
          ),
          if (support.message.isNotEmpty)
            TvSetting(title: 'Help', description: support.message),
          if (support.email.isNotEmpty)
            TvSetting(
              title: 'Email support',
              value: support.email,
              description: 'Open your email app, or copy this support address.',
              onPressed: () => _contact('mailto:${support.email}'),
            ),
          if (support.website.isNotEmpty)
            TvSetting(
              title: 'Support website',
              value: support.website,
              description: 'Open the support website, or copy its address.',
              onPressed: () => _contact(support.website),
            ),
        ];
        if (ref.watch(isLargeScreenProvider)) {
          return TvSettingsView(
            groups: [
              TvSettingsGroup(title: 'Management & support', entries: entries),
            ],
            notice: 'Management & support',
          );
        }
        return Scaffold(
          appBar: AppBar(title: const Text('Management & support')),
          body: TvPageNavigation(
            enabled: false,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final entry in entries)
                  Card(
                    child: ListTile(
                      title: Text(entry.title),
                      subtitle: Text(
                        [
                          if (entry.value.isNotEmpty) entry.value,
                          entry.description,
                        ].where((s) => s.isNotEmpty).join('\n'),
                      ),
                      onTap: entry.onPressed,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
