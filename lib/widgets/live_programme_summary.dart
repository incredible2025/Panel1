import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import 'tv_glass_guide.dart';

/// Only visible list rows subscribe to the existing cached channel guide.
class LiveProgrammeSummary extends ConsumerWidget {
  const LiveProgrammeSummary({super.key, required this.channelId});
  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final time =
        ref.watch(programmeClockProvider).asData?.value ?? DateTime.now();
    final state = ref.watch(epgProvider(channelId));
    final slots = glassGuideSlots(state.asData?.value ?? [], time);
    final now = slots[0];
    final next = slots[1];
    String clock(DateTime time) =>
        TimeOfDay.fromDateTime(time.toLocal()).format(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          now != null
              ? 'Now · ${now.title}'
              : state.isLoading
              ? 'Loading guide…'
              : 'Programme guide unavailable',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11),
        ),
        if (next != null)
          Text(
            '${clock(next.start)} · ${next.title}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor),
          ),
      ],
    );
  }
}
