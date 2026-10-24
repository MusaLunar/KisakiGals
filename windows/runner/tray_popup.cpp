#include "tray_popup.h"

#include <dwmapi.h>
#include <objidl.h>
#include <gdiplus.h>
#include <windowsx.h>

#include <algorithm>
#include <cmath>

#include "resource.h"

#ifndef DWMWA_WINDOW_CORNER_PREFERENCE
#define DWMWA_WINDOW_CORNER_PREFERENCE 33
#endif
#ifndef DWMWCP_ROUND
#define DWMWCP_ROUND 2
#endif

namespace {

constexpr const wchar_t kTrayPopupClassName[] = L"KisakiTrayPopupWindow";
bool g_class_registered = false;

// Unicode string constants (ASCII-escaped to avoid any MSVC codepage issues)
// "桌面快捷启动"
constexpr const wchar_t kStrSubtitle[] =
    L"\u684C\u9762\u5FEB\u6377\u542F\u52A8";
// "正在游玩中"
constexpr const wchar_t kStrPlayingNow[] = L"\u6B63\u5728\u6E38\u73A9\u4E2D";
// "结束会话"
constexpr const wchar_t kStrStopSession[] = L"\u7ED3\u675F\u4F1A\u8BDD";
// "最近游玩 · 点击即刻启动"
constexpr const wchar_t kStrRecentHeader[] =
    L"\u6700\u8FD1\u6E38\u73A9 \u00B7 \u70B9\u51FB\u5373\u523B\u542F\u52A8";
// "暂无最近游玩记录"
constexpr const wchar_t kStrRecentEmpty[] =
    L"\u6682\u65E0\u6700\u8FD1\u6E38\u73A9\u8BB0\u5F55";
// "运行中"
constexpr const wchar_t kStrRunning[] = L"\u8FD0\u884C\u4E2D";
// "▶ 启动"
constexpr const wchar_t kStrLaunch[] = L"\u25B6 \u542F\u52A8";
// "打开主面板"
constexpr const wchar_t kStrNavShow[] = L"\u6253\u5F00\u4E3B\u9762\u677F";
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
  wc.style = CS_HREDRAW | CS_VREDRAW | CS_DROPSHADOW;
  wc.lpfnWndProc = KisakiTrayPopup::WndProc;
  wc.hInstance = GetModuleHandle(nullptr);
  wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
  wc.hbrBackground = nullptr;
  wc.lpszClassName = kTrayPopupClassName;
  RegisterClassExW(&wc);
  g_class_registered = true;
}

void KisakiTrayPopup::RebuildLayout() {
  regions_.clear();
  const int pad = S(12);
  width_ = S(312);
  int y = pad;

  // 1. Masthead (40px)
  y += S(40);
  y += S(6);

  // 2. Running game banner (optional)
  if (!data_.running_title.empty()) {
    const int banner_h = S(46);
    RECT stop_rc = {width_ - pad - S(74), y + S(9), width_ - pad - S(8),
                    y + banner_h - S(9)};
    regions_.push_back({stop_rc, "stop_tracking", true, false});
    y += banner_h + S(10);
  }

  // 3. Section header
  y += S(22);

  // 4. Recently played 2 game cards
  if (data_.recent_games.empty()) {
    y += S(48);
  } else {
    const int count =
        static_cast<int>(std::min<size_t>(2, data_.recent_games.size()));
    const int card_h = S(58);
    for (int i = 0; i < count; ++i) {
      RECT card_rc = {pad, y, width_ - pad, y + card_h};
      regions_.push_back(
          {card_rc,
           "launch_game_" + std::to_string(data_.recent_games[i].id),
           false,
           true});
      y += card_h + S(6);
    }
  }

  y += S(6);
  y += S(10);

  // 5. 2x2 navigation grid
  const int gap = S(6);
  const int col_w = (width_ - pad * 2 - gap) / 2;
  const int nav_h = S(36);

  struct NavDef {
    const char* action;
  };
  const NavDef navs[4] = {
      {"show"},
      {"nav_library"},
      {"nav_discover"},
      {"nav_stats"},
  };

  for (int i = 0; i < 4; ++i) {
    int row = i / 2;
    int col = i % 2;
    int left = pad + col * (col_w + gap);
    int top = y + row * (nav_h + gap);
    RECT rc = {left, top, left + col_w, top + nav_h};
    regions_.push_back({rc, navs[i].action, false, false});
  }

  y += nav_h * 2 + gap + S(10);
  y += S(8);

  // 6. Footer buttons
  const int foot_h = S(34);
  RECT settings_rc = {pad, y, pad + col_w, y + foot_h};
  RECT quit_rc = {pad + col_w + gap, y, width_ - pad, y + foot_h};
  regions_.push_back({settings_rc, "nav_settings", false, false});
  regions_.push_back({quit_rc, "quit", true, false});

  y += foot_h + pad;
  height_ = y;
}

