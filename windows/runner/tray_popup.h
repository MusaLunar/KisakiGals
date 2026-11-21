#ifndef RUNNER_TRAY_POPUP_H_
#define RUNNER_TRAY_POPUP_H_

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <vector>

namespace Gdiplus {
class Bitmap;
}

struct TrayRecentGame {
  int id = 0;
  std::wstring title;
  std::wstring subtitle;
  std::wstring cover_path;
  bool running = false;
};

struct TrayPopupData {
  bool dark = false;
  uint32_t accent_argb = 0xFF0078D4u;
  std::wstring version;
  std::wstring running_title;
  std::vector<TrayRecentGame> recent_games;
};

class KisakiTrayPopup {
 public:
  using ActionCallback = std::function<void(const std::string& action)>;

  explicit KisakiTrayPopup(ActionCallback on_action);
  ~KisakiTrayPopup();

  void Show(const TrayPopupData& data);
  void Hide();

 private:
  enum class RegionKind {
    kMenuItem,
    kRecentGame,
    kStopSession,
    kDangerMenuItem,
  };

  struct HitRegion {
    RECT rect;
    std::string action;
    RegionKind kind = RegionKind::kMenuItem;
    size_t recent_index = 0;
  };

  static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wparam,
                                  LPARAM lparam) noexcept;
  LRESULT HandleMessage(HWND hwnd, UINT msg, WPARAM wparam,
                        LPARAM lparam) noexcept;

  void EnsureWindowClass();
  void ApplyDwmAttributes(bool dark);
  void RebuildLayout();
  void Paint(HDC hdc);
  int HitTest(POINT pt) const;

  HWND hwnd_ = nullptr;
  ULONG_PTR gdiplus_token_ = 0;
  ActionCallback on_action_;
  TrayPopupData data_;
  std::vector<HitRegion> regions_;
  int hovered_index_ = -1;
  int pressed_index_ = -1;
  int focused_index_ = -1;
  bool tracking_mouse_ = false;
  bool use_dwm_acrylic_ = false;
  float dpi_scale_ = 1.0f;
  int width_ = 224;
  int height_ = 260;

  int S(int v) const { return static_cast<int>(v * dpi_scale_ + 0.5f); }
  float SF(float v) const { return v * dpi_scale_; }
};

#endif  // RUNNER_TRAY_POPUP_H_
