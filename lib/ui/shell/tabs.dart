/// 侧栏页面索引（全应用唯一来源，避免各处硬编码）。
///
/// 背景：侧栏顺序调整过（新增「探索」页插到「游戏库」之后），而主页、
/// 资源搜索、设置跳转等处原先都写着裸数字，插一项就会全线错位——表现为
/// 「点了没反应」「跳到别的页」这类很难排查的问题。这里集中定义索引，
/// 新增页面只需改这一处 + `app_shell.dart` 的路由表与侧栏列表。
///
/// 变更记录：原先「资源搜索」是独立的一项（索引 3）。它与「探索」本质都是
/// 「找游戏」，现已合并进「探索」页作为页内的「资源」模式（见
/// `ui/discover/discover_page.dart`），因此侧栏从 7 项减为 6 项，
/// 统计 / AI / 设置的索引整体前移一位。
///
/// **注意区分**：设置页**内部**的分区索引（`settingsSectionProvider` 的
/// 0..N，例如 `ai_page.dart` 里的 `jumpToSettingsSection(ref, 3)` 指
/// 「设置 → AI 分区」）与这里的页面索引完全是两套编号，不要混用。
library;

class Tabs {
  const Tabs._();

  static const home = 0;
  static const library = 1;
  static const discover = 2; // 探索（含「资源」模式：原「资源搜索」已并入）
  static const stats = 3;
  static const ai = 4;
  static const settings = 5;

  /// 页面总数（越界防御/自检用）。
  static const count = 6;
}
