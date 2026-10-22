import 'package:flutter/material.dart';
import '../core/design_system.dart';

class StatusView extends StatelessWidget {
  const StatusView({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.onRetry,
    this.loading = false,
  });

  final String title;
  final String? message;
  final IconData icon;
  final VoidCallback? onRetry;
  final bool loading;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent.withValues(alpha: .055),
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: .13),
                  ),
                ),
                child: Icon(icon, color: AppColors.accent, size: 32),
              ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

String formatPlaybackTime(int milliseconds) {
  final seconds = milliseconds ~/ 1000;
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final remainder = seconds % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
  }
  return '$minutes:${remainder.toString().padLeft(2, '0')}';
}
