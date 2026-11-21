#include "tray_popup.h"

#include <dwmapi.h>
#include <objidl.h>
#include <gdiplus.h>
#include <windowsx.h>

#include <algorithm>
#include <cmath>
#include <vector>

#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif
#ifndef DWMWA_WINDOW_CORNER_PREFERENCE
#define DWMWA_WINDOW_CORNER_PREFERENCE 33
#endif
#ifndef DWMWCP_ROUND
#define DWMWCP_ROUND 2
#endif
#ifndef DWMWA_SYSTEMBACKDROP_TYPE
#define DWMWA_SYSTEMBACKDROP_TYPE 38
#endif
#ifndef DWMSBT_TRANSIENTWINDOW
#define DWMSBT_TRANSIENTWINDOW 3
#endif

namespace {

constexpr const wchar_t kTrayPopupClassName[] = L"KisakiTrayPopupWindow";
bool g_class_registered = false;

// Unicode string constants (ASCII-escaped to avoid any MSVC codepage issues)
// "停止会话 · "
constexpr const wchar_t kStrStopSessionPrefix[] =
    L"\u505C\u6B62\u4F1A\u8BDD \u00B7 ";
// "运行中"
constexpr const wchar_t kStrRunning[] = L"\u8FD0\u884C\u4E2D";
// "打开主窗口"
constexpr const wchar_t kStrNavShow[] = L"\u6253\u5F00\u4E3B\u7A97\u53E3";
// "我的游戏库"
constexpr const wchar_t kStrNavLibrary[] = L"\u6211\u7684\u6E38\u620F\u5E93";
// "探索发现"
constexpr const wchar_t kStrNavDiscover[] = L"\u63A2\u7D22\u53D1\u73B0";
// "游玩统计"
constexpr const wchar_t kStrNavStats[] = L"\u6E38\u73A9\u7EDF\u8BA1";
// "偏好设置"
constexpr const wchar_t kStrNavSettings[] = L"\u504F\u597D\u8BBE\u7F6E";
// "退出 KisakiGals"
constexpr const wchar_t kStrQuit[] = L"\u9000\u51FA KisakiGals";

// Segoe Fluent Icons / Segoe MDL2 Assets shared codepoints
constexpr const wchar_t kGlyphPlay[] = L"\uE768";
constexpr const wchar_t kGlyphStop[] = L"\uE71A";
constexpr const wchar_t kGlyphHome[] = L"\uE80F";
constexpr const wchar_t kGlyphLibrary[] = L"\uE8F1";
constexpr const wchar_t kGlyphExplore[] = L"\uE774";
constexpr const wchar_t kGlyphStats[] = L"\uE9D2";
constexpr const wchar_t kGlyphSettings[] = L"\uE713";
constexpr const wchar_t kGlyphQuit[] = L"\uE7E8";

void AddRoundRect(Gdiplus::GraphicsPath& path, Gdiplus::RectF r, float radius) {
  if (radius <= 0.5f) {
    path.AddRectangle(r);
    return;
  }
  float d = std::min({radius * 2.0f, r.Width, r.Height});
  path.AddArc(r.X, r.Y, d, d, 180.0f, 90.0f);
  path.AddArc(r.GetRight() - d, r.Y, d, d, 270.0f, 90.0f);
  path.AddArc(r.GetRight() - d, r.GetBottom() - d, d, d, 0.0f, 90.0f);
  path.AddArc(r.X, r.GetBottom() - d, d, d, 90.0f, 90.0f);
  path.CloseFigure();
}

void FillRoundRect(Gdiplus::Graphics& g, Gdiplus::RectF r, float radius,
                   const Gdiplus::Color& color) {
  Gdiplus::GraphicsPath path;
  AddRoundRect(path, r, radius);
  Gdiplus::SolidBrush brush(color);
  g.FillPath(&brush, &path);
}

void DrawRoundRect(Gdiplus::Graphics& g, Gdiplus::RectF r, float radius,
                   const Gdiplus::Color& color, float stroke_width = 1.0f) {
  Gdiplus::GraphicsPath path;
  AddRoundRect(path, r, radius);
  Gdiplus::Pen pen(color, stroke_width);
  g.DrawPath(&pen, &path);
}

Gdiplus::RectF ToRectF(const RECT& rc) {
  return Gdiplus::RectF(
      static_cast<float>(rc.left), static_cast<float>(rc.top),
      static_cast<float>(rc.right - rc.left),
      static_cast<float>(rc.bottom - rc.top));
}

}  // namespace

