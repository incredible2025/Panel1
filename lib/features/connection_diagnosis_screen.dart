import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design_system.dart';
import '../core/providers.dart';
import '../data/connection_diagnostics.dart';
import '../data/diagnostic_transport.dart';
import '../data/models.dart';
import '../widgets/parental_access.dart';
import '../widgets/tv_page_navigation.dart';
import 'tv_diagnosis_view.dart';

final connectionDiagnosticsFactoryProvider =
    Provider<ConnectionDiagnostics Function()>(
      (ref) =>
          () => ConnectionDiagnostics(IoDiagnosticTransport()),
    );

class ConnectionDiagnosisScreen extends ConsumerStatefulWidget {
  const ConnectionDiagnosisScreen({
    super.key,
    this.credentials,
    this.item,
    this.episode,
    this.canTestStream = false,
  });
  final Credentials? credentials;
  final MediaItem? item;
  final Episode? episode;
  final bool canTestStream;
  @override
  ConsumerState<ConnectionDiagnosisScreen> createState() =>
      _ConnectionDiagnosisScreenState();
}

class _ConnectionDiagnosisScreenState
    extends ConsumerState<ConnectionDiagnosisScreen>
    with WidgetsBindingObserver {
  ConnectionDiagnostics? _runner;
  DiagnosticReport? _report;
  bool _busy = false, _includeStream = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _busy) _stop();
  }

  void _stop() {
    _runner?.cancel();
    _generation++;
    if (mounted) {
      setState(() {
        _busy = false;
        _report = DiagnosticReport(
          _report?.started ?? DateTime.now(),
          _report?.checks ?? const [],
          cancelled: true,
        );
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    _runner?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    if (_busy) return;
    final credentials =
        widget.credentials ?? ref.read(sessionProvider)?.credentials;
    if (credentials == null) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _report = null;
    });
    var permitted = false;
    if (_includeStream && widget.canTestStream && widget.item != null) {
      permitted = await allowMedia(context, ref, widget.item!);
    }
    if (!mounted || generation != _generation) return;
    final runner = ref.read(connectionDiagnosticsFactoryProvider)();
    _runner = runner;
    try {
      final report = await runner.run(
        credentials,
        item: widget.item,
        episode: widget.episode,
        testStream: _includeStream,
        streamPermitted: permitted,
        onProgress: (report) {
          if (mounted && generation == _generation) {
            setState(() => _report = report);
          }
        },
      );
      if (mounted && generation == _generation) {
        setState(() => _report = report);
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () => _report = DiagnosticReport(DateTime.now(), [
            DiagnosticCheck('network', diagnosticFailure('unexpected'), 0),
          ]),
        );
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    final report = _report;
    if (report == null || _busy) return;
    try {
      await Clipboard.setData(ClipboardData(text: report.toText()));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Private diagnosis report copied. Paste it to share with support.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The report could not be copied.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // A change of signed-in account cancels this route, so stale credentials or
    // protected stream identifiers cannot be used in a later account session.
    ref.listen(sessionProvider.select((s) => s?.accountId), (previous, next) {
      if (previous != next) {
        _stop();
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      }
    });
    final credentials =
        widget.credentials ?? ref.watch(sessionProvider)?.credentials;
    final report = _report;
    final completed = report?.checks.length ?? 0;
    final next = diagnosticStages.values.elementAt(
      completed.clamp(0, diagnosticStages.length - 1),
    );
    if (ref.watch(isTvProvider)) {
      return TvDiagnosisView(
        report: report,
        busy: _busy,
        canRun: credentials != null,
        onRun: _run,
        onStop: _stop,
        onCopy: _copy,
        progressLabel: next,
        includeStream: widget.canTestStream && widget.item != null
            ? _includeStream
            : null,
        onStreamChanged: (value) => setState(() => _includeStream = value),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Connection diagnosis')),
      body: TvPageNavigation(
        enabled: ref.watch(isTvProvider),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: FocusTraversalGroup(
                policy: WidgetOrderTraversalPolicy(),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Eyebrow('UNDERSTAND YOUR CONNECTION'),
                      const SizedBox(height: 12),
                      Text(
                        'Find the cause. See the next step.',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Check the device network, provider DNS, server port, HTTPS, account and library endpoints. Each failed check explains what happened and how to respond.',
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Checks contact your configured provider and the system DNS resolver. There is no external speed-test or diagnosis service. Reports omit server addresses, login details and viewing titles.',
                        style: TextStyle(color: AppColors.muted, height: 1.5),
                      ),
                      const SizedBox(height: 16),
                      if (widget.canTestStream && widget.item != null)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Include selected stream sample'),
                          subtitle: const Text(
                            'Optional: opens one short stream request, reads at most 64 KiB, then closes it. This can briefly count as a provider connection. It does not decode video or measure sustained speed.',
                          ),
                          value: _includeStream,
                          onChanged: _busy
                              ? null
                              : (value) =>
                                    setState(() => _includeStream = value),
                        )
                      else
                        const Text(
                          'No video stream will be opened. To test a selected stream, use Connection diagnosis from the player’s error screen.',
                          style: TextStyle(color: AppColors.muted),
                        ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton.icon(
                            autofocus: true,
                            onPressed: credentials == null
                                ? null
                                : _busy
                                ? _stop
                                : _run,
                            icon: Icon(
                              _busy
                                  ? Icons.stop_circle_outlined
                                  : Icons.network_check,
                            ),
                            label: Text(
                              _busy
                                  ? 'Stop diagnosis'
                                  : report == null
                                  ? 'Run diagnosis'
                                  : 'Run again',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: report == null || _busy ? null : _copy,
                            icon: const Icon(Icons.copy_outlined),
                            label: const Text('Copy private report'),
                          ),
                        ],
                      ),
                      if (credentials == null)
                        const Padding(
                          padding: EdgeInsets.only(top: 16),
                          child: Text(
                            'Enter your provider address and account details on the sign-in screen first.',
                          ),
                        ),
                      const SizedBox(height: 24),
                      if (_busy) ...[
                        LinearProgressIndicator(
                          value: completed / diagnosticStages.length,
                        ),
                        const SizedBox(height: 12),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            'Checking: $next… Each network probe is limited to eight seconds.',
                          ),
                        ),
                      ] else if (report != null)
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            report.summary,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                      const SizedBox(height: 18),
                      if (report != null)
                        for (final check in report.checks) _checkCard(check),
                      const SizedBox(height: 18),
                      const Text(
                        'What these checks cannot prove',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'A timeout does not prove ISP blocking. Android’s network/VPN/Private DNS indicators are a snapshot and do not verify a tunnel or DNS provider. Secure DNS does not hide the stream server IP. Successful API or sample tests do not guarantee working codecs, audio, subtitles or uninterrupted playback. Secure DNS configuration is not changed by this screen.',
                        style: TextStyle(color: AppColors.muted, height: 1.5),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _checkCard(DiagnosticCheck check) {
    final f = check.finding;
    final color = switch (f.status) {
      DiagnosticStatus.passed => const Color(0xFF6DD6AD),
      DiagnosticStatus.warning => const Color(0xFFE7C980),
      DiagnosticStatus.failed => AppColors.danger,
      DiagnosticStatus.skipped => AppColors.muted,
    };
    final icon = switch (f.status) {
      DiagnosticStatus.passed => Icons.check_circle_outline,
      DiagnosticStatus.warning => Icons.info_outline,
      DiagnosticStatus.failed => Icons.error_outline,
      DiagnosticStatus.skipped => Icons.remove_circle_outline,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        key: ValueKey('${check.stage}-${f.code}'),
        initiallyExpanded: f.status == DiagnosticStatus.failed,
        leading: Icon(icon, color: color),
        title: Text(check.title),
        subtitle: Text(
          '${f.summary}\n${f.status.name.toUpperCase()} · ${f.code} · ${check.elapsedMs} ms',
          style: TextStyle(color: color, height: 1.5),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(f.description, style: const TextStyle(height: 1.5)),
          if (f.evidence.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'Observed on this device',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            for (final observed in f.evidence)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('• $observed'),
              ),
          ],
          if (f.causes.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'Possible causes',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            for (final cause in f.causes)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('• $cause'),
              ),
          ],
          if (f.steps.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'What to try',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            for (var i = 0; i < f.steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('${i + 1}. ${f.steps[i]}'),
              ),
          ],
        ],
      ),
    );
  }
}
