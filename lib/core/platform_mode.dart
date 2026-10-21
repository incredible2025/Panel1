import 'package:flutter/services.dart';

/// Native detection uses UiModeManager, so tablets keep their touch layout.
Future<bool> detectTelevision() async {
  try {
    return await const MethodChannel(
          'streamline/platform',
        ).invokeMethod<bool>('isTelevision') ??
        false;
  } on MissingPluginException {
    return false;
  } on PlatformException {
    return false;
  }
}