KisakiTrayPopup::KisakiTrayPopup(ActionCallback on_action)
    : on_action_(std::move(on_action)) {
  Gdiplus::GdiplusStartupInput gdiplus_startup_input;
  Gdiplus::GdiplusStartup(&gdiplus_token_, &gdiplus_startup_input, nullptr);
}

KisakiTrayPopup::~KisakiTrayPopup() {
  Hide();
  if (hwnd_) {
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
  if (gdiplus_token_ != 0) {
    Gdiplus::GdiplusShutdown(gdiplus_token_);
    gdiplus_token_ = 0;
  }
}

void KisakiTrayPopup::EnsureWindowClass() {
  if (g_class_registered) return;
  WNDCLASSEXW wc = {};
  wc.cbSize = sizeof(WNDCLASSEXW);
  wc.style = CS_HREDRAW | CS_VREDRAW;
  wc.lpfnWndProc = KisakiTrayPopup::WndProc;
  wc.hInstance = GetModuleHandle(nullptr);
  wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
  wc.hbrBackground = nullptr;
  wc.lpszClassName = kTrayPopupClassName;
  RegisterClassExW(&wc);
  g_class_registered = true;
}

void KisakiTrayPopup::ApplyDwmAttributes(bool dark) {
  if (!hwnd_) return;

  BOOL dark_val = dark ? TRUE : FALSE;
  DwmSetWindowAttribute(hwnd_, DWMWA_USE_IMMERSIVE_DARK_MODE, &dark_val,
                        sizeof(dark_val));

  DWORD corner_pref = DWMWCP_ROUND;
  DwmSetWindowAttribute(hwnd_, DWMWA_WINDOW_CORNER_PREFERENCE, &corner_pref,
                        sizeof(corner_pref));

  DWORD backdrop = DWMSBT_TRANSIENTWINDOW;
  HRESULT hr = DwmSetWindowAttribute(hwnd_, DWMWA_SYSTEMBACKDROP_TYPE,
                                     &backdrop, sizeof(backdrop));
  if (SUCCEEDED(hr)) {
    use_dwm_acrylic_ = true;
    MARGINS margins = {-1, -1, -1, -1};
    DwmExtendFrameIntoClientArea(hwnd_, &margins);
  } else {
    use_dwm_acrylic_ = false;
  }
}

void KisakiTrayPopup::RebuildLayout() {
  regions_.clear();
  const int pad_x = S(4);
  const int pad_y = S(4);
  const int item_h = S(32);
  const int item_gap = S(2);
  const int sep_space = S(9);
  width_ = S(224);
  int y = pad_y;

  // Group 1: Primary window / active session controls (mirrors MenuFlyout top group)
  {
    RECT rc = {pad_x, y, width_ - pad_x, y + item_h};
    regions_.push_back({rc, "show", RegionKind::kMenuItem, 0});
    y += item_h;
  }
  if (!data_.running_title.empty()) {
    y += item_gap;
    RECT rc = {pad_x, y, width_ - pad_x, y + item_h};
    regions_.push_back({rc, "stop_tracking", RegionKind::kStopSession, 0});
    y += item_h;
  }

  y += sep_space;

  // Group 2 (optional): Up to 2 recent games as uniform MenuFlyout items
  const size_t recent_count = std::min<size_t>(2, data_.recent_games.size());
  if (recent_count > 0) {
    for (size_t i = 0; i < recent_count; ++i) {
      RECT rc = {pad_x, y, width_ - pad_x, y + item_h};
      regions_.push_back(
          {rc,
           "launch_game_" + std::to_string(data_.recent_games[i].id),
           RegionKind::kRecentGame, i});
      y += item_h;
      if (i + 1 < recent_count) y += item_gap;
    }
    y += sep_space;
  }

  // Group 3: Navigation destinations (uniform MenuFlyoutItem rows)
  const char* nav_actions[4] = {
      "nav_library",
      "nav_discover",
      "nav_stats",
      "nav_settings",
  };
  for (int i = 0; i < 4; ++i) {
    RECT rc = {pad_x, y, width_ - pad_x, y + item_h};
    regions_.push_back({rc, nav_actions[i], RegionKind::kMenuItem, 0});
    y += item_h;
    if (i + 1 < 4) y += item_gap;
  }

  y += sep_space;

  // Group 4: Danger quit item
  {
    RECT rc = {pad_x, y, width_ - pad_x, y + item_h};
    regions_.push_back({rc, "quit", RegionKind::kDangerMenuItem, 0});
    y += item_h;
  }

  y += pad_y;
  height_ = y;
}

void KisakiTrayPopup::Show(const TrayPopupData& data) {
  EnsureWindowClass();
  data_ = data;
  hovered_index_ = -1;
  pressed_index_ = -1;
  focused_index_ = -1;

  POINT cursor = {};
  GetCursorPos(&cursor);

  HMONITOR monitor = MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST);
  MONITORINFO mi = {};
  mi.cbSize = sizeof(MONITORINFO);
  GetMonitorInfoW(monitor, &mi);

  UINT dpi = 96;
  if (hwnd_) {
    dpi = GetDpiForWindow(hwnd_);
  } else {
    HDC screen_dc = GetDC(nullptr);
    if (screen_dc) {
      dpi = static_cast<UINT>(GetDeviceCaps(screen_dc, LOGPIXELSX));
      ReleaseDC(nullptr, screen_dc);
    }
  }
  dpi_scale_ = std::clamp(static_cast<float>(dpi) / 96.0f, 1.0f, 2.5f);

  RebuildLayout();

  if (!hwnd_) {
    hwnd_ = CreateWindowExW(
        WS_EX_TOOLWINDOW | WS_EX_TOPMOST, kTrayPopupClassName,
        L"KisakiTrayPopup", WS_POPUP | WS_CLIPCHILDREN, 0, 0, width_, height_,
        nullptr, nullptr, GetModuleHandle(nullptr), this);
    if (!hwnd_) return;
  }

  ApplyDwmAttributes(data_.dark);

  UINT win_dpi = GetDpiForWindow(hwnd_);
  if (win_dpi > 0) {
    float new_scale =
        std::clamp(static_cast<float>(win_dpi) / 96.0f, 1.0f, 2.5f);
    if (std::abs(new_scale - dpi_scale_) > 0.01f) {
      dpi_scale_ = new_scale;
      RebuildLayout();
    }
  }

  const RECT work = mi.rcWork;
  const int margin = S(8);
  int x = cursor.x - width_ / 2;
  int y = cursor.y - height_ - S(10);

  if (y < work.top + margin) {
    y = cursor.y + S(10);
  }
  x = std::clamp(x, static_cast<int>(work.left + margin),
                 static_cast<int>(work.right - width_ - margin));
  y = std::clamp(y, static_cast<int>(work.top + margin),
                 static_cast<int>(work.bottom - height_ - margin));

  SetWindowPos(hwnd_, HWND_TOPMOST, x, y, width_, height_,
               SWP_SHOWWINDOW | SWP_NOACTIVATE);
  ShowWindow(hwnd_, SW_SHOW);
  SetForegroundWindow(hwnd_);
  SetFocus(hwnd_);
  InvalidateRect(hwnd_, nullptr, FALSE);
}

