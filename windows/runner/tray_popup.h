#ifndef RUNNER_TRAY_POPUP_H_
#define RUNNER_TRAY_POPUP_H_

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <functional>
#include <string>
#include <vector>

struct TrayRecentGame {
  int id = 0;
  std::wstring title;
  std::wstring subtitle;
  std::wstring cover_path;
  bool running = false;
};

struct TrayPopupData {
  bool dark = false;
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
  struct HitRegion {
    RECT rect;
    std::string action;
    bool is_danger = false;
    bool is_primary = false;
  };

  static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wparam,
                                  LPARAM lparam) noexcept;
  LRESULT HandleMessage(HWND hwnd, UINT msg, WPARAM wparam,
                        LPARAM lparam) noexcept;

  void EnsureWindowClass();
  void RebuildLayout();
  void Paint(HDC hdc);
  int HitTest(POINT pt) const;

  HWND hwnd_ = nullptr;
  ULONG_PTR gdiplus_token_ = 0;
  ActionCallback on_action_;
  TrayPopupData data_;
  std::vector<HitRegion> regions_;
  int hovered_index_ = -1;
  bool tracking_mouse_ = false;
  float dpi_scale_ = 1.0f;
  int width_ = 308;
  int height_ = 360;

  int S(int v) const { return static_cast<int>(v * dpi_scale_ + 0.5f); }
  float SF(float v) const { return v * dpi_scale_; }
};

#endif  // RUNNER_TRAY_POPUP_H_
