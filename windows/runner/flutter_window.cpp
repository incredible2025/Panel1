#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr UINT kNetworkChangedMessage = WM_APP + 24;
void CALLBACK NetworkChanged(void* context, PMIB_IPINTERFACE_ROW,
                             MIB_NOTIFICATION_TYPE) {
  // OS callbacks run off the UI thread; deliver the Dart event on the window.
  PostMessageW(static_cast<HWND>(context), kNetworkChangedMessage, 0, 0);
}
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  platform_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "streamline/platform",
      &flutter::StandardMethodCodec::GetInstance());
  platform_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() == "isTelevision") {
          result->Success(flutter::EncodableValue(false));
        } else if (call.method_name() == "networkDiagnosis") {
          // Do not infer internet access or VPN status from adapter presence.
          // Dart probes the resolver and service from this PC's own network.
          result->Success(flutter::EncodableValue(flutter::EncodableMap{}));
        } else if (call.method_name() == "toggleFullscreen") {
          ToggleFullscreen();
          result->Success();
        } else if (call.method_name() == "setKeepScreenOn") {
          const auto* enabled = call.arguments() ? std::get_if<bool>(call.arguments()) : nullptr;
          SetThreadExecutionState(ES_CONTINUOUS | ((enabled && *enabled) ? ES_DISPLAY_REQUIRED : 0));
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  if (NotifyIpInterfaceChange(AF_UNSPEC, NetworkChanged, GetHandle(), FALSE,
                             &network_change_handle_) != NO_ERROR) {
    network_change_handle_ = nullptr;
  }

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (network_change_handle_) {
    CancelMibChangeNotify2(network_change_handle_);
    network_change_handle_ = nullptr;
  }
  SetThreadExecutionState(ES_CONTINUOUS);
  platform_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == kNetworkChangedMessage) {
    if (platform_channel_) platform_channel_->InvokeMethod("networkChanged", nullptr);
    return 0;
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_GETMINMAXINFO: {
      // The shared Glass layout remains readable at its smallest window size.
      const UINT dpi = GetDpiForWindow(hwnd);
      auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
      info->ptMinTrackSize.x = MulDiv(960, static_cast<int>(dpi), 96);
      info->ptMinTrackSize.y = MulDiv(600, static_cast<int>(dpi), 96);
      return 0;
    }
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::ToggleFullscreen() {
  HWND window = GetHandle();
  const auto style = GetWindowLongPtr(window, GWL_STYLE);
  if (!fullscreen_) {
    MONITORINFO monitor = {sizeof(MONITORINFO)};
    if (!GetWindowPlacement(window, &placement_) ||
        !GetMonitorInfo(MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST), &monitor)) return;
    SetWindowLongPtr(window, GWL_STYLE, style & ~WS_OVERLAPPEDWINDOW);
    SetWindowPos(window, HWND_TOP, monitor.rcMonitor.left, monitor.rcMonitor.top,
                 monitor.rcMonitor.right - monitor.rcMonitor.left,
                 monitor.rcMonitor.bottom - monitor.rcMonitor.top,
                 SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
    fullscreen_ = true;
  } else {
    SetWindowLongPtr(window, GWL_STYLE, style | WS_OVERLAPPEDWINDOW);
    SetWindowPlacement(window, &placement_);
    SetWindowPos(window, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
    fullscreen_ = false;
  }
}
