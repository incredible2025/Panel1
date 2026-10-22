import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/app_settings.dart';
import '../data/local_store.dart';
import 'providers.dart';

final settingsProvider =
    StateNotifierProvider<SettingsController, AsyncValue<AppSettings>>((ref) {
      final account = ref.watch(
        sessionProvider.select((session) => session?.accountId),
      );
      return SettingsController(
        account == null ? null : ref.watch(storeProvider),
        account,
      );
    });

class SettingsController extends StateNotifier<AsyncValue<AppSettings>> {
  SettingsController(this.store, this.account) : super(const AsyncLoading()) {
    ready = reload();
  }
  final LocalStore? store;
  final String? account;
  late Future<void> ready;
  Future<void> _writes = Future.value();
  String? saveError;
  AppSettings get current => state.asData?.value ?? const AppSettings();
  Future<void> reload() async {
    try {
      final settings = store == null || account == null
          ? const AppSettings()
          : await store!.readSettings(account!);
      if (mounted) state = AsyncData(settings);
    } catch (error, stack) {
      if (mounted) state = AsyncError(error, stack);
    }
  }

  Future<bool> patch(Map<String, dynamic> values) =>
      update((settings) => settings.patch(values));
  Future<bool> update(AppSettings Function(AppSettings) change) {
    final complete = Completer<bool>();
    _writes = _writes.then((_) async {
      await ready;
      if (!mounted || state.hasError || account == null || store == null) {
        complete.complete(false);
        return;
      }
      final previous = current;
      try {
        final next = change(previous);
        await store!.saveSettings(account!, next);
        if (mounted) {
          saveError = null;
          state = AsyncData(next);
        }
        complete.complete(true);
      } catch (_) {
        if (mounted) {
          saveError = 'Preferences could not be saved. Please try again.';
          state = AsyncData(previous);
        }
        complete.complete(false);
      }
    });
    return complete.future;
  }
}

final parentalSessionProvider = StateNotifierProvider<ParentalSession, bool>((
  ref,
) {
  ref.watch(sessionProvider.select((session) => session?.accountId));
  return ParentalSession();
});

class ParentalSession extends StateNotifier<bool> {
  ParentalSession() : super(false);
  Timer? _expiry;
  void unlock() {
    _expiry?.cancel();
    state = true;
    _expiry = Timer(const Duration(minutes: 5), lock);
  }

  void lock() {
    _expiry?.cancel();
    if (mounted) state = false;
  }

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }
}

final pinConfiguredProvider = FutureProvider<bool>((ref) {
  final account = ref.watch(
    sessionProvider.select((session) => session?.accountId),
  );
  return account == null ? false : ref.watch(storeProvider).hasPin(account);
});