void KisakiTrayPopup::Hide() {
  if (GetCapture() == hwnd_) {
    ReleaseCapture();
  }
  if (hwnd_ && IsWindowVisible(hwnd_)) {
    ShowWindow(hwnd_, SW_HIDE);
  }
  hovered_index_ = -1;
  pressed_index_ = -1;
  focused_index_ = -1;
}

int KisakiTrayPopup::HitTest(POINT pt) const {
  for (size_t i = 0; i < regions_.size(); ++i) {
    if (PtInRect(&regions_[i].rect, pt)) {
      return static_cast<int>(i);
    }
  }
  return -1;
}

void KisakiTrayPopup::Paint(HDC hdc) {
  if (width_ <= 0 || height_ <= 0) return;

  BITMAPINFO bmi = {};
  bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bmi.bmiHeader.biWidth = width_;
  bmi.bmiHeader.biHeight = -height_;  // top-down DIB
  bmi.bmiHeader.biPlanes = 1;
  bmi.bmiHeader.biBitCount = 32;
  bmi.bmiHeader.biCompression = BI_RGB;

  void* dib_bits = nullptr;
  HDC mem_dc = CreateCompatibleDC(hdc);
  HBITMAP dib = CreateDIBSection(mem_dc, &bmi, DIB_RGB_COLORS, &dib_bits, nullptr, 0);
  if (!mem_dc || !dib || !dib_bits) {
    if (dib) DeleteObject(dib);
    if (mem_dc) DeleteDC(mem_dc);
    return;
  }
  HGDIOBJ old_bmp = SelectObject(mem_dc, dib);

  {
    Gdiplus::Bitmap buffer(width_, height_, width_ * 4, PixelFormat32bppPARGB,
                           static_cast<BYTE*>(dib_bits));
    Gdiplus::Graphics g(&buffer);
    g.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    g.SetInterpolationMode(Gdiplus::InterpolationModeHighQualityBicubic);
    g.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAliasGridFit);

    const bool dark = data_.dark;

    const uint32_t raw_accent =
        ((data_.accent_argb & 0xFF000000u) == 0u) ? 0xFF0078D4u
                                                 : data_.accent_argb;
    const BYTE ar = static_cast<BYTE>((raw_accent >> 16) & 0xFFu);
    const BYTE ag = static_cast<BYTE>((raw_accent >> 8) & 0xFFu);
    const BYTE ab = static_cast<BYTE>(raw_accent & 0xFFu);

    // Fluent 2 MenuFlyout acrylic tint + subtle fill interaction states
    const BYTE bg_alpha = use_dwm_acrylic_ ? (dark ? 204 : 220) : 255;
    const Gdiplus::Color flyout_bg =
        dark ? Gdiplus::Color(bg_alpha, 44, 44, 44)
             : Gdiplus::Color(bg_alpha, 249, 249, 249);
    const Gdiplus::Color subtle_hover =
        dark ? Gdiplus::Color(20, 255, 255, 255)
             : Gdiplus::Color(12, 0, 0, 0);
    const Gdiplus::Color subtle_press =
        dark ? Gdiplus::Color(13, 255, 255, 255)
             : Gdiplus::Color(8, 0, 0, 0);
    const Gdiplus::Color divider_color =
        dark ? Gdiplus::Color(26, 255, 255, 255)
             : Gdiplus::Color(20, 0, 0, 0);
    const Gdiplus::Color fallback_border =
        dark ? Gdiplus::Color(255, 68, 68, 68)
             : Gdiplus::Color(255, 224, 224, 224);

    const Gdiplus::Color ink_primary =
        dark ? Gdiplus::Color(255, 245, 245, 245)
             : Gdiplus::Color(255, 24, 24, 24);
    const Gdiplus::Color ink_secondary =
        dark ? Gdiplus::Color(225, 220, 220, 220)
             : Gdiplus::Color(210, 64, 64, 64);
    const Gdiplus::Color focus_ring_color =
        dark ? Gdiplus::Color(220, 255, 255, 255)
             : Gdiplus::Color(185, 0, 0, 0);

    const float luma = 0.2126f * static_cast<float>(ar) +
                       0.7152f * static_cast<float>(ag) +
                       0.0722f * static_cast<float>(ab);
    auto compute_accent_ink = [&]() -> Gdiplus::Color {
      const float fr = static_cast<float>(ar);
      const float fg = static_cast<float>(ag);
      const float fb = static_cast<float>(ab);
      if (dark) {
        if (luma >= 165.0f) return Gdiplus::Color(255, ar, ag, ab);
        const float t = std::clamp(
            (165.0f - luma) / std::max(1.0f, 255.0f - luma), 0.28f, 0.78f);
        return Gdiplus::Color(
            255,
            static_cast<BYTE>(std::clamp(fr + (255.0f - fr) * t, 0.0f, 255.0f)),
            static_cast<BYTE>(std::clamp(fg + (255.0f - fg) * t, 0.0f, 255.0f)),
            static_cast<BYTE>(std::clamp(fb + (255.0f - fb) * t, 0.0f, 255.0f)));
      }
      if (luma <= 92.0f) return Gdiplus::Color(255, ar, ag, ab);
      const float scale = 92.0f / luma;
      return Gdiplus::Color(
          255,
          static_cast<BYTE>(std::clamp(fr * scale, 0.0f, 255.0f)),
          static_cast<BYTE>(std::clamp(fg * scale, 0.0f, 255.0f)),
          static_cast<BYTE>(std::clamp(fb * scale, 0.0f, 255.0f)));
    };
    const Gdiplus::Color accent_ink = compute_accent_ink();

    const Gdiplus::Color danger_ink =
        dark ? Gdiplus::Color(255, 255, 153, 164)
             : Gdiplus::Color(255, 196, 43, 28);
    const Gdiplus::Color danger_fill =
        dark ? Gdiplus::Color(255, 196, 43, 28)
             : Gdiplus::Color(255, 209, 52, 56);
    const Gdiplus::Color danger_tint =
        dark ? Gdiplus::Color(36, 255, 153, 164)
             : Gdiplus::Color(22, 196, 43, 28);
    const Gdiplus::Color on_danger(255, 255, 255, 255);

    g.SetCompositingMode(Gdiplus::CompositingModeSourceCopy);
    g.Clear(flyout_bg);
    g.SetCompositingMode(Gdiplus::CompositingModeSourceOver);

    if (!use_dwm_acrylic_) {
      DrawRoundRect(
          g,
          Gdiplus::RectF(0.5f, 0.5f, static_cast<float>(width_ - 1),
                         static_cast<float>(height_ - 1)),
          SF(8.0f), fallback_border, 1.0f);
    }

    Gdiplus::FontFamily ff_source_cn(L"Source Han Sans CN");
    Gdiplus::FontFamily ff_source_sc(L"Source Han Sans SC");
    Gdiplus::FontFamily ff_yahei(L"Microsoft YaHei UI");
    Gdiplus::FontFamily ff_segoe(L"Segoe UI");
    const Gdiplus::FontFamily* text_ff = Gdiplus::FontFamily::GenericSansSerif();
    for (const auto* candidate :
         {&ff_source_cn, &ff_source_sc, &ff_yahei, &ff_segoe}) {
      if (candidate->IsAvailable()) {
        text_ff = candidate;
        break;
      }
    }
    Gdiplus::FontFamily icon_ff_win11(L"Segoe Fluent Icons");
    Gdiplus::FontFamily icon_ff_win10(L"Segoe MDL2 Assets");
    const Gdiplus::FontFamily* icon_ff =
        icon_ff_win11.IsAvailable()
            ? &icon_ff_win11
            : (icon_ff_win10.IsAvailable() ? &icon_ff_win10 : text_ff);

    Gdiplus::Font font_item(text_ff, SF(13.0f), Gdiplus::FontStyleRegular,
                            Gdiplus::UnitPixel);
    Gdiplus::Font font_item_strong(text_ff, SF(13.0f), Gdiplus::FontStyleBold,
                                   Gdiplus::UnitPixel);
    Gdiplus::Font font_caption(text_ff, SF(11.0f), Gdiplus::FontStyleRegular,
                               Gdiplus::UnitPixel);
    Gdiplus::Font font_icon(icon_ff, SF(14.5f), Gdiplus::FontStyleRegular,
                            Gdiplus::UnitPixel);

    Gdiplus::SolidBrush primary_brush(ink_primary);
    Gdiplus::SolidBrush secondary_brush(ink_secondary);
    Gdiplus::SolidBrush accent_brush(accent_ink);
    Gdiplus::SolidBrush danger_brush(danger_ink);
    Gdiplus::SolidBrush on_danger_brush(on_danger);
    Gdiplus::Pen divider_pen(divider_color, 1.0f);

    Gdiplus::StringFormat left_vcenter;
    left_vcenter.SetAlignment(Gdiplus::StringAlignmentNear);
    left_vcenter.SetLineAlignment(Gdiplus::StringAlignmentCenter);
    left_vcenter.SetTrimming(Gdiplus::StringTrimmingEllipsisCharacter);
    left_vcenter.SetFormatFlags(Gdiplus::StringFormatFlagsNoWrap);

    Gdiplus::StringFormat right_vcenter;
    right_vcenter.SetAlignment(Gdiplus::StringAlignmentFar);
    right_vcenter.SetLineAlignment(Gdiplus::StringAlignmentCenter);
    right_vcenter.SetFormatFlags(Gdiplus::StringFormatFlagsNoWrap);

    Gdiplus::StringFormat center_fmt;
    center_fmt.SetAlignment(Gdiplus::StringAlignmentCenter);
    center_fmt.SetLineAlignment(Gdiplus::StringAlignmentCenter);
    center_fmt.SetFormatFlags(Gdiplus::StringFormatFlagsNoWrap);

    auto draw_separator = [&](int sep_y) {
      g.DrawLine(&divider_pen, 0.0f, static_cast<float>(sep_y),
                 static_cast<float>(width_), static_cast<float>(sep_y));
    };

    auto draw_menu_row = [&](int idx, const wchar_t* glyph,
                             const wchar_t* label, const Gdiplus::Font& font,
                             const Gdiplus::Brush& icon_brush,
                             const Gdiplus::Brush& text_brush,
                             const wchar_t* trailing_caption = nullptr) {
      const bool hovered = (hovered_index_ == idx);
      const bool pressed = (pressed_index_ == idx);
      const Gdiplus::RectF rc = ToRectF(regions_[idx].rect);

      if (regions_[idx].kind == RegionKind::kDangerMenuItem) {
        if (pressed) {
          FillRoundRect(g, rc, SF(4.0f), danger_fill);
        } else if (hovered) {
          FillRoundRect(g, rc, SF(4.0f), danger_tint);
        }
      } else {
        if (pressed) {
          FillRoundRect(g, rc, SF(4.0f), subtle_press);
        } else if (hovered) {
          FillRoundRect(g, rc, SF(4.0f), subtle_hover);
        }
      }

      Gdiplus::RectF icon_rc(rc.X + SF(10.0f), rc.Y, SF(20.0f), rc.Height);
      g.DrawString(glyph, -1, &font_icon, icon_rc, &center_fmt, &icon_brush);

      float right_reserve = SF(10.0f);
      if (trailing_caption != nullptr && trailing_caption[0] != L'\0') {
        right_reserve = SF(52.0f);
        Gdiplus::RectF cap_rc(rc.GetRight() - SF(48.0f), rc.Y, SF(38.0f),
                              rc.Height);
        g.DrawString(trailing_caption, -1, &font_caption, cap_rc,
                     &right_vcenter, &accent_brush);
      }

      Gdiplus::RectF label_rc(icon_rc.GetRight() + SF(10.0f), rc.Y,
                              rc.GetRight() - icon_rc.GetRight() -
                                  SF(10.0f) - right_reserve,
                              rc.Height);
      g.DrawString(label, -1, &font, label_rc, &left_vcenter, &text_brush);

      if (focused_index_ == idx) {
        Gdiplus::RectF fr = rc;
        fr.Inflate(-1.0f, -1.0f);
        DrawRoundRect(g, fr, SF(4.0f), focus_ring_color, 1.5f);
      }
    };

    const int sep_space = S(9);
    const int recent_count =
        static_cast<int>(std::min<size_t>(2, data_.recent_games.size()));

    size_t i = 0;
    // 1. Primary window + optional active session stop item
    if (i < regions_.size()) {
      draw_menu_row(static_cast<int>(i), kGlyphHome, kStrNavShow, font_item,
                    secondary_brush, primary_brush);
      ++i;
    }
    if (!data_.running_title.empty() && i < regions_.size()) {
      const std::wstring stop_label =
          std::wstring(kStrStopSessionPrefix) + data_.running_title;
      draw_menu_row(static_cast<int>(i), kGlyphStop, stop_label.c_str(),
                    font_item_strong, accent_brush, primary_brush);
      ++i;
    }

    if (i > 0) {
      draw_separator(regions_[i - 1].rect.bottom + sep_space / 2);
    }

    // 2. Optional compact recent game items
    if (recent_count > 0) {
      for (int r = 0; r < recent_count && i < regions_.size(); ++r, ++i) {
        const auto& game = data_.recent_games[regions_[i].recent_index];
        const bool hovered = (hovered_index_ == static_cast<int>(i));
        const Gdiplus::Brush& icon_b =
            (game.running || hovered) ? static_cast<const Gdiplus::Brush&>(accent_brush)
                                      : secondary_brush;
        draw_menu_row(static_cast<int>(i), kGlyphPlay, game.title.c_str(),
                      game.running ? font_item_strong : font_item, icon_b,
                      primary_brush, game.running ? kStrRunning : nullptr);
      }
      draw_separator(regions_[i - 1].rect.bottom + sep_space / 2);
    }

    // 3. Navigation menu items
    const wchar_t* nav_icons[4] = {
        kGlyphLibrary,
        kGlyphExplore,
        kGlyphStats,
        kGlyphSettings,
    };
    const wchar_t* nav_labels[4] = {
        kStrNavLibrary,
        kStrNavDiscover,
        kStrNavStats,
        kStrNavSettings,
    };
    for (int n = 0; n < 4 && i < regions_.size(); ++n, ++i) {
      draw_menu_row(static_cast<int>(i), nav_icons[n], nav_labels[n], font_item,
                    secondary_brush, primary_brush);
    }
    if (i > 0) {
      draw_separator(regions_[i - 1].rect.bottom + sep_space / 2);
    }

    // 4. Danger quit item
    if (i < regions_.size()) {
      const bool pressed = (pressed_index_ == static_cast<int>(i));
      const Gdiplus::Brush& b =
          pressed ? static_cast<const Gdiplus::Brush&>(on_danger_brush)
                  : danger_brush;
      draw_menu_row(static_cast<int>(i), kGlyphQuit, kStrQuit, font_item, b, b);
    }
  }

  BitBlt(hdc, 0, 0, width_, height_, mem_dc, 0, 0, SRCCOPY);
  SelectObject(mem_dc, old_bmp);
  DeleteObject(dib);
  DeleteDC(mem_dc);
}

