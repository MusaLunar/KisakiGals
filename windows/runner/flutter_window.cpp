#include "flutter_window.h"

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"

namespace {

std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  int count = MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                  static_cast<int>(utf8.size()), nullptr, 0);
  if (count <= 0) return std::wstring();
  std::wstring wide(count, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                      wide.data(), count);
  return wide;
}

std::string GetStringField(const flutter::EncodableMap& map,
                           const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it != map.end()) {
    if (const auto* s = std::get_if<std::string>(&it->second)) {
      return *s;
    }
  }
  return "";
}

bool GetBoolField(const flutter::EncodableMap& map, const char* key,
                  bool def = false) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it != map.end()) {
    if (const auto* b = std::get_if<bool>(&it->second)) {
      return *b;
    }
  }
  return def;
}

int GetIntField(const flutter::EncodableMap& map, const char* key,
                int def = 0) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it != map.end()) {
    if (const auto* v32 = std::get_if<int32_t>(&it->second)) {
      return *v32;
    }
    if (const auto* v64 = std::get_if<int64_t>(&it->second)) {
      return static_cast<int>(*v64);
    }
  }
  return def;
}

}  // namespace

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
  SetupTrayPopupChannel();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::SetupTrayPopupChannel() {
  tray_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "kisaki/tray_menu",
          &flutter::StandardMethodCodec::GetInstance());

  tray_popup_ = std::make_unique<KisakiTrayPopup>(
      [this](const std::string& action) {
        if (tray_channel_) {
          tray_channel_->InvokeMethod(
              "onTrayAction",
              std::make_unique<flutter::EncodableValue>(action));
        }
      });

  tray_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "showPopup") {
          TrayPopupData data;
          if (const auto* args =
                  std::get_if<flutter::EncodableMap>(call.arguments())) {
            data.dark = GetBoolField(*args, "dark", false);
            data.version = Utf8ToWide(GetStringField(*args, "version"));
            data.running_title =
                Utf8ToWide(GetStringField(*args, "runningTitle"));

            auto it = args->find(flutter::EncodableValue("recentGames"));
            if (it != args->end()) {
              if (const auto* list =
                      std::get_if<flutter::EncodableList>(&it->second)) {
                for (const auto& item : *list) {
                  if (const auto* gm =
                          std::get_if<flutter::EncodableMap>(&item)) {
                    TrayRecentGame rg;
                    rg.id = GetIntField(*gm, "id", 0);
                    rg.title = Utf8ToWide(GetStringField(*gm, "title"));
                    rg.subtitle = Utf8ToWide(GetStringField(*gm, "subtitle"));
                    rg.cover_path =
                        Utf8ToWide(GetStringField(*gm, "coverPath"));
                    rg.running = GetBoolField(*gm, "running", false);
                    if (rg.id > 0 && !rg.title.empty()) {
                      data.recent_games.push_back(std::move(rg));
                    }
                  }
                }
              }
            }
          }
          if (tray_popup_) {
            tray_popup_->Show(data);
          }
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "hidePopup") {
          if (tray_popup_) {
            tray_popup_->Hide();
          }
          result->Success(flutter::EncodableValue(true));
        } else {
          result->NotImplemented();
        }
      });
}

void FlutterWindow::OnDestroy() {
  tray_popup_.reset();
  tray_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
