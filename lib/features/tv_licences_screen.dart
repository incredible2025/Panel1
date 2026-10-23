import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../widgets/status_view.dart';
import '../widgets/tv_controls.dart';
import '../widgets/tv_page_navigation.dart';
import '../widgets/tv_utility_scaffold.dart';

class TvLicencesScreen extends StatefulWidget {
  const TvLicencesScreen({super.key});
  @override
  State<TvLicencesScreen> createState() => _TvLicencesScreenState();
}

class _TvLicencesScreenState extends State<TvLicencesScreen> {
  late final _licenses = LicenseRegistry.licenses.toList();
  final _list = GlobalKey<TvRemoteListState>();
  final _reading = FocusNode(debugLabel: 'Licence text');
  int _selected = 0;
  @override
  void dispose() {
    _reading.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TvUtilityScaffold(
    title: 'Open source licences',
    hint:
        'Left  Library list    Right  Licence text    Up / Down  Browse / read    Back  Return',
    child: FutureBuilder<List<LicenseEntry>>(
      future: _licenses,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const StatusView(title: 'Licences unavailable');
        }
        final entries = snapshot.data;
        if (entries == null) {
          return const StatusView(title: 'Loading licences', loading: true);
        }
        if (entries.isEmpty) {
          return const StatusView(title: 'No licences registered');
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 320,
              child: TvRemoteList(
                key: _list,
                autofocus: true,
                label: 'Licence',
                fullRows: true,
                titleSize: 14,
                extent: 48,
                dense: true,
                onTop: () {},
                onLeft: () {},
                onRight: _reading.requestFocus,
                entries: [
                  for (var i = 0; i < entries.length; i++)
                    TvListEntry(
                      id: '$i',
                      title: entries[i].packages.join(', '),
                      selected: i == _selected,
                      onFocused: () => setState(() => _selected = i),
                      onPressed: _reading.requestFocus,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: TvScrollPane(
                key: ValueKey(_selected),
                label: 'Full licence text',
                focusNode: _reading,
                onLeft: () => _list.currentState?.focusSelected(remember: true),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      entries[_selected].packages.join(', '),
                      style: const TextStyle(fontSize: 22),
                    ),
                    const SizedBox(height: 18),
                    for (final paragraph in entries[_selected].paragraphs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          paragraph.text,
                          style: const TextStyle(fontSize: 13, height: 1.5),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