LRESULT CALLBACK KisakiTrayPopup::WndProc(HWND hwnd, UINT msg, WPARAM wparam,
                                          LPARAM lparam) noexcept {
  KisakiTrayPopup* self = nullptr;
  if (msg == WM_NCCREATE) {
    auto* cs = reinterpret_cast<CREATESTRUCT*>(lparam);
    self = static_cast<KisakiTrayPopup*>(cs->lpCreateParams);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    self->hwnd_ = hwnd;
  } else {
    self = reinterpret_cast<KisakiTrayPopup*>(
        GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  }
  if (self) {
    return self->HandleMessage(hwnd, msg, wparam, lparam);
  }
  return DefWindowProcW(hwnd, msg, wparam, lparam);
}

LRESULT KisakiTrayPopup::HandleMessage(HWND hwnd, UINT msg, WPARAM wparam,
                                       LPARAM lparam) noexcept {
  switch (msg) {
    case WM_ERASEBKGND:
      return 1;

    case WM_PAINT: {
      PAINTSTRUCT ps;
      HDC hdc = BeginPaint(hwnd, &ps);
      Paint(hdc);
      EndPaint(hwnd, &ps);
      return 0;
    }

    case WM_MOUSEMOVE: {
      if (!tracking_mouse_) {
        TRACKMOUSEEVENT tme = {};
        tme.cbSize = sizeof(TRACKMOUSEEVENT);
        tme.dwFlags = TME_LEAVE;
        tme.hwndTrack = hwnd;
        TrackMouseEvent(&tme);
        tracking_mouse_ = true;
      }
      POINT pt = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      int hit = HitTest(pt);
      if (hit != hovered_index_) {
        hovered_index_ = hit;
        InvalidateRect(hwnd, nullptr, FALSE);
      }
      SetCursor(LoadCursor(nullptr, hit >= 0 ? IDC_HAND : IDC_ARROW));
      return 0;
    }

    case WM_MOUSELEAVE: {
      tracking_mouse_ = false;
      if (hovered_index_ != -1) {
        hovered_index_ = -1;
        InvalidateRect(hwnd, nullptr, FALSE);
      }
      return 0;
    }

    case WM_LBUTTONDOWN: {
      POINT pt = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      int hit = HitTest(pt);
      pressed_index_ = hit;
      focused_index_ = -1;
      if (hit >= 0) {
        SetCapture(hwnd);
      }
      InvalidateRect(hwnd, nullptr, FALSE);
      return 0;
    }

    case WM_LBUTTONUP: {
      // Read before ReleaseCapture(), which dispatches WM_CAPTURECHANGED and
      // clears pressed_index_ synchronously.
      const int prev_pressed = pressed_index_;
      pressed_index_ = -1;
      if (GetCapture() == hwnd) {
        ReleaseCapture();
      }
      POINT pt = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      int hit = HitTest(pt);
      if (hit >= 0 && hit == prev_pressed &&
          hit < static_cast<int>(regions_.size())) {
        std::string action = regions_[hit].action;
        Hide();
        if (on_action_) {
          on_action_(action);
        }
      } else {
        InvalidateRect(hwnd, nullptr, FALSE);
      }
      return 0;
    }

    case WM_CAPTURECHANGED: {
      if (pressed_index_ != -1) {
        pressed_index_ = -1;
        InvalidateRect(hwnd, nullptr, FALSE);
      }
      return 0;
    }

    case WM_KEYDOWN: {
      if (wparam == VK_ESCAPE) {
        Hide();
        return 0;
      }
      if (!regions_.empty()) {
        const int n = static_cast<int>(regions_.size());
        if (wparam == VK_DOWN ||
            (wparam == VK_TAB && !(GetKeyState(VK_SHIFT) & 0x8000))) {
          focused_index_ = (focused_index_ + 1 + n) % n;
          InvalidateRect(hwnd, nullptr, FALSE);
          return 0;
        }
        if (wparam == VK_UP ||
            (wparam == VK_TAB && (GetKeyState(VK_SHIFT) & 0x8000))) {
          focused_index_ = focused_index_ <= 0 ? (n - 1) : (focused_index_ - 1);
          InvalidateRect(hwnd, nullptr, FALSE);
          return 0;
        }
        if ((wparam == VK_RETURN || wparam == VK_SPACE) &&
            focused_index_ >= 0 && focused_index_ < n) {
          std::string action = regions_[focused_index_].action;
          Hide();
          if (on_action_) {
            on_action_(action);
          }
          return 0;
        }
      }
      break;
    }

    case WM_ACTIVATE: {
      if (LOWORD(wparam) == WA_INACTIVE) {
        Hide();
        return 0;
      }
      break;
    }

    case WM_KILLFOCUS: {
      Hide();
      return 0;
    }
  }
  return DefWindowProcW(hwnd, msg, wparam, lparam);
}