void KisakiTrayPopup::Show(const TrayPopupData& data) {
  EnsureWindowClass();
  data_ = data;
  hovered_index_ = -1;

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

    DWORD corner_pref = DWMWCP_ROUND;
    DwmSetWindowAttribute(hwnd_, DWMWA_WINDOW_CORNER_PREFERENCE, &corner_pref,
                          sizeof(corner_pref));
  }

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
  // Position to the right of the mouse cursor by default
  int x = cursor.x + S(6);
  int y = cursor.y - height_ - S(6);

  if (y < work.top + margin) {
    y = cursor.y + S(8);
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
  if (hwnd_ && IsWindowVisible(hwnd_)) {
    ShowWindow(hwnd_, SW_HIDE);
  }
  hovered_index_ = -1;
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
  Gdiplus::Bitmap buffer(width_, height_, PixelFormat32bppARGB);
  Gdiplus::Graphics g(&buffer);
  g.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
  g.SetInterpolationMode(Gdiplus::InterpolationModeHighQualityBicubic);
  g.SetTextRenderingHint(Gdiplus::TextRenderingHintClearTypeGridFit);

  const bool dark = data_.dark;

  // Shimen palette
  const Gdiplus::Color bg_color =
      dark ? Gdiplus::Color(255, 22, 21, 27)
           : Gdiplus::Color(255, 250, 247, 242);
  const Gdiplus::Color card_bg =
      dark ? Gdiplus::Color(255, 31, 30, 38)
           : Gdiplus::Color(255, 255, 255, 255);
  const Gdiplus::Color hover_bg =
      dark ? Gdiplus::Color(255, 42, 40, 52)
           : Gdiplus::Color(255, 241, 235, 225);
  const Gdiplus::Color border_color =
      dark ? Gdiplus::Color(255, 50, 48, 60)
           : Gdiplus::Color(255, 226, 219, 208);
  const Gdiplus::Color ink_color =
      dark ? Gdiplus::Color(255, 243, 239, 232)
           : Gdiplus::Color(255, 24, 23, 28);
  const Gdiplus::Color ink_soft =
      dark ? Gdiplus::Color(255, 158, 153, 168)
           : Gdiplus::Color(255, 104, 99, 112);
  const Gdiplus::Color crimson =
      dark ? Gdiplus::Color(255, 228, 78, 84)
           : Gdiplus::Color(255, 209, 59, 64);
  const Gdiplus::Color crimson_tint =
      dark ? Gdiplus::Color(48, 228, 78, 84)
           : Gdiplus::Color(28, 209, 59, 64);
  const Gdiplus::Color cyan =
      dark ? Gdiplus::Color(255, 56, 178, 146)
           : Gdiplus::Color(255, 29, 122, 95);
  const Gdiplus::Color cyan_tint =
      dark ? Gdiplus::Color(44, 56, 178, 146)
           : Gdiplus::Color(28, 29, 122, 95);

  g.Clear(bg_color);
  DrawRoundRect(
      g,
      Gdiplus::RectF(0.5f, 0.5f, static_cast<float>(width_ - 1),
                     static_cast<float>(height_ - 1)),
      SF(10.0f), border_color, 1.0f);

  Gdiplus::FontFamily font_family(L"Microsoft YaHei UI");
  Gdiplus::Font font_title(&font_family, SF(13.0f), Gdiplus::FontStyleBold,
                           Gdiplus::UnitPixel);
  Gdiplus::Font font_body_bold(&font_family, SF(12.5f), Gdiplus::FontStyleBold,
                               Gdiplus::UnitPixel);
  Gdiplus::Font font_body(&font_family, SF(12.0f), Gdiplus::FontStyleRegular,
                          Gdiplus::UnitPixel);
  Gdiplus::Font font_caption(&font_family, SF(11.0f), Gdiplus::FontStyleRegular,
                             Gdiplus::UnitPixel);
  Gdiplus::Font font_micro(&font_family, SF(10.5f), Gdiplus::FontStyleBold,
                           Gdiplus::UnitPixel);

  Gdiplus::SolidBrush ink_brush(ink_color);
  Gdiplus::SolidBrush soft_brush(ink_soft);
  Gdiplus::SolidBrush crimson_brush(crimson);
  Gdiplus::SolidBrush cyan_brush(cyan);
  Gdiplus::SolidBrush white_brush(Gdiplus::Color(255, 255, 255, 255));
  Gdiplus::Pen divider_pen(border_color, 1.0f);

  Gdiplus::StringFormat left_vcenter;
  left_vcenter.SetAlignment(Gdiplus::StringAlignmentNear);
  left_vcenter.SetLineAlignment(Gdiplus::StringAlignmentCenter);
  left_vcenter.SetTrimming(Gdiplus::StringTrimmingEllipsisCharacter);
  left_vcenter.SetFormatFlags(Gdiplus::StringFormatFlagsNoWrap);

  Gdiplus::StringFormat center_fmt;
  center_fmt.SetAlignment(Gdiplus::StringAlignmentCenter);
  center_fmt.SetLineAlignment(Gdiplus::StringAlignmentCenter);
  center_fmt.SetFormatFlags(Gdiplus::StringFormatFlagsNoWrap);

  const int pad = S(12);
  int y = pad;
  size_t region_cursor = 0;

  // 1. Masthead (App icon + KisakiGals title)
  {
    const int icon_size = S(28);
    const int icon_x = pad;
    const int icon_y = y + S(5);
    bool drew_app_icon = false;
    HICON h_icon = static_cast<HICON>(LoadImageW(
        GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON,
        icon_size, icon_size, LR_DEFAULTCOLOR));
    if (h_icon) {
      HDC buf_dc = g.GetHDC();
      if (buf_dc) {
        DrawIconEx(buf_dc, icon_x, icon_y, h_icon, icon_size, icon_size, 0,
                   nullptr, DI_NORMAL);
        g.ReleaseHDC(buf_dc);
        drew_app_icon = true;
      }
      DestroyIcon(h_icon);
    }
    if (!drew_app_icon) {
      Gdiplus::RectF icon_rc(static_cast<float>(icon_x),
                             static_cast<float>(icon_y),
                             static_cast<float>(icon_size),
                             static_cast<float>(icon_size));
      FillRoundRect(g, icon_rc, SF(6.0f), crimson);
      g.DrawString(L"K", -1, &font_body_bold, icon_rc, &center_fmt,
                   &white_brush);
    }

    Gdiplus::RectF name_rc(static_cast<float>(pad + S(36)),
                           static_cast<float>(y + S(3)), SF(165.0f), SF(18.0f));
    g.DrawString(L"KisakiGals", -1, &font_title, name_rc, &left_vcenter,
                 &ink_brush);

    Gdiplus::RectF sub_rc(static_cast<float>(pad + S(36)),
                          static_cast<float>(y + S(21)), SF(180.0f), SF(15.0f));
    g.DrawString(kStrSubtitle, -1, &font_caption, sub_rc, &left_vcenter,
                 &soft_brush);

    std::wstring ver_label =
        data_.version.empty() ? L"v1.1.0" : (L"v" + data_.version);
    Gdiplus::RectF ver_rc(static_cast<float>(width_ - pad - S(54)),
                          static_cast<float>(y + S(9)), SF(54.0f), SF(20.0f));
    FillRoundRect(g, ver_rc, SF(5.0f), crimson_tint);
    g.DrawString(ver_label.c_str(), -1, &font_micro, ver_rc, &center_fmt,
                 &crimson_brush);

    y += S(40) + S(6);
  }

  // 2. Running status banner
  if (!data_.running_title.empty() && region_cursor < regions_.size()) {
    const int banner_h = S(46);
    Gdiplus::RectF banner_rc(static_cast<float>(pad), static_cast<float>(y),
                             static_cast<float>(width_ - pad * 2),
                             static_cast<float>(banner_h));
    FillRoundRect(g, banner_rc, SF(8.0f), cyan_tint);
    DrawRoundRect(g, banner_rc, SF(8.0f), cyan, 1.0f);

    Gdiplus::RectF dot_rc(static_cast<float>(pad + S(10)),
                          static_cast<float>(y + S(19)), SF(8.0f), SF(8.0f));
    g.FillEllipse(&cyan_brush, dot_rc);

    Gdiplus::RectF label_rc(static_cast<float>(pad + S(24)),
                            static_cast<float>(y + S(6)),
                            static_cast<float>(width_ - pad * 2 - S(108)),
                            SF(16.0f));
    g.DrawString(kStrPlayingNow, -1, &font_micro, label_rc, &left_vcenter,
                 &cyan_brush);

    Gdiplus::RectF title_rc(static_cast<float>(pad + S(24)),
                            static_cast<float>(y + S(22)),
                            static_cast<float>(width_ - pad * 2 - S(108)),
                            SF(18.0f));
    g.DrawString(data_.running_title.c_str(), -1, &font_body_bold, title_rc,
                 &left_vcenter, &ink_brush);

    const int stop_idx = static_cast<int>(region_cursor++);
    Gdiplus::RectF stop_rc = ToRectF(regions_[stop_idx].rect);
    const bool stop_hover = (hovered_index_ == stop_idx);
    FillRoundRect(g, stop_rc, SF(6.0f), stop_hover ? crimson : card_bg);
    if (!stop_hover) {
      DrawRoundRect(g, stop_rc, SF(6.0f), crimson, 1.0f);
    }
    g.DrawString(kStrStopSession, -1, &font_micro, stop_rc, &center_fmt,
                 stop_hover ? &white_brush : &crimson_brush);

    y += banner_h + S(10);
  }

  // 3. Section header
  {
    Gdiplus::RectF sec_rc(static_cast<float>(pad + S(2)),
                          static_cast<float>(y),
                          static_cast<float>(width_ - pad * 2), SF(18.0f));
    g.DrawString(kStrRecentHeader, -1, &font_micro, sec_rc, &left_vcenter,
                 &soft_brush);
    y += S(22);
  }

  // 4. Recently played 2 game cards
  if (data_.recent_games.empty()) {
    Gdiplus::RectF empty_rc(static_cast<float>(pad), static_cast<float>(y),
                            static_cast<float>(width_ - pad * 2), SF(44.0f));
    FillRoundRect(g, empty_rc, SF(8.0f), card_bg);
    DrawRoundRect(g, empty_rc, SF(8.0f), border_color, 1.0f);
    g.DrawString(kStrRecentEmpty, -1, &font_caption, empty_rc, &center_fmt,
                 &soft_brush);
    y += S(48);
  } else {
    const int count =
        static_cast<int>(std::min<size_t>(2, data_.recent_games.size()));
    for (int i = 0; i < count && region_cursor < regions_.size(); ++i) {
      const int idx = static_cast<int>(region_cursor++);
      const bool hovered = (hovered_index_ == idx);
      const auto& game = data_.recent_games[i];
      Gdiplus::RectF card_rc = ToRectF(regions_[idx].rect);

      FillRoundRect(g, card_rc, SF(8.0f), hovered ? hover_bg : card_bg);
      DrawRoundRect(g, card_rc, SF(8.0f),
                    hovered ? crimson : border_color, 1.0f);

      if (hovered) {
        Gdiplus::RectF bar_rc(card_rc.X + SF(3.0f), card_rc.Y + SF(12.0f),
                              SF(3.0f), card_rc.Height - SF(24.0f));
        FillRoundRect(g, bar_rc, SF(1.5f), crimson);
      }

      // 2:3 Cover thumbnail (30x44)
      Gdiplus::RectF cov_rc(card_rc.X + SF(10.0f), card_rc.Y + SF(7.0f),
                            SF(30.0f), SF(44.0f));
      bool drew_cover = false;
      if (!game.cover_path.empty()) {
        Gdiplus::Image img(game.cover_path.c_str());
        if (img.GetLastStatus() == Gdiplus::Ok && img.GetWidth() > 0 &&
            img.GetHeight() > 0) {
          Gdiplus::GraphicsPath clip_path;
          AddRoundRect(clip_path, cov_rc, SF(4.0f));
          Gdiplus::GraphicsState state = g.Save();
          g.SetClip(&clip_path);
          g.DrawImage(&img, cov_rc);
          g.Restore(state);
          DrawRoundRect(g, cov_rc, SF(4.0f), border_color, 1.0f);
          drew_cover = true;
        }
      }
      if (!drew_cover) {
        FillRoundRect(g, cov_rc, SF(4.0f), crimson_tint);
        DrawRoundRect(g, cov_rc, SF(4.0f), border_color, 1.0f);
        g.DrawString(L"G", -1, &font_body_bold, cov_rc, &center_fmt,
                     &crimson_brush);
      }

      const float text_left = cov_rc.GetRight() + SF(10.0f);
      const float pill_w = SF(56.0f);
      const float text_w =
          card_rc.GetRight() - text_left - pill_w - SF(14.0f);

      Gdiplus::RectF title_rc(text_left, card_rc.Y + SF(9.0f), text_w,
                              SF(20.0f));
      g.DrawString(game.title.c_str(), -1, &font_body_bold, title_rc,
                   &left_vcenter, &ink_brush);

      Gdiplus::RectF sub_rc(text_left, card_rc.Y + SF(30.0f), text_w,
                            SF(17.0f));
      g.DrawString(game.subtitle.c_str(), -1, &font_caption, sub_rc,
                   &left_vcenter, game.running ? &cyan_brush : &soft_brush);

      Gdiplus::RectF badge_rc(card_rc.GetRight() - pill_w - SF(10.0f),
                              card_rc.Y + (card_rc.Height - SF(24.0f)) * 0.5f,
                              pill_w, SF(24.0f));
      if (game.running) {
        FillRoundRect(g, badge_rc, SF(6.0f), cyan_tint);
        g.DrawString(kStrRunning, -1, &font_micro, badge_rc, &center_fmt,
                     &cyan_brush);
      } else {
        FillRoundRect(g, badge_rc, SF(6.0f),
                      hovered ? crimson : crimson_tint);
        g.DrawString(kStrLaunch, -1, &font_micro, badge_rc, &center_fmt,
                     hovered ? &white_brush : &crimson_brush);
      }
    }
    y += count * (S(58) + S(6));
  }

  y += S(6);
  g.DrawLine(&divider_pen, pad, y, width_ - pad, y);
  y += S(10);

  // 5. 2x2 Navigation grid
  const wchar_t* nav_labels[4] = {
      kStrNavShow,
      kStrNavLibrary,
      kStrNavDiscover,
      kStrNavStats,
  };
  for (int i = 0; i < 4 && region_cursor < regions_.size(); ++i) {
    const int idx = static_cast<int>(region_cursor++);
    const bool hovered = (hovered_index_ == idx);
    Gdiplus::RectF rc = ToRectF(regions_[idx].rect);
    FillRoundRect(g, rc, SF(7.0f), hovered ? hover_bg : card_bg);
    DrawRoundRect(g, rc, SF(7.0f), hovered ? crimson : border_color, 1.0f);
    g.DrawString(nav_labels[i], -1, hovered ? &font_body_bold : &font_body, rc,
                 &center_fmt, hovered ? &crimson_brush : &ink_brush);
  }

  const int nav_h = S(36);
  const int gap = S(6);
  y += nav_h * 2 + gap + S(10);

  g.DrawLine(&divider_pen, pad, y, width_ - pad, y);
  y += S(8);

  // 6. Footer buttons
  if (region_cursor + 1 < regions_.size()) {
    const int set_idx = static_cast<int>(region_cursor++);
    const bool set_hover = (hovered_index_ == set_idx);
    Gdiplus::RectF set_rc = ToRectF(regions_[set_idx].rect);
    FillRoundRect(g, set_rc, SF(7.0f), set_hover ? hover_bg : card_bg);
    DrawRoundRect(g, set_rc, SF(7.0f), border_color, 1.0f);
    g.DrawString(kStrNavSettings, -1, &font_body, set_rc, &center_fmt,
                 &ink_brush);

    const int quit_idx = static_cast<int>(region_cursor++);
    const bool quit_hover = (hovered_index_ == quit_idx);
    Gdiplus::RectF quit_rc = ToRectF(regions_[quit_idx].rect);
    FillRoundRect(g, quit_rc, SF(7.0f), quit_hover ? crimson : crimson_tint);
    g.DrawString(kStrQuit, -1, &font_body_bold, quit_rc, &center_fmt,
                 quit_hover ? &white_brush : &crimson_brush);
  }

  Gdiplus::Graphics screen_g(hdc);
  screen_g.DrawImage(&buffer, 0, 0);
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

    case WM_LBUTTONUP: {
      POINT pt = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      int hit = HitTest(pt);
      if (hit >= 0 && hit < static_cast<int>(regions_.size())) {
        std::string action = regions_[hit].action;
        Hide();
        if (on_action_) {
          on_action_(action);
        }
      }
      return 0;
    }

    case WM_KEYDOWN: {
      if (wparam == VK_ESCAPE) {
        Hide();
        return 0;
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
