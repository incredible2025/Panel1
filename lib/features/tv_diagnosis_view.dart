import 'package:flutter/material.dart';
import '../data/connection_diagnostics.dart';
import '../widgets/tv_controls.dart';
import '../widgets/tv_glass_theme.dart';
import '../widgets/tv_page_navigation.dart';
import '../widgets/tv_utility_scaffold.dart';

class TvDiagnosisView extends StatefulWidget {
  const TvDiagnosisView({
    super.key,
    required this.report,
    required this.busy,
    required this.canRun,
    required this.onRun,
    required this.onStop,
    required this.onCopy,
    required this.progressLabel,
    this.includeStream,
    this.onStreamChanged,
  });
  final DiagnosticReport? report;
  final bool busy, canRun;
  final VoidCallback onRun, onStop, onCopy;
  final String progressLabel;
  final bool? includeStream;
  final ValueChanged<bool>? onStreamChanged;
  @override
  State<TvDiagnosisView> createState() => _TvDiagnosisViewState();
}

class _TvDiagnosisViewState extends State<TvDiagnosisView> {
  final _checks = GlobalKey<TvRemoteListState>();
  final _reading = FocusNode(debugLabel: 'Diagnosis explanation');
  final _run = FocusNode(debugLabel: 'Diagnosis action');
  final _copy = FocusNode(debugLabel: 'Copy diagnosis');
  final _stream = FocusNode(debugLabel: 'Diagnosis stream option');
  String? _stage;
  @override
  void dispose() {
    _reading.dispose();
    _run.dispose();
    _copy.dispose();
    _stream.dispose();
    super.dispose();
  }

  Widget _text(String value, {Color? color}) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Text(
      value,
      style: TextStyle(fontSize: 14, height: 1.5, color: color),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final checks = widget.report?.checks ?? <DiagnosticCheck>[];
    final selected =
        checks.where((e) => e.stage == _stage).firstOrNull ??
        checks.firstOrNull;
    void focusChecks() {
      if (checks.isEmpty) {
        _reading.requestFocus();
      } else {
        _checks.currentState?.focusSelected(remember: true);
      }
    }

    final details = selected?.finding;
    return TvUtilityScaffold(
      title: 'Connection diagnosis',
      subtitle: widget.busy
          ? 'Checking: ${widget.progressLabel}'
          : widget.report?.summary ?? 'Find the cause. See the next step.',
      onEnter: _run.requestFocus,
      hint:
          'Left / Right  Checks, explanation, actions    Up / Down  Browse / read    OK  Select    Back  Return',
      child: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 322,
                  child: checks.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'Run diagnosis to check this device’s network, DNS and connection to your provider.',
                            style: TextStyle(fontSize: 17, height: 1.5),
                          ),
                        )
                      : TvRemoteList(
                          key: _checks,
                          label: 'Diagnosis check',
                          fullRows: true,
                          titleSize: 14,
                          extent: 53,
                          dense: true,
                          onLeft: _run.requestFocus,
                          onRight: _reading.requestFocus,
                          onTop: () {},
                          onBottom: _run.requestFocus,
                          entries: [
                            for (final check in checks)
                              TvListEntry(
                                id: check.stage,
                                title: check.title,
                                subtitle:
                                    '${check.finding.status.name.toUpperCase()} · ${check.finding.code}',
                                selected: selected?.stage == check.stage,
                                onFocused: () =>
                                    setState(() => _stage = check.stage),
                                onPressed: _reading.requestFocus,
                              ),
                          ],
                        ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: TvScrollPane(
                    key: ValueKey('${selected?.stage}/${details?.code}'),
                    label: 'Diagnosis explanation and next steps',
                    focusNode: _reading,
                    onLeft: focusChecks,
                    onRight: _run.requestFocus,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (selected != null && details != null) ...[
                          Text(
                            selected.title,
                            style: const TextStyle(fontSize: 22),
                          ),
                          const SizedBox(height: 14),
                          _text(
                            '${details.status.name.toUpperCase()} · ${details.code} · ${selected.elapsedMs} ms',
                            color: TvGlass.accent,
                          ),
                          _text(details.summary),
                          _text(details.description),
                          if (details.evidence.isNotEmpty) ...[
                            _text(
                              'Observed on this device',
                              color: TvGlass.accent,
                            ),
                            for (final e in details.evidence) _text('• $e'),
                          ],
                          if (details.causes.isNotEmpty) ...[
                            _text('Possible causes', color: TvGlass.accent),
                            for (final e in details.causes) _text('• $e'),
                          ],
                          if (details.steps.isNotEmpty) ...[
                            _text('What to try', color: TvGlass.accent),
                            for (var i = 0; i < details.steps.length; i++)
                              _text('${i + 1}. ${details.steps[i]}'),
                          ],
                        ] else ...[
                          _text(
                            'Your current connection',
                            color: TvGlass.accent,
                          ),
                          _text(
                            'Checks run on this device using its active Wi-Fi, Ethernet or VPN and system DNS resolver. They contact your configured provider; they do not use an external diagnosis service.',
                          ),
                          _text(
                            'Reports omit server addresses, login details and viewing titles. Select a result on the left to read its evidence, possible causes and practical next steps.',
                          ),
                          if (!widget.canRun)
                            _text(
                              'Enter your username and password on the sign-in screen first.',
                            ),
                        ],
                        const Divider(),
                        _text(
                          'What these checks cannot prove',
                          color: TvGlass.accent,
                        ),
                        _text(
                          'A timeout does not prove ISP blocking. Network, VPN and Private DNS indicators are a snapshot and do not verify a tunnel or DNS provider. Secure DNS does not hide the stream server IP. Successful API or sample tests do not guarantee codecs, audio or uninterrupted playback. This screen does not change Secure DNS.',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TvUtilityAction(
                  label: widget.busy
                      ? 'Stop diagnosis'
                      : widget.report == null
                      ? 'Run diagnosis'
                      : 'Run again',
                  focusNode: _run,
                  autofocus: true,
                  onPressed: widget.canRun
                      ? widget.busy
                            ? widget.onStop
                            : widget.onRun
                      : null,
                  onLeft: _reading.requestFocus,
                  onRight: _copy.requestFocus,
                  onUp: focusChecks,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TvUtilityAction(
                  label: 'Copy private report',
                  focusNode: _copy,
                  onPressed: widget.report == null || widget.busy
                      ? null
                      : widget.onCopy,
                  onLeft: _run.requestFocus,
                  onRight: widget.includeStream == null
                      ? _reading.requestFocus
                      : _stream.requestFocus,
                  onUp: _reading.requestFocus,
                ),
              ),
              if (widget.includeStream != null) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: TvUtilityAction(
                    label:
                        'Stream sample: ${widget.includeStream! ? 'On' : 'Off'}',
                    focusNode: _stream,
                    onPressed: widget.busy
                        ? null
                        : () => widget.onStreamChanged?.call(
                            !widget.includeStream!,
                          ),
                    onLeft: _copy.requestFocus,
                    onUp: _reading.requestFocus,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
