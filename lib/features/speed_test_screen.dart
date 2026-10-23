import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design_system.dart';
import '../core/providers.dart';
import '../data/speed_test.dart';
import '../widgets/tv_page_navigation.dart';
import '../widgets/tv_glass_theme.dart';
import '../widgets/tv_utility_scaffold.dart';

final speedTestFactoryProvider = Provider<SpeedTestRunner Function()>(
  (ref) =>
      () => SpeedTestRunner(IoSpeedTestTransport()),
);

class SpeedTestScreen extends ConsumerStatefulWidget {
  const SpeedTestScreen({super.key});
  @override
  ConsumerState<SpeedTestScreen> createState() => _SpeedTestScreenState();
}

class _SpeedTestScreenState extends ConsumerState<SpeedTestScreen>
    with WidgetsBindingObserver {
  SpeedTestRunner? _runner;
  SpeedResult? _result;
  bool _busy = false;
  int _generation = 0;
  final _primary = FocusNode(debugLabel: 'Speed test action');
  final _copyFocus = FocusNode(debugLabel: 'Copy speed results');
  final _reading = FocusNode(debugLabel: 'Speed test explanation');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _generation++;
    _runner?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _primary.dispose();
    _copyFocus.dispose();
    _reading.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _busy) _stop();
  }

  void _stop() {
    _generation++;
    _runner?.cancel();
    final old = _result;
    if (mounted) {
      setState(() {
        _busy = false;
        _result = SpeedResult(
          phase: SpeedPhase.finished,
          download: old?.download,
          upload: old?.upload,
          latency: old?.latency,
          jitter: old?.jitter,
          notices: old?.notices ?? const [],
          cancelled: true,
        );
      });
    }
  }

  Future<void> _run() async {
    if (_busy) return;
    final generation = ++_generation;
    final runner = ref.read(speedTestFactoryProvider)();
    _runner = runner;
    setState(() {
      _busy = true;
      _result = const SpeedResult();
    });
    try {
      final result = await runner.run(
        onProgress: (value) {
          if (mounted && generation == _generation) {
            setState(() => _result = value);
          }
        },
      );
      if (mounted && generation == _generation) {
        setState(() => _result = result);
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () => _result = const SpeedResult(
            phase: SpeedPhase.finished,
            notices: ['The speed test could not complete. Please retry.'],
          ),
        );
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: _result!.toText()));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Speed test results copied.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Results could not be copied.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionProvider.select((s) => s?.accountId), (previous, next) {
      if (previous != next && _busy) _stop();
    });
    final result = _result;
    final heading = _busy
        ? switch (result?.phase) {
            SpeedPhase.download => 'Measuring download…',
            SpeedPhase.upload => 'Measuring upload…',
            _ => 'Measuring latency…',
          }
        : result == null
        ? 'How fast is your connection?'
        : result.cancelled
        ? 'Test stopped'
        : result.timedOut
        ? 'Test time limit reached'
        : result.notices.isNotEmpty
        ? 'Test finished with notices'
        : 'Your results';
    if (ref.watch(isTvProvider)) return _television(heading, result);
    return Scaffold(
      appBar: AppBar(title: const Text('Speed test')),
      body: TvPageNavigation(
        enabled: ref.watch(isTvProvider),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: FocusTraversalGroup(
                  policy: WidgetOrderTraversalPolicy(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Eyebrow('YOUR CURRENT CONNECTION'),
                      const SizedBox(height: 14),
                      Text(
                        heading,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Measures this device’s connection to Cloudflare using your current Wi-Fi, Ethernet, mobile data or VPN. The route to your TV provider may perform differently.',
                        style: TextStyle(color: AppColors.muted, height: 1.5),
                      ),
                      const SizedBox(height: 22),
                      LayoutBuilder(
                        builder: (context, size) => Wrap(
                          spacing: 14,
                          runSpacing: 14,
                          children: [
                            for (final metric in [
                              (
                                'Download',
                                result?.download,
                                'Mbps',
                                Icons.south_rounded,
                              ),
                              (
                                'Upload',
                                result?.upload,
                                'Mbps',
                                Icons.north_rounded,
                              ),
                              (
                                'HTTP latency',
                                result?.latency,
                                'ms',
                                Icons.timer_outlined,
                              ),
                              (
                                'Jitter',
                                result?.jitter,
                                'ms',
                                Icons.multiline_chart,
                              ),
                            ])
                              SizedBox(
                                width: size.maxWidth >= 330
                                    ? (size.maxWidth - 14) / 2
                                    : size.maxWidth,
                                child: Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            metric.$4,
                                            size: 18,
                                            color: AppColors.accent,
                                          ),
                                          const SizedBox(width: 8),
                                          Flexible(child: Text(metric.$1)),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        metric.$2?.toStringAsFixed(
                                              metric.$3 == 'Mbps' ? 1 : 0,
                                            ) ??
                                            '—',
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineLarge
                                            ?.copyWith(color: AppColors.accent),
                                      ),
                                      Text(
                                        metric.$3,
                                        style: const TextStyle(
                                          color: AppColors.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (_busy) ...[
                        LinearProgressIndicator(
                          value: MediaQuery.disableAnimationsOf(context)
                              ? .5
                              : null,
                        ),
                        const SizedBox(height: 18),
                      ],
                      FilledButton.icon(
                        key: ValueKey(_busy ? 'stop-speed' : 'start-speed'),
                        autofocus: true,
                        onPressed: _busy ? _stop : _run,
                        icon: Icon(_busy ? Icons.stop_rounded : Icons.speed),
                        label: Text(
                          _busy
                              ? 'Stop test'
                              : result == null
                              ? 'Start speed test'
                              : 'Run again',
                        ),
                      ),
                      if (!_busy && result?.hasMeasurements == true) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _copy,
                          icon: const Icon(Icons.copy),
                          label: const Text('Copy results'),
                        ),
                      ],
                      if (result != null)
                        for (final notice in result.notices)
                          Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: Text(
                              notice,
                              style: const TextStyle(
                                color: AppColors.muted,
                                height: 1.5,
                              ),
                            ),
                          ),
                      const SizedBox(height: 24),
                      const Text(
                        'Starts only when you choose. Up to 28 MB of test data plus network overhead; stops after 60 seconds. Stop or leave this screen to end the test. Pause other downloads for a clearer estimate.',
                        style: TextStyle(color: AppColors.muted, height: 1.5),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Cloudflare receives your public IP when you run the test. Your TV login and viewing history are never sent. Results stay on this screen unless you copy them.',
                        style: TextStyle(color: AppColors.muted, height: 1.5),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'HTTP latency is not ICMP ping. Jitter is the variation between consecutive latency samples. Speeds are single-connection estimates, including request overhead; they do not guarantee playback quality.',
                        style: TextStyle(color: AppColors.subdued, height: 1.5),
                      ),
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

  Widget _television(String heading, SpeedResult? result) => TvUtilityScaffold(
    title: 'Speed test',
    subtitle: heading,
    onEnter: _primary.requestFocus,
    hint:
        'Left  Test details    Right  Actions    Up / Down  Browse / read    OK  Select    Back  Return',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final metric in [
              ('Download', result?.download, 'Mbps'),
              ('Upload', result?.upload, 'Mbps'),
              ('HTTP latency', result?.latency, 'ms'),
              ('Jitter', result?.jitter, 'ms'),
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Container(
                    key: ValueKey('tv-speed-${metric.$1}'),
                    height: 112,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: TvGlass.panel,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          metric.$1,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.1,
                            color: TvGlass.muted,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          metric.$2?.toStringAsFixed(
                                metric.$3 == 'Mbps' ? 1 : 0,
                              ) ??
                              '—',
                          style: const TextStyle(
                            fontSize: 30,
                            height: 1.1,
                            color: TvGlass.accent,
                          ),
                        ),
                        Text(
                          metric.$2 == null
                              ? 'Not measured · ${metric.$3}'
                              : metric.$3,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.1,
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
        const SizedBox(height: 16),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: TvScrollPane(
                  label: 'Speed test details and notices',
                  focusNode: _reading,
                  onRight: _primary.requestFocus,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (result != null)
                        for (final notice in result.notices)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Text(
                              notice,
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.4,
                                color: Color(0xFFFFC9B4),
                              ),
                            ),
                          ),
                      const Text(
                        'YOUR CURRENT CONNECTION',
                        style: TextStyle(fontSize: 12, color: TvGlass.accent),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Measures this device’s connection to Cloudflare over its current Wi-Fi, Ethernet or VPN. The route to your TV provider may perform differently.',
                        style: TextStyle(fontSize: 14, height: 1.5),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Starts only when you choose. Up to 28 MB of test data plus network overhead; stops after 60 seconds. Stop or leave this screen to end the test. Pause other downloads for a clearer estimate.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: TvGlass.muted,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Cloudflare receives your public IP when you run the test. Your TV login and viewing history are never sent. Results stay on this screen unless you copy them.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: TvGlass.muted,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'HTTP latency is not ICMP ping. Jitter is variation between consecutive latency samples. Speeds are single-connection estimates including request overhead; they do not guarantee playback quality.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: TvGlass.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 20),
              SizedBox(
                width: 244,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TvUtilityAction(
                      label: _busy
                          ? 'Stop test'
                          : result == null
                          ? 'Start speed test'
                          : 'Run again',
                      onPressed: _busy ? _stop : _run,
                      focusNode: _primary,
                      autofocus: true,
                      onLeft: _reading.requestFocus,
                      onDown: result?.hasMeasurements == true && !_busy
                          ? _copyFocus.requestFocus
                          : _reading.requestFocus,
                    ),
                    if (!_busy && result?.hasMeasurements == true) ...[
                      const SizedBox(height: 12),
                      TvUtilityAction(
                        label: 'Copy results',
                        onPressed: _copy,
                        focusNode: _copyFocus,
                        onUp: _primary.requestFocus,
                        onLeft: _reading.requestFocus,
                        onDown: _reading.requestFocus,
                      ),
                    ],
                    const SizedBox(height: 20),
                    if (_busy) ...[
                      LinearProgressIndicator(
                        value: MediaQuery.disableAnimationsOf(context)
                            ? .5
                            : null,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        heading,
                        style: const TextStyle(
                          fontSize: 13,
                          color: TvGlass.muted,
                        ),
                      ),
                    ],
                    const Spacer(),
                    const Text(
                      'Data limit: 28 MB\nTime limit: 60 seconds\n\nStop test ends network traffic.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: TvGlass.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
