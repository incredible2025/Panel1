import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Windows keeps a normal title bar; F11 toggles the native fullscreen window.
class DesktopControls extends StatelessWidget {
  const DesktopControls({super.key, required this.child});
  final Widget child;
  static const channel = MethodChannel('streamline/platform');
  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.f11): () async {
        try {
          await channel.invokeMethod<void>('toggleFullscreen');
        } on PlatformException {
          // Window changes must never interrupt a stream.
        } on MissingPluginException {
          // Widget harnesses do not have a native window.
        }
      },
    },
    child: child,
  );
}
