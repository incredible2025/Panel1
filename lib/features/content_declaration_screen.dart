import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_brand.dart';
import '../core/providers.dart';
import '../data/content_declaration.dart';
import '../widgets/tv_app_exit.dart';
import '../widgets/tv_controls.dart';
import '../widgets/tv_page_navigation.dart';
import '../widgets/tv_utility_scaffold.dart';

/// Gates updates, sign-in and catalogue widgets until local acknowledgement is saved.
class ContentDeclarationGate extends ConsumerStatefulWidget {
  const ContentDeclarationGate({super.key, required this.builder});
  final WidgetBuilder builder;
  @override
  ConsumerState<ContentDeclarationGate> createState() =>
      _ContentDeclarationGateState();
}

class _ContentDeclarationGateState
    extends ConsumerState<ContentDeclarationGate> {
  late Future<bool> _accepted;
  @override
  void initState() {
    super.initState();
    _accepted = _read();
  }

  Future<bool> _read() => ref
      .read(storeProvider)
      .hasAcknowledgedContentDeclaration(contentDeclarationVersion);

  Future<void> _accept() async {
    await ref
        .read(storeProvider)
        .acknowledgeContentDeclaration(contentDeclarationVersion);
    if (mounted) {
      setState(() {
        _accepted = Future.value(true);
      });
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _accepted,
    builder: (context, result) {
      if (result.hasError) {
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'The saved declaration could not be read. Please try again.',
                  ),
                  const SizedBox(height: 20),
                  TvControl(
                    label: 'Try again',
                    autofocus: true,
                    onPressed: () => setState(() {
                      _accepted = _read();
                    }),
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      if (!result.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return result.data!
          ? widget.builder(context)
          : ContentDeclarationScreen(onAccept: _accept);
    },
  );
}

/// The same declaration is available read-only in Settings.
class ContentDeclarationScreen extends ConsumerStatefulWidget {
  const ContentDeclarationScreen({super.key, this.onAccept});
  final Future<void> Function()? onAccept;
  @override
  ConsumerState<ContentDeclarationScreen> createState() =>
      _ContentDeclarationScreenState();
}

class _ContentDeclarationScreenState
    extends ConsumerState<ContentDeclarationScreen> {
  final _reading = FocusNode(debugLabel: 'Read content declaration');
  final _acknowledge = FocusNode(debugLabel: 'Acknowledge content declaration');
  final _continue = FocusNode(debugLabel: 'Continue after declaration');
  bool _checked = false, _saving = false;
  String? _error;
  bool get _firstLaunch => widget.onAccept != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(isLargeScreenProvider)) _reading.requestFocus();
    });
  }

  @override
  void dispose() {
    _reading.dispose();
    _acknowledge.dispose();
    _continue.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    if (_saving) return;
    if (!_checked) {
      setState(
        () => _error = 'Please acknowledge the declaration before continuing.',
      );
      _acknowledge.requestFocus();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onAccept!();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Your acknowledgement could not be saved. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toggle() {
    if (_saving) return;
    setState(() {
      _checked = !_checked;
      _error = null;
    });
  }

  Widget _text() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '$appBrandName · Content declaration',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 16),
      for (final section in contentDeclarationSections) ...[
        Text(
          section.$1,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(section.$2, style: const TextStyle(fontSize: 15, height: 1.45)),
        const SizedBox(height: 18),
      ],
    ],
  );

  Widget _actions(bool large) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (large)
        TvControl(
          label: 'Acknowledge declaration',
          focusNode: _acknowledge,
          onPressed: _toggle,
          selected: _checked,
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              _reading.requestFocus();
              return KeyEventResult.handled;
            }
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.arrowDown) {
              _continue.requestFocus();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_checked ? Icons.check_box : Icons.check_box_outline_blank),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  contentDeclarationAcknowledgement,
                  style: TextStyle(fontSize: 14, height: 1.4),
                ),
              ),
            ],
          ),
        )
      else
        CheckboxListTile(
          value: _checked,
          onChanged: _saving ? null : (_) => _toggle(),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(contentDeclarationAcknowledgement),
        ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
      const SizedBox(height: 18),
      if (large)
        TvControl(
          label: 'Acknowledge and continue',
          focusNode: _continue,
          onPressed: _accept,
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.arrowUp) {
              _acknowledge.requestFocus();
              return KeyEventResult.handled;
            }
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              _reading.requestFocus();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Text(_saving ? 'Saving…' : 'Acknowledge and continue'),
        )
      else
        FilledButton(
          onPressed: _checked && !_saving ? _accept : null,
          child: Text(_saving ? 'Saving…' : 'Acknowledge and continue'),
        ),
      const SizedBox(height: 16),
      const Text(
        'If you do not accept this declaration, close the app.',
        style: TextStyle(fontSize: 13),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final large = ref.watch(isLargeScreenProvider);
    final page = large
        ? TvUtilityScaffold(
            title: 'Content declaration',
            showBack: !_firstLaunch,
            hint:
                'Up / Down  Read     Right  Acknowledge     Back  ${_firstLaunch ? 'Exit' : 'Return'}',
            onEnter: _reading.requestFocus,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 6,
                  child: TvScrollPane(
                    label: 'Content declaration',
                    focusNode: _reading,
                    onRight: _firstLaunch ? _acknowledge.requestFocus : null,
                    child: _text(),
                  ),
                ),
                if (_firstLaunch) ...[
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 4,
                    child: SingleChildScrollView(child: _actions(true)),
                  ),
                ],
              ],
            ),
          )
        : Scaffold(
            appBar: AppBar(
              title: const Text('Content declaration'),
              automaticallyImplyLeading: !_firstLaunch,
            ),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [_text(), if (_firstLaunch) _actions(false)],
                ),
              ),
            ),
          );
    if (!_firstLaunch) return page;
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (popped, _) {
        if (popped || _saving) return;
        if (ref.read(isTvProvider)) {
          ref.read(tvAppExitProvider).request(context, ref);
        } else if (!ref.read(isDesktopProvider)) {
          SystemNavigator.pop();
        }
      },
      child: page,
    );
  }
}
