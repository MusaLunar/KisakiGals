/// Windows 11 风格 Fluent 2 设置中心：5 大分区与 settingsSectionProvider 双向联动。
library;

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/utils.dart' show fmtDateTime;
import '../../data/settings_store.dart';
import '../../main.dart' show applyCloseBehavior;
import '../../providers.dart';
import '../../services/ai_service.dart';
import '../../services/auto_backup_scheduler.dart';
import '../../services/autostart.dart';
import '../../services/cloud_sync.dart';
import '../../services/kungal_oauth.dart';
import '../../services/plugin_system.dart';
import '../../services/update_checker.dart';
import '../../services/upload/upload.dart';
import '../../services/window_capture.dart';
import '../fluent/fluent_dialogs.dart';
import '../fluent/fluent_icons.dart';
import '../fluent/fluent_motion.dart';
import '../fluent/fluent_notices.dart';
import '../fluent/fluent_surfaces.dart';
import '../fluent/fluent_theme.dart';
import '../library/game_actions.dart';

class _SectionMeta {
  final int index;
  final IconData icon;
  final String navLabel;
  final String heading;
  final String subtitle;

  const _SectionMeta({
    required this.index,
    required this.icon,
    required this.navLabel,
    required this.heading,
    required this.subtitle,
  });
}

const List<_SectionMeta> _kSettingsSections = [
  _SectionMeta(
    index: 0,
    icon: FluentIcons.color_20_regular,
    navLabel: '外观与个性化',
    heading: '外观与个性化',
    subtitle: '应用明暗主题、强调色与 Windows 11 窗口材质效果',
  ),
  _SectionMeta(
    index: 1,
    icon: FluentIcons.rocket_20_regular,
    navLabel: '启动与热键',
    heading: '启动与热键',
    subtitle: '启动、追踪与游玩路径',
  ),
  _SectionMeta(
    index: 2,
    icon: FluentIcons.shield_lock_20_regular,
    navLabel: '库与账号隐私',
    heading: '库与账号隐私',
    subtitle: '游戏库、刮削源、账号与隐私',
  ),
  _SectionMeta(
    index: 3,
    icon: FluentIcons.sparkle_20_regular,
    navLabel: 'AI 配置',
    heading: 'AI 服务设置',
    subtitle: 'OpenAI 兼容端点、模型与连接验证',
  ),
  _SectionMeta(
    index: 4,
    icon: FluentIcons.database_20_regular,
    navLabel: '备份与更新',
    heading: '备份与更新',
    subtitle: '数据目录、自动备份、插件扩展与版本更新',
  ),
];

/// Windows 11 风格设置中心页（支持 5 分区双向定位与 Material 过渡外壳兜底）。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final ScrollController _scrollCtrl = ScrollController();
  final List<GlobalKey> _sectionKeys =
      List<GlobalKey>.generate(_kSettingsSections.length, (_) => GlobalKey());

  late int _activeSection =
      ref.read(settingsSectionProvider).clamp(0, _kSettingsSections.length - 1);
  ProviderSubscription<int>? _sectionSub;
  bool _programmaticScroll = false;
  bool _ignoreProviderJump = false;
  int _scrollEpoch = 0;

  @override
  void initState() {
    super.initState();
    _sectionSub = ref.listenManual<int>(settingsSectionProvider, (prev, next) {
      if (_ignoreProviderJump) return;
      final clamped = next.clamp(0, _kSettingsSections.length - 1);
      if (!mounted) return;
      if (clamped != _activeSection) {
        setState(() => _activeSection = clamped);
      }
      _scrollToSection(clamped);
    });

    if (_activeSection != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToSection(_activeSection, animate: false);
      });
    }
  }

  @override
  void dispose() {
    _sectionSub?.close();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Widget _wrapFluent(BuildContext context, Widget child) {
    final hasTheme = FluentTheme.maybeOf(context) != null;
    final hasLoc = Localizations.of<FluentLocalizations>(
          context,
          FluentLocalizations,
        ) !=
        null;
    final hasOverlay = Overlay.maybeOf(context) != null;
    if (hasTheme && hasLoc && hasOverlay) return child;
    var wrapped = child;
    if (!hasOverlay) {
      wrapped = Overlay.wrap(child: wrapped);
    }
    if (!hasLoc) {
      wrapped = Localizations.override(
        context: context,
        delegates: const [FluentLocalizations.delegate],
        child: wrapped,
      );
    }
    if (!hasTheme) {
      wrapped = ensureFluentTheme(context, wrapped);
    }
    return wrapped;
  }

  Future<void> _scrollToSection(int index, {bool animate = true}) async {
    if (index < 0 || index >= _sectionKeys.length) return;
    final targetContext = _sectionKeys[index].currentContext;
    if (targetContext == null || !targetContext.mounted) return;
    final disableAnim =
        !animate || (mounted && fluentAnimationsDisabled(context));
    final epoch = ++_scrollEpoch;
    _programmaticScroll = true;
    try {
      await Scrollable.ensureVisible(
        targetContext,
        duration: disableAnim ? Duration.zero : FluentMotion.standard,
        curve: FluentMotion.enterCurve,
        alignment: 0.0,
      );
    } finally {
      if (mounted && epoch == _scrollEpoch) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && epoch == _scrollEpoch) {
            _programmaticScroll = false;
          }
        });
      }
    }
  }

  void _selectSection(int index) {
    final clamped = index.clamp(0, _kSettingsSections.length - 1);
    if (_activeSection != clamped) {
      setState(() => _activeSection = clamped);
    }
    if (ref.read(settingsSectionProvider) != clamped) {
      _ignoreProviderJump = true;
      ref.read(settingsSectionProvider.notifier).state = clamped;
      _ignoreProviderJump = false;
    }
    _scrollToSection(clamped);
  }

  bool _handleScrollUpdate(ScrollUpdateNotification notification) {
    if (_programmaticScroll || !_scrollCtrl.hasClients) return false;
    final scrollBox = _scrollCtrl.position.context.notificationContext
        ?.findRenderObject() as RenderBox?;
    if (scrollBox == null || !scrollBox.attached) return false;

    final viewportTop = scrollBox.localToGlobal(Offset.zero).dy;
    var candidate = _activeSection;
    var bestTop = double.negativeInfinity;

    for (var i = 0; i < _sectionKeys.length; i++) {
      final ctx = _sectionKeys[i].currentContext;
      if (ctx == null) continue;
      final ro = ctx.findRenderObject();
      if (ro is! RenderBox || !ro.attached) continue;
      final top = ro.localToGlobal(Offset.zero).dy - viewportTop;
      if (top <= 96 && top > bestTop) {
        bestTop = top;
        candidate = i;
      }
    }

    if (bestTop == double.negativeInfinity) {
      candidate = 0;
    }

    if (candidate != _activeSection && mounted) {
      setState(() => _activeSection = candidate);
      if (ref.read(settingsSectionProvider) != candidate) {
        _ignoreProviderJump = true;
        ref.read(settingsSectionProvider.notifier).state = candidate;
        _ignoreProviderJump = false;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return _wrapFluent(
      context,
      Builder(builder: _buildPage),
    );
  }

  Widget _buildPage(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final disableAnim = fluentAnimationsDisabled(context);
    final activeMeta = _kSettingsSections[_activeSection];

    return ScaffoldPage(
      padding: EdgeInsets.zero,
      header: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('设置', style: theme.typography.titleLarge),
                  const SizedBox(height: 2),
                  Text(
                    '${activeMeta.heading} · 更改除数据目录外实时生效',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.typography.caption?.copyWith(
                      color: theme.inactiveColor,
                    ),
                  ),
                ],
              ),
            ),
            FluentStatusPill.label(
              icon: activeMeta.icon,
              label: activeMeta.navLabel,
            ),
          ],
        ),
      ),
      content: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 820;
          final dividerColor = isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.07);

          final scrollBody = Expanded(
            child: NotificationListener<ScrollUpdateNotification>(
              onNotification: _handleScrollUpdate,
              child: SingleChildScrollView(
                controller: _scrollCtrl,
                padding: EdgeInsets.fromLTRB(
                  isWide ? 24 : 16,
                  8,
                  isWide ? 24 : 16,
                  40,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 920),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SettingsSectionBlock(
                          key: _sectionKeys[0],
                          meta: _kSettingsSections[0],
                          active: _activeSection == 0,
                          index: 0,
                          disableAnim: disableAnim,
                          child: const _AppearanceSection(),
                        ),
                        const SizedBox(height: 24),
                        _SettingsSectionBlock(
                          key: _sectionKeys[1],
                          meta: _kSettingsSections[1],
                          active: _activeSection == 1,
                          index: 1,
                          disableAnim: disableAnim,
                          child: const _StartupAndHotkeySection(),
                        ),
                        const SizedBox(height: 24),
                        _SettingsSectionBlock(
                          key: _sectionKeys[2],
                          meta: _kSettingsSections[2],
                          active: _activeSection == 2,
                          index: 2,
                          disableAnim: disableAnim,
                          child: const _LibraryAccountPrivacySection(),
                        ),
                        const SizedBox(height: 24),
                        _SettingsSectionBlock(
                          key: _sectionKeys[3],
                          meta: _kSettingsSections[3],
                          active: _activeSection == 3,
                          index: 3,
                          disableAnim: disableAnim,
                          child: const _AiSection(),
                        ),
                        const SizedBox(height: 24),
                        _SettingsSectionBlock(
                          key: _sectionKeys[4],
                          meta: _kSettingsSections[4],
                          active: _activeSection == 4,
                          index: 4,
                          disableAnim: disableAnim,
                          child: const _BackupPluginUpdateSection(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );

          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 214,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 12, 16),
                    child: _SettingsNavRail(
                      activeSection: _activeSection,
                      onSelect: _selectSection,
                    ),
                  ),
                ),
                Container(width: 1, color: dividerColor),
                scrollBody,
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SettingsPillBar(
                activeSection: _activeSection,
                onSelect: _selectSection,
              ),
              Container(height: 1, color: dividerColor),
              scrollBody,
            ],
          );
        },
      ),
    );
  }
}

// ---------- 导航与布局原语 ----------

class _SettingsNavRail extends StatelessWidget {
  final int activeSection;
  final ValueChanged<int> onSelect;

  const _SettingsNavRail({
    required this.activeSection,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final meta in _kSettingsSections)
          _NavRailItem(
            meta: meta,
            selected: activeSection == meta.index,
            accent: accent,
            isDark: isDark,
            onTap: () => onSelect(meta.index),
          ),
      ],
    );
  }
}

class _NavRailItem extends StatefulWidget {
  final _SectionMeta meta;
  final bool selected;
  final Color accent;
  final bool isDark;
  final VoidCallback onTap;

  const _NavRailItem({
    required this.meta,
    required this.selected,
    required this.accent,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_NavRailItem> createState() => _NavRailItemState();
}

class _NavRailItemState extends State<_NavRailItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final bg = widget.selected
        ? widget.accent.withValues(alpha: widget.isDark ? 0.16 : 0.10)
        : (_hovered
            ? (widget.isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.04))
            : Colors.transparent);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          key: ValueKey('settings_nav_${widget.meta.index}'),
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: FluentMotion.fast,
            curve: FluentMotion.enterCurve,
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  key: widget.selected
                      ? ValueKey('settings_section_active_${widget.meta.index}')
                      : null,
                  duration: FluentMotion.fast,
                  width: 3,
                  height: widget.selected ? 18 : 0,
                  decoration: BoxDecoration(
                    color: widget.selected ? widget.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  widget.meta.icon,
                  size: 16,
                  color: widget.selected ? widget.accent : theme.inactiveColor,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.meta.navLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.typography.body?.copyWith(
                      fontWeight:
                          widget.selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsPillBar extends StatelessWidget {
  final int activeSection;
  final ValueChanged<int> onSelect;

  const _SettingsPillBar({
    required this.activeSection,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Row(
        children: [
          for (final meta in _kSettingsSections)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ToggleButton(
                key: ValueKey('settings_nav_${meta.index}'),
                checked: activeSection == meta.index,
                onChanged: (_) => onSelect(meta.index),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (activeSection == meta.index)
                      Container(
                        key: ValueKey('settings_section_active_${meta.index}'),
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    Icon(meta.icon, size: 14),
                    const SizedBox(width: 6),
                    Text(meta.navLabel),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SettingsSectionBlock extends StatelessWidget {
  final _SectionMeta meta;
  final bool active;
  final int index;
  final bool disableAnim;
  final Widget child;

  const _SettingsSectionBlock({
    super.key,
    required this.meta,
    required this.active,
    required this.index,
    required this.disableAnim,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);
    return RepaintBoundary(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FluentSectionHeader(
            icon: meta.icon,
            title: meta.heading,
            subtitle: meta.subtitle,
            trailing: active
                ? FluentBadge(
                    text: '当前区域',
                    foreground: accent,
                    background: accent.withValues(alpha: 0.14),
                  )
                : null,
          ),
          const SizedBox(height: 10),
          child,
        ],
      ).fluentEntrance(index: index, disable: disableAnim),
    );
  }
}

class _SettingsGroupCard extends StatelessWidget {
  final String? title;
  final List<Widget> children;

  const _SettingsGroupCard({
    this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.black.withValues(alpha: 0.06);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null && title!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Text(
              title!,
              style: theme.typography.bodyStrong?.copyWith(
                color: theme.inactiveColor,
                fontSize: 12.5,
              ),
            ),
          ),
        FluentSurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    color: dividerColor,
                  ),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const _SettingRow({
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final labelBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.typography.body),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            subtitle!,
            style: theme.typography.caption?.copyWith(
              color: theme.inactiveColor,
              height: 1.45,
            ),
          ),
        ],
      ],
    );

    if (trailing == null) return labelBlock;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              labelBlock,
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerRight, child: trailing!),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: labelBlock),
            const SizedBox(width: 16),
            Flexible(
              flex: 0,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * 0.56,
                ),
                child: trailing!,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ToggleSettingRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool checked;
  final ValueChanged<bool>? onChanged;

  const _ToggleSettingRow({
    required this.title,
    this.subtitle,
    required this.checked,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _SettingRow(
      title: title,
      subtitle: subtitle,
      trailing: ToggleSwitch(
        checked: checked,
        onChanged: onChanged,
      ),
    );
  }
}

T _watchOptional<T>(WidgetRef ref, ProviderListenable<T> provider, T fallback) {
  try {
    return ref.watch(provider);
  } catch (_) {
    return fallback;
  }
}

// ---------- Section 0: 外观与个性化 ----------

class _AppearanceSection extends ConsumerStatefulWidget {
  const _AppearanceSection();

  @override
  ConsumerState<_AppearanceSection> createState() => _AppearanceSectionState();
}

class _AppearanceSectionState extends ConsumerState<_AppearanceSection> {
  ThemeModePref _fallbackTheme = ThemeModePref.system;
  AccentPreset _fallbackAccent = AccentPreset.system;
  BackdropEffectPref _fallbackBackdrop = BackdropEffectPref.mica;

  Future<void> _setTheme(ThemeModePref pref) async {
    setState(() => _fallbackTheme = pref);
    try {
      await ref.read(themeProvider.notifier).set(pref);
    } catch (_) {}
  }

  Future<void> _setAccent(AccentPreset preset) async {
    setState(() => _fallbackAccent = preset);
    try {
      await ref.read(accentPresetProvider.notifier).set(preset);
    } catch (_) {}
  }

  Future<void> _setBackdrop(BackdropEffectPref effect) async {
    setState(() => _fallbackBackdrop = effect);
    try {
      await ref.read(backdropEffectProvider.notifier).set(effect);
    } catch (_) {}
  }

  static String _themeLabel(ThemeModePref pref) => switch (pref) {
        ThemeModePref.system => '跟随系统',
        ThemeModePref.light => '浅色模式',
        ThemeModePref.dark => '深色模式',
      };

  @override
  Widget build(BuildContext context) {
    final themePref = _watchOptional(ref, themeProvider, _fallbackTheme);
    final accentPref =
        _watchOptional(ref, accentPresetProvider, _fallbackAccent);
    final backdropPref =
        _watchOptional(ref, backdropEffectProvider, _fallbackBackdrop);
    final systemAccent =
        _watchOptional(ref, systemAccentColorProvider, kDefaultWin11Azure);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingsGroupCard(
          title: '主题与材质',
          children: [
            _SettingRow(
              title: '应用主题模式',
              subtitle: '选择跟随 Windows 系统明暗切换或固定浅色/深色',
              trailing: SizedBox(
                width: 190,
                child: ComboBox<ThemeModePref>(
                  key: const ValueKey('settings_theme_combo'),
                  isExpanded: true,
                  value: themePref,
                  items: [
                    for (final pref in ThemeModePref.values)
                      ComboBoxItem<ThemeModePref>(
                        value: pref,
                        child: Text(_themeLabel(pref)),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) _setTheme(v);
                  },
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SettingRow(
                  title: '强调色预设',
                  subtitle: '选择跟随系统 DWM 强调色，或切换预置主题色板',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final preset in AccentPreset.values)
                      _AccentSwatchCard(
                        key: ValueKey('settings_accent_${preset.id}'),
                        preset: preset,
                        color: resolveAccentBaseColor(preset, systemAccent),
                        selected: accentPref == preset,
                        onTap: () => _setAccent(preset),
                      ),
                  ],
                ),
              ],
            ),
            _SettingRow(
              title: '窗口材质效果',
              subtitle: 'Windows 11 DWM 背景合成材质（Mica / Tabbed / Acrylic / Solid）',
              trailing: SizedBox(
                width: 190,
                child: ComboBox<BackdropEffectPref>(
                  key: const ValueKey('settings_backdrop_combo'),
                  isExpanded: true,
                  value: backdropPref,
                  items: [
                    for (final effect in BackdropEffectPref.values)
                      ComboBoxItem<BackdropEffectPref>(
                        value: effect,
                        child: Text(effect.label),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) _setBackdrop(v);
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AccentSwatchCard extends StatelessWidget {
  final AccentPreset preset;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _AccentSwatchCard({
    super.key,
    required this.preset,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = selected
        ? color
        : (isDark
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.black.withValues(alpha: 0.10));

    return SizedBox(
      width: 148,
      child: FluentSurfaceCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        backgroundColor: selected
            ? color.withValues(alpha: isDark ? 0.18 : 0.10)
            : null,
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: borderColor,
                  width: selected ? 2 : 1,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                preset.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.typography.body?.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (selected)
              Icon(
                FluentIcons.checkmark_circle_16_filled,
                size: 16,
                color: color,
              ),
          ],
        ),
      ),
    );
  }
}

// ---------- Section 1: 启动与热键 ----------

class _StartupAndHotkeySection extends ConsumerStatefulWidget {
  const _StartupAndHotkeySection();

  @override
  ConsumerState<_StartupAndHotkeySection> createState() =>
      _StartupAndHotkeySectionState();
}

class _StartupAndHotkeySectionState
    extends ConsumerState<_StartupAndHotkeySection> {
  final TextEditingController _leController = TextEditingController();
  final FocusNode _hotkeyFocusNode = FocusNode();

  bool _autostart = false;
  String _afterLaunch = 'none';
  bool _focusOnGameExit = true;
  String _closeBehavior = 'exit';
  String _trackingMode = 'foreground';
  String _screenshotHotkey = 'F12';
  String _lePath = '';
  bool _leValid = false;
  bool _recordingHotkey = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _leController.dispose();
    _hotkeyFocusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final services = tryAppServices();
    if (services == null) return;
    final s = services.settings;
    final autostart = await services.autostart.isEnabled();
    final after = await s.getString(SettingsStore.kAfterLaunch, 'none');
    final focusOnExit =
        await s.getBool(SettingsStore.kFocusOnGameExit, def: true);
    final close = await s.getString(SettingsStore.kCloseBehavior, 'exit');
    final tracking = await s.getString(SettingsStore.kTrackingMode, 'foreground');
    final hotkey = await s.getString(SettingsStore.kScreenshotHotkey, 'F12');
    final lePath = await s.getString(SettingsStore.kLePath, '');
    if (!mounted) return;
    setState(() {
      _autostart = autostart;
      _afterLaunch = after;
      _focusOnGameExit = focusOnExit;
      _closeBehavior = close;
      _trackingMode = tracking;
      _screenshotHotkey = hotkey;
      _lePath = lePath;
      _leValid = lePath.isNotEmpty && File(lePath).existsSync();
      _leController.text = lePath;
    });
  }

  Future<void> _applyHotkey(String key) async {
    final services = tryAppServices();
    await services?.settings.setString(SettingsStore.kScreenshotHotkey, key);
    services?.tracker.reloadCaptureHotkey(key);
    if (!mounted) return;
    setState(() {
      _screenshotHotkey = key;
      _recordingHotkey = false;
    });
    showNotice(key == 'disabled' ? '已关闭游玩路径截图热键' : '已设置截图热键：$key');
  }

  String? _canonicalHotkeyFromEvent(LogicalKeyboardKey key) {
    final map = <LogicalKeyboardKey, String>{
      LogicalKeyboardKey.f1: 'F1',
      LogicalKeyboardKey.f2: 'F2',
      LogicalKeyboardKey.f3: 'F3',
      LogicalKeyboardKey.f4: 'F4',
      LogicalKeyboardKey.f5: 'F5',
      LogicalKeyboardKey.f6: 'F6',
      LogicalKeyboardKey.f7: 'F7',
      LogicalKeyboardKey.f8: 'F8',
      LogicalKeyboardKey.f9: 'F9',
      LogicalKeyboardKey.f10: 'F10',
      LogicalKeyboardKey.f11: 'F11',
      LogicalKeyboardKey.f12: 'F12',
      LogicalKeyboardKey.printScreen: 'PrintScreen',
      LogicalKeyboardKey.scrollLock: 'ScrollLock',
      LogicalKeyboardKey.pause: 'Pause',
      LogicalKeyboardKey.insert: 'Insert',
    };
    return map[key];
  }

  @override
  Widget build(BuildContext context) {
    final hotkeyItems = <({String id, String label})>[
      ...WindowCaptureService.hotkeyChoices,
      if (!WindowCaptureService.hotkeyChoices
          .any((c) => c.id == _screenshotHotkey))
        (id: _screenshotHotkey, label: _screenshotHotkey),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingsGroupCard(
          title: '启动与窗口行为',
          children: [
            _ToggleSettingRow(
              title: '开机自启',
              subtitle: '登录 Windows 后自动启动 KisakiGals',
              checked: _autostart,
              onChanged: (v) async {
                await tryAppServices()?.autostart.setEnabled(v);
                if (!mounted) return;
                setState(() => _autostart = v);
              },
            ),
            _SettingRow(
              title: '启动游戏后',
              subtitle: '游戏开始运行时主窗口的行为（最小化到托盘不会占用任务栏）',
              trailing: SizedBox(
                width: 190,
                child: ComboBox<String>(
                  isExpanded: true,
                  value: _afterLaunch == 'minimize' ? 'minimize' : 'none',
                  items: const [
                    ComboBoxItem(value: 'none', child: Text('保持前台')),
                    ComboBoxItem(value: 'minimize', child: Text('最小化到托盘')),
                  ],
                  onChanged: (v) async {
                    if (v == null) return;
                    await tryAppServices()
                        ?.settings
                        .setString(SettingsStore.kAfterLaunch, v);
                    if (!mounted) return;
                    setState(() => _afterLaunch = v);
                  },
                ),
              ),
            ),
            _SettingRow(
              title: '关闭应用时',
              subtitle: '托盘图标始终存在，可随时恢复窗口；此项决定点 × 时退出或隐藏',
              trailing: SizedBox(
                width: 190,
                child: ComboBox<String>(
                  isExpanded: true,
                  value: _closeBehavior == 'tray' ? 'tray' : 'exit',
                  items: const [
                    ComboBoxItem(value: 'exit', child: Text('直接关闭')),
                    ComboBoxItem(value: 'tray', child: Text('最小化到托盘')),
                  ],
                  onChanged: (v) async {
                    if (v == null) return;
                    final services = tryAppServices();
                    await services?.settings
                        .setString(SettingsStore.kCloseBehavior, v);
                    if (!mounted) return;
                    setState(() => _closeBehavior = v);
                    if (services != null) {
                      await applyCloseBehavior();
                    }
                  },
                ),
              ),
            ),
            _ToggleSettingRow(
              title: '游戏退出后恢复前台',
              subtitle: '游戏进程退出或终止后，主程序自动获取焦点并恢复前台显示',
              checked: _focusOnGameExit,
              onChanged: (v) async {
                await tryAppServices()
                    ?.settings
                    .setBool(SettingsStore.kFocusOnGameExit, v);
                if (!mounted) return;
                setState(() => _focusOnGameExit = v);
              },
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SettingsGroupCard(
          title: '转区启动（Locale Emulator）',
          children: [
            _SettingRow(
              title: 'LEProc.exe 路径',
              subtitle: _lePath.isEmpty
                  ? '未配置。日文原版游戏可在「编辑信息 → 启动与存档」中开启转区启动以避免乱码'
                  : _lePath,
              trailing: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FluentStatusPill.label(
                        label: _lePath.isEmpty
                            ? '未配置'
                            : (_leValid ? '路径有效' : '路径无效'),
                        icon: _lePath.isEmpty
                            ? FluentIcons.info_16_regular
                            : (_leValid
                                ? FluentIcons.checkmark_circle_16_regular
                                : FluentIcons.error_circle_16_regular),
                        color: _lePath.isEmpty
                            ? null
                            : (_leValid
                                ? const Color(0xFF107C10)
                                : const Color(0xFFD13438)),
                      ),
                      const SizedBox(width: 8),
                      Button(
                        onPressed: () async {
                          final r = await FilePicker.platform.pickFiles(
                            type: FileType.any,
                            dialogTitle: '选择 Locale Emulator 的 LEProc.exe',
                          );
                          final path = r?.files.single.path;
                          if (path == null || path.isEmpty) return;
                          await tryAppServices()
                              ?.settings
                              .setString(SettingsStore.kLePath, path);
                          if (!mounted) return;
                          setState(() {
                            _lePath = path;
                            _leValid = File(path).existsSync();
                            _leController.text = path;
                          });
                          showNotice('已保存 Locale Emulator 路径');
                        },
                        child: const Text('浏览…'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 280,
                    child: TextBox(
                      controller: _leController,
                      placeholder: r'例：D:\LocaleEmulator\LEProc.exe',
                      onChanged: (v) async {
                        final trimmed = v.trim();
                        setState(() {
                          _lePath = trimmed;
                          _leValid =
                              trimmed.isNotEmpty && File(trimmed).existsSync();
                        });
                        await tryAppServices()
                            ?.settings
                            .setString(SettingsStore.kLePath, trimmed);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SettingsGroupCard(
          title: '时长追踪与游玩路径截图',
          children: [
            _SettingRow(
              title: '时间记录方式',
              subtitle: '仅前台：只有游戏窗口在前台时计时；挂机即计时：进程存活即计时',
              trailing: SizedBox(
                width: 190,
                child: ComboBox<String>(
                  isExpanded: true,
                  value: _trackingMode == 'elapsed' ? 'elapsed' : 'foreground',
                  items: const [
                    ComboBoxItem(value: 'foreground', child: Text('仅前台计时')),
                    ComboBoxItem(value: 'elapsed', child: Text('挂机即计时')),
                  ],
                  onChanged: (v) async {
                    if (v == null) return;
                    await tryAppServices()
                        ?.settings
                        .setString(SettingsStore.kTrackingMode, v);
                    if (!mounted) return;
                    setState(() => _trackingMode = v);
                  },
                ),
              ),
            ),
            KeyboardListener(
              focusNode: _hotkeyFocusNode,
              onKeyEvent: (event) {
                if (!_recordingHotkey || event is! KeyDownEvent) return;
                if (event.logicalKey == LogicalKeyboardKey.escape) {
                  setState(() => _recordingHotkey = false);
                  return;
                }
                final mapped = _canonicalHotkeyFromEvent(event.logicalKey);
                if (mapped == null) {
                  showNotice(
                    '请按 F1-F12、PrintScreen、ScrollLock、Pause 或 Insert',
                    error: true,
                  );
                  return;
                }
                _applyHotkey(mapped);
              },
              child: _SettingRow(
                title: '游玩路径截图热键',
                subtitle: _recordingHotkey
                    ? '正在监听按键：请按下快捷键（F1-F12 / PrtSc / Insert，Esc 取消）'
                    : '游戏运行时按下快捷键截取游戏窗口并写入「游玩路径」',
                trailing: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 150,
                      child: ComboBox<String>(
                        key: const ValueKey('settings_hotkey_combo'),
                        isExpanded: true,
                        value: _screenshotHotkey,
                        items: [
                          for (final c in hotkeyItems)
                            ComboBoxItem<String>(
                              value: c.id,
                              child: Text(c.label),
                            ),
                        ],
                        onChanged: (v) {
                          if (v != null) _applyHotkey(v);
                        },
                      ),
                    ),
                    _recordingHotkey
                        ? FilledButton(
                            key: const ValueKey('settings_hotkey_record_btn'),
                            onPressed: () =>
                                setState(() => _recordingHotkey = false),
                            child: const Text('取消录制'),
                          )
                        : Button(
                            key: const ValueKey('settings_hotkey_record_btn'),
                            onPressed: () {
                              setState(() => _recordingHotkey = true);
                              _hotkeyFocusNode.requestFocus();
                            },
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(FluentIcons.keyboard_16_regular, size: 15),
                                SizedBox(width: 6),
                                Text('录制快捷键'),
                              ],
                            ),
                          ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------- Section 2: 库与账号隐私 ----------

const Map<String, String> _kTokenUrls = {
  KisakiSources.bangumi: 'https://next.bgm.tv/demo/access-token/create',
  KisakiSources.vndb: 'https://vndb.org/u/tokens',
  KisakiSources.hikarinagi: 'https://www.hikarinagi.org/person/settings',
};

const Map<String, String> _kTokenHints = {
  KisakiSources.bangumi: '登录后创建 Access Token（勾选 collections 权限）',
  KisakiSources.vndb: '用户面板 → API Tokens（同步需 list 权限，上传需 listwrite）',
  KisakiSources.hikarinagi: '登录后在个人设置中生成 Access Token',
};

class _LibraryAccountPrivacySection extends ConsumerStatefulWidget {
  const _LibraryAccountPrivacySection();

  @override
  ConsumerState<_LibraryAccountPrivacySection> createState() =>
      _LibraryAccountPrivacySectionState();
}

class _LibraryAccountPrivacySectionState
    extends ConsumerState<_LibraryAccountPrivacySection> {
  final TextEditingController _searchGalController = TextEditingController();
  final TextEditingController _proxyController = TextEditingController();
  final Map<String, TextEditingController> _tokens = {
    KisakiSources.bangumi: TextEditingController(),
    KisakiSources.vndb: TextEditingController(),
    KisakiSources.hikarinagi: TextEditingController(),
  };

  List<String> _libraryRoots = [];
  List<String> _enabledSources = List<String>.from(KisakiSources.defaultEnabled);
  final Map<String, bool> _testingSource = {};
  final Map<String, String> _accountStatus = {};
  final Set<String> _syncing = {};
  KunOAuthSession? _kunSession;
  bool _kunLoggingIn = false;

  static final List<String> _allSourceIds = {
    ...KisakiSources.defaultEnabled,
    KisakiSources.dlsite,
  }.toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchGalController.dispose();
    _proxyController.dispose();
    for (final c in _tokens.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final services = tryAppServices();
    if (services == null) return;
    final s = services.settings;
    final roots = await services.relocator.roots();
    final searchGal = await s.getString(SettingsStore.kSearchGalApi, '');
    final proxy = await s.getString('sources.proxy', '');
    final enabled = await s.getStringList(
      SettingsStore.kEnabledSources,
      KisakiSources.defaultEnabled,
    );
    final nsfwMode = await s.getString(SettingsStore.kNsfwMode, 'blur');
    final nsfwBlur = await s.getDouble('nsfw.blur', 12);
    final bgBlur = await s.getDouble('detail.bg_blur', 14);

    for (final platform in _tokens.keys) {
      final token = await services.accounts.token(platform);
      if (token != null) _tokens[platform]!.text = token;
      final info = await services.accounts.info(platform);
      if (info['status'] != null) {
        _accountStatus[platform] = '${info['status']}';
      }
    }
    final kunToken = await services.accounts.token(KisakiSources.kun);
    final kunInfo = await services.accounts.info(KisakiSources.kun);
    _kunSession = KunOAuthSession.fromStore(kunToken, kunInfo);
    if (kunInfo['status'] != null) {
      _accountStatus[KisakiSources.kun] = '${kunInfo['status']}';
    }
    _kunLoggingIn = KunOAuthService.instance.isLoggingIn;

    if (!mounted) return;
    ref.read(nsfwModeProvider.notifier).state = nsfwMode;
    ref.read(nsfwBlurProvider.notifier).state = nsfwBlur;
    ref.read(detailBgBlurProvider.notifier).state = bgBlur;
    setState(() {
      _libraryRoots = roots;
      _searchGalController.text = searchGal;
      _proxyController.text = proxy;
      _enabledSources = enabled;
    });
  }

  Future<void> _saveLibraryRoots(List<String> next) async {
    setState(() => _libraryRoots = next);
    await tryAppServices()
        ?.settings
        .setString(SettingsStore.kLibraryRoots, jsonEncode(next));
  }

  Future<void> _addLibraryRoot() async {
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择游戏库根目录',
    );
    if (!mounted) return;
    if (dir == null || dir.trim().isEmpty) return;
    final trimmed = dir.trim();
    if (_libraryRoots.contains(trimmed)) {
      showNotice('该目录已在游戏库根目录列表中');
      return;
    }
    await _saveLibraryRoots([..._libraryRoots, trimmed]);
    if (!mounted) return;
    showNotice('已添加游戏库根目录');
  }

  Future<void> _saveEnabledSources(List<String> next) async {
    setState(() => _enabledSources = next);
    await tryAppServices()
        ?.settings
        .setStringList(SettingsStore.kEnabledSources, next);
  }

  Future<void> _loginKunOAuth() async {
    final services = tryAppServices();
    if (services == null) {
      showNotice('应用服务未初始化，无法发起 OAuth 授权', error: true);
      return;
    }
    setState(() {
      _kunLoggingIn = true;
      _accountStatus[KisakiSources.kun] =
          '已在浏览器打开鲲Gal (NextMoe) 授权页，请完成登录…';
    });
    final res = await KunOAuthService.instance.login(
      proxy: services.fetcher.proxy,
    );
    if (!mounted) return;
    final kunToken = await services.accounts.token(KisakiSources.kun);
    final kunInfo = await services.accounts.info(KisakiSources.kun);
    if (!mounted) return;
    setState(() {
      _kunLoggingIn = false;
      _kunSession = res.session ?? KunOAuthSession.fromStore(kunToken, kunInfo);
      _accountStatus[KisakiSources.kun] =
          (kunInfo['status'] ?? res.message).toString();
    });
    showNotice(res.message, error: !res.ok);
  }

  Future<void> _cancelKunOAuth() async {
    await KunOAuthService.instance.cancelLogin();
    if (!mounted) return;
    setState(() {
      _kunLoggingIn = false;
      _accountStatus[KisakiSources.kun] = '已取消 OAuth 授权等待';
    });
  }

  Future<void> _logoutKunOAuth() async {
    if (tryAppServices() != null) {
      await KunOAuthService.instance.logout();
    }
    if (!mounted) return;
    setState(() {
      _kunSession = null;
      _accountStatus[KisakiSources.kun] = '已退出鲲Gal账号';
    });
    showNotice('已退出鲲Gal账号');
  }

  Future<void> _syncPlatform(String platform) async {
    final services = tryAppServices();
    if (services == null) {
      showNotice('应用服务未初始化，无法同步云端记录', error: true);
      return;
    }
    String token = '';
    if (platform == KisakiSources.kun) {
      token = (await KunOAuthService.instance.validAccessToken()) ??
          (_kunSession?.accessToken ?? '');
      if (token.isEmpty) {
        if (!mounted) return;
        setState(() => _accountStatus[platform] = '请先点击「OAuth 浏览器登录」授权鲲Gal账号');
        return;
      }
    } else {
      token = _tokens[platform]!.text.trim();
      if (token.isEmpty) {
        setState(() => _accountStatus[platform] = '请先填入 Token');
        return;
      }
    }
    setState(() => _syncing.add(platform));
    try {
      final index = await services.repo.sourceIndex();
      final svc = CloudSyncService(proxy: services.fetcher.proxy);
      final r = await svc.sync(
        platform: platform,
        token: token,
        resolve: (sid) {
          var key = sid;
          if (platform == KisakiSources.vndb && key.startsWith('v')) {
            key = key.substring(1);
          }
          return index['$platform:$key'] ?? index['$platform:$sid'];
        },
        onSave: (g, _) => services.repo.updateGame(g),
      );
      ref.read(libraryVersionProvider.notifier).state++;
      final at = DateTime.now();
      final prevExtra = await services.accounts.info(platform);
      await services.accounts.setToken(platform, token, extra: {
        ...prevExtra,
        'status': r.ok ? '上次同步 ${fmtDateTime(at)}' : r.message,
        'last_sync': at.toIso8601String(),
      });
      if (!mounted) return;
      setState(() {
        _accountStatus[platform] =
            r.ok ? '上次同步 ${fmtDateTime(at)} · ${r.message}' : r.message;
      });
      showNotice(r.message, error: !r.ok);
    } finally {
      if (mounted) setState(() => _syncing.remove(platform));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final services = tryAppServices();
    final nsfwMode = ref.watch(nsfwModeProvider);
    final nsfwBlur = ref.watch(nsfwBlurProvider);
    final bgBlur = ref.watch(detailBgBlurProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingsGroupCard(
          title: '游戏库路径与聚合接口',
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SettingRow(
                  title: '游戏库根目录',
                  subtitle: '换机或迁移磁盘时自动在这些目录下重定位缺失的游戏路径',
                  trailing: Button(
                    onPressed: _addLibraryRoot,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(FluentIcons.folder_add_16_regular, size: 15),
                        SizedBox(width: 6),
                        Text('添加目录…'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (_libraryRoots.isEmpty)
                  Text(
                    '尚未记录游戏库根目录',
                    style: theme.typography.caption?.copyWith(
                      color: theme.inactiveColor,
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final root in _libraryRoots)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FluentBadge(
                              icon: FluentIcons.folder_16_regular,
                              text: root,
                              onTap: null,
                            ),
                            const SizedBox(width: 2),
                            Tooltip(
                              message: '移除根目录',
                              child: IconButton(
                                icon: const Icon(
                                  FluentIcons.delete_16_regular,
                                  size: 14,
                                ),
                                onPressed: () {
                                  final next = _libraryRoots
                                      .where((r) => r != root)
                                      .toList();
                                  _saveLibraryRoots(next);
                                },
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
              ],
            ),
            _SettingRow(
              title: 'SearchGal 兼容聚合接口',
              subtitle: '留空时仅使用内置源；填入自建接口地址可聚合更多资源站点',
              trailing: SizedBox(
                width: 280,
                child: TextBox(
                  controller: _searchGalController,
                  placeholder: 'https://your-app.workers.dev/gal',
                  onChanged: (v) => tryAppServices()
                      ?.settings
                      .setString(SettingsStore.kSearchGalApi, v.trim()),
                ),
              ),
            ),
            _SettingRow(
              title: '网络代理地址',
              subtitle:
                  '留空自动检测系统代理（当前：${services?.fetcher.proxy ?? '直连'}）',
              trailing: SizedBox(
                width: 280,
                child: Row(
                  children: [
                    Expanded(
                      child: TextBox(
                        controller: _proxyController,
                        placeholder: 'http://127.0.0.1:7890',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Button(
                      onPressed: () async {
                        final proxy = _proxyController.text.trim();
                        final s = tryAppServices();
                        await s?.settings.setString('sources.proxy', proxy);
                        await s?.fetcher.init(appProxy: proxy);
                        if (!mounted) return;
                        showNotice('代理设置已保存并重新加载');
                      },
                      child: const Text('保存'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SettingsGroupCard(
          title: '元数据源（刮削时并发查询）',
          children: [
            for (final id in _allSourceIds)
              _SettingRow(
                title: KisakiSources.labels[id] ?? id,
                subtitle: id == KisakiSources.cngal ? '公开 API 不太稳定，按需启用' : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_testingSource[id] == true)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: ProgressRing(strokeWidth: 2),
                      )
                    else
                      Button(
                        onPressed: () async {
                          final s = tryAppServices();
                          if (s == null) {
                            showNotice('应用服务未初始化，无法测试数据源', error: true);
                            return;
                          }
                          setState(() => _testingSource[id] = true);
                          final ok = await s.fetcher.testSource(id);
                          if (!mounted) return;
                          showNotice(
                            '${KisakiSources.labels[id]}：${ok ? '连接正常' : '连接失败'}',
                            error: !ok,
                          );
                          setState(() => _testingSource[id] = false);
                        },
                        child: const Text('测试'),
                      ),
                    const SizedBox(width: 10),
                    ToggleSwitch(
                      checked: _enabledSources.contains(id),
                      onChanged: (v) {
                        final next = [..._enabledSources];
                        if (v) {
                          if (!next.contains(id)) next.add(id);
                        } else {
                          next.remove(id);
                        }
                        _saveEnabledSources(next);
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _SettingsGroupCard(
          title: '账号与云端记录同步',
          children: [
            _KunOAuthCardRow(
              session: _kunSession,
              status: _accountStatus[KisakiSources.kun],
              loggingIn: _kunLoggingIn,
              syncing: _syncing.contains(KisakiSources.kun),
              onLogin: _loginKunOAuth,
              onCancelLogin: _cancelKunOAuth,
              onLogout: _logoutKunOAuth,
              onStatus: (msg) {
                if (!mounted) return;
                setState(() => _accountStatus[KisakiSources.kun] = msg);
              },
              onSync: () => _syncPlatform(KisakiSources.kun),
            ),
            for (final platform in _tokens.keys)
              _TokenAccountRow(
                platform: platform,
                controller: _tokens[platform]!,
                status: _accountStatus[platform],
                syncing: _syncing.contains(platform),
                onStatus: (msg) {
                  if (!mounted) return;
                  setState(() => _accountStatus[platform] = msg);
                },
                onSync: () => _syncPlatform(platform),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _SettingsGroupCard(
          title: 'NSFW 封面与背景模糊隐私',
          children: [
            _SettingRow(
              title: 'R-18 封面处理模式',
              subtitle: '在列表、详情与百科页中对 NSFW 封面应用隐私遮罩',
              trailing: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ToggleButton(
                    key: const ValueKey('settings_nsfw_blur'),
                    checked: nsfwMode == 'blur',
                    onChanged: (_) async {
                      ref.read(nsfwModeProvider.notifier).state = 'blur';
                      await tryAppServices()
                          ?.settings
                          .setString(SettingsStore.kNsfwMode, 'blur');
                    },
                    child: const Text('模糊'),
                  ),
                  ToggleButton(
                    key: const ValueKey('settings_nsfw_placeholder'),
                    checked: nsfwMode == 'placeholder',
                    onChanged: (_) async {
                      ref.read(nsfwModeProvider.notifier).state = 'placeholder';
                      await tryAppServices()
                          ?.settings
                          .setString(SettingsStore.kNsfwMode, 'placeholder');
                    },
                    child: const Text('占位图'),
                  ),
                  ToggleButton(
                    key: const ValueKey('settings_nsfw_show'),
                    checked: nsfwMode == 'show',
                    onChanged: (_) async {
                      ref.read(nsfwModeProvider.notifier).state = 'show';
                      await tryAppServices()
                          ?.settings
                          .setString(SettingsStore.kNsfwMode, 'show');
                    },
                    child: const Text('直接显示'),
                  ),
                ],
              ),
            ),
            if (nsfwMode == 'blur')
              _SettingRow(
                title: 'NSFW 模糊强度',
                subtitle: '当前高斯模糊半径：${nsfwBlur.round()} px',
                trailing: SizedBox(
                  width: 220,
                  child: Slider(
                    key: const ValueKey('settings_nsfw_blur_slider'),
                    value: nsfwBlur.clamp(0, 20),
                    min: 0,
                    max: 20,
                    divisions: 20,
                    label: '${nsfwBlur.round()}',
                    onChanged: (v) {
                      ref.read(nsfwBlurProvider.notifier).state = v;
                    },
                    onChangeEnd: (v) =>
                        tryAppServices()?.settings.setDouble('nsfw.blur', v),
                  ),
                ),
              ),
            _SettingRow(
              title: '详情页背景模糊度',
              subtitle: '作品详情页背景氛围图的模糊强度（${bgBlur.round()} px，0 = 不模糊）',
              trailing: SizedBox(
                width: 220,
                child: Slider(
                  key: const ValueKey('settings_detail_bg_blur_slider'),
                  value: bgBlur.clamp(0, 20),
                  min: 0,
                  max: 20,
                  divisions: 20,
                  label: '${bgBlur.round()}',
                  onChanged: (v) {
                    ref.read(detailBgBlurProvider.notifier).state = v;
                  },
                  onChangeEnd: (v) =>
                      tryAppServices()?.settings.setDouble('detail.bg_blur', v),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _KunOAuthCardRow extends StatelessWidget {
  final KunOAuthSession? session;
  final String? status;
  final bool loggingIn;
  final bool syncing;
  final VoidCallback onLogin;
  final VoidCallback onCancelLogin;
  final VoidCallback onLogout;
  final ValueChanged<String> onStatus;
  final VoidCallback onSync;

  const _KunOAuthCardRow({
    required this.session,
    required this.status,
    required this.loggingIn,
    required this.syncing,
    required this.onLogin,
    required this.onCancelLogin,
    required this.onLogout,
    required this.onStatus,
    required this.onSync,
  });

  @override
  Widget build(BuildContext context) {
    final loggedIn = session != null && session!.accessToken.isNotEmpty;
    final defaultSubtitle = loggedIn
        ? '已授权：${session!.name.isNotEmpty ? session!.name : (session!.userId.isNotEmpty ? "UID ${session!.userId}" : "鲲Gal用户")}'
        : '通过浏览器一键完成 鲲Gal (NextMoe) OAuth 2.0 + PKCE 登录并自动刷新令牌';

    return _SettingRow(
      title: '鲲Galgame (NextMoe OAuth)',
      subtitle: status ?? defaultSubtitle,
      trailing: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.end,
        children: [
          FluentStatusPill.label(
            label: loggingIn ? '等待授权' : (loggedIn ? '已授权' : '未登录'),
            icon: loggedIn
                ? FluentIcons.checkmark_circle_16_regular
                : FluentIcons.person_16_regular,
            color: loggedIn ? const Color(0xFF107C10) : null,
          ),
          if (loggingIn) ...[
            const SizedBox(
              width: 16,
              height: 16,
              child: ProgressRing(strokeWidth: 2),
            ),
            Button(
              onPressed: onCancelLogin,
              child: const Text('取消等待'),
            ),
          ] else if (!loggedIn) ...[
            FilledButton(
              onPressed: onLogin,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FluentIcons.globe_16_regular, size: 15),
                  SizedBox(width: 6),
                  Text('OAuth 浏览器登录'),
                ],
              ),
            ),
          ] else ...[
            Button(
              onPressed: () async {
                final services = tryAppServices();
                if (services == null) {
                  showNotice('应用服务未初始化', error: true);
                  return;
                }
                onStatus('正在校验鲲Gal令牌…');
                final token = await KunOAuthService.instance.validAccessToken() ??
                    session!.accessToken;
                final uploader = ReviewUploader(proxy: services.fetcher.proxy);
                final r = await uploader.testAccount(KisakiSources.kun, token);
                onStatus(r.message);
                showNotice(r.message, error: !r.ok);
              },
              child: const Text('校验'),
            ),
            Button(onPressed: onLogin, child: const Text('重新授权')),
            Button(onPressed: onLogout, child: const Text('退出')),
            if (syncing)
              const SizedBox(
                width: 16,
                height: 16,
                child: ProgressRing(strokeWidth: 2),
              )
            else
              FilledButton(
                onPressed: onSync,
                child: const Text('同步云端记录'),
              ),
          ],
        ],
      ),
    );
  }
}

class _TokenAccountRow extends StatelessWidget {
  final String platform;
  final TextEditingController controller;
  final String? status;
  final bool syncing;
  final ValueChanged<String> onStatus;
  final VoidCallback onSync;

  const _TokenAccountRow({
    required this.platform,
    required this.controller,
    required this.status,
    required this.syncing,
    required this.onStatus,
    required this.onSync,
  });

  @override
  Widget build(BuildContext context) {
    return _SettingRow(
      title: KisakiSources.labels[platform] ?? platform,
      subtitle: status ?? _kTokenHints[platform],
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 210,
                child: PasswordBox(
                  controller: controller,
                  placeholder: '粘贴 Access Token',
                  revealMode: PasswordRevealMode.peek,
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: '获取 Token（打开浏览器）',
                child: IconButton(
                  icon: const Icon(FluentIcons.open_16_regular, size: 16),
                  onPressed: () async {
                    final url =
                        Uri.parse(_kTokenUrls[platform] ?? 'https://example.com');
                    if (!await launchUrl(url,
                        mode: LaunchMode.externalApplication)) {
                      onStatus('无法打开浏览器，请手动访问：$url');
                    }
                  },
                ),
              ),
              Button(
                onPressed: () async {
                  final token = controller.text.trim();
                  if (token.isEmpty) {
                    onStatus('请先填入 Token');
                    return;
                  }
                  final services = tryAppServices();
                  if (services == null) {
                    onStatus('应用服务未初始化');
                    return;
                  }
                  onStatus('测试中…');
                  final uploader = ReviewUploader(proxy: services.fetcher.proxy);
                  final r = await uploader.testAccount(platform, token);
                  if (r.ok) {
                    await services.accounts
                        .setToken(platform, token, extra: {'status': r.message});
                  }
                  onStatus(r.message);
                },
                child: const Text('测试'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (syncing)
            const SizedBox(
              width: 16,
              height: 16,
              child: ProgressRing(strokeWidth: 2),
            )
          else
            Button(
              onPressed: onSync,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FluentIcons.cloud_sync_16_regular, size: 15),
                  SizedBox(width: 6),
                  Text('同步云端记录'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---------- Section 3: AI 服务设置 ----------

class _AiPreset {
  final String label;
  final String baseUrl;
  final String model;
  final String hint;
  const _AiPreset(this.label, this.baseUrl, this.model, this.hint);
}

const List<_AiPreset> _kAiPresets = [
  _AiPreset('DeepSeek', 'https://api.deepseek.com', 'deepseek-flash',
      '注意：deepseek-flash 为推理模型，会先消耗推理额度，建议最大回复长度 ≥ 2000'),
  _AiPreset('OpenAI', 'https://api.openai.com/v1', 'gpt-4o-mini', ''),
  _AiPreset('阿里云通义', 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      'qwen-plus', ''),
  _AiPreset('智谱 GLM', 'https://open.bigmodel.cn/api/paas/v4', 'glm-4-flash', ''),
  _AiPreset('本地 Ollama', 'http://127.0.0.1:11434/v1', 'qwen2.5:7b',
      '需先运行 ollama serve；本地端点无需真实 API Key，可填任意占位符'),
  _AiPreset('本地 LM Studio', 'http://127.0.0.1:1234/v1', 'local-model', ''),
  _AiPreset('自定义', '', '', '任意 OpenAI 兼容端点，请填到 /v1 或服务商指定的根路径'),
];

class _AiSection extends ConsumerStatefulWidget {
  const _AiSection();

  @override
  ConsumerState<_AiSection> createState() => _AiSectionState();
}

class _AiSectionState extends ConsumerState<_AiSection> {
  final TextEditingController _baseUrl = TextEditingController();
  final TextEditingController _apiKey = TextEditingController();
  final TextEditingController _model = TextEditingController();

  int _maxTokens = 4000;
  String _selectedPreset = '自定义';
  String _testStatus = '';
  InfoBarSeverity _testSeverity = InfoBarSeverity.info;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final services = tryAppServices();
    if (services == null) return;
    final s = services.settings;
    _baseUrl.text = await s.getString(SettingsStore.kAiBaseUrl, '');
    _apiKey.text = await s.getString(SettingsStore.kAiApiKey, '');
    _model.text = await s.getString(SettingsStore.kAiModel, '');
    _maxTokens = await s.getInt(SettingsStore.kAiMaxTokens, 4000);
    if (!mounted) return;
    setState(() {
      _selectedPreset = _matchPreset()?.label ?? '自定义';
    });
  }

  _AiPreset? _matchPreset() {
    final base = _baseUrl.text.trim().replaceAll(RegExp(r'/+$'), '');
    for (final p in _kAiPresets) {
      if (p.baseUrl.isNotEmpty &&
          p.baseUrl.replaceAll(RegExp(r'/+$'), '') == base) {
        return p;
      }
    }
    return null;
  }

  Future<void> _applyPreset(_AiPreset p) async {
    final s = tryAppServices()?.settings;
    if (p.baseUrl.isNotEmpty) {
      _baseUrl.text = p.baseUrl;
      await s?.setString(SettingsStore.kAiBaseUrl, p.baseUrl);
    }
    if (p.model.isNotEmpty) {
      _model.text = p.model;
      await s?.setString(SettingsStore.kAiModel, p.model);
    }
    if (!mounted) return;
    setState(() {
      _selectedPreset = p.label;
      _testStatus = '已选择「${p.label}」，请填写 API Key';
      _testSeverity = InfoBarSeverity.info;
    });
  }

  Future<void> _saveAndTestConnection() async {
    final config = AiConfig(
      baseUrl: _baseUrl.text.trim(),
      apiKey: _apiKey.text.trim(),
      model: _model.text.trim(),
    );
    if (!config.ready) {
      setState(() {
        _testStatus = '请先填写完整配置';
        _testSeverity = InfoBarSeverity.warning;
      });
      return;
    }

    final services = tryAppServices();
    if (services == null) {
      setState(() {
        _testStatus = '应用服务未初始化，暂无法发起网络测试';
        _testSeverity = InfoBarSeverity.warning;
      });
      return;
    }

    await services.settings
        .setString(SettingsStore.kAiBaseUrl, config.baseUrl);
    await services.settings.setString(SettingsStore.kAiApiKey, config.apiKey);
    await services.settings.setString(SettingsStore.kAiModel, config.model);
    await services.settings.setInt(SettingsStore.kAiMaxTokens, _maxTokens);

    if (!mounted) return;
    setState(() {
      _testing = true;
      _testStatus = '正在连接测试…';
      _testSeverity = InfoBarSeverity.info;
    });

    try {
      final r = await services.ai.chat(
        config: config,
        system: '你是 KisakiGals 的连接测试助手。',
        user: '请只回复：连接成功',
        maxTokens: _maxTokens < 512 ? 512 : _maxTokens,
      );
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testStatus = r.ok ? '连接正常：${r.content}' : r.message;
        _testSeverity = r.ok ? InfoBarSeverity.success : InfoBarSeverity.error;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testStatus = '测试异常：$e';
        _testSeverity = InfoBarSeverity.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final matched = _matchPreset();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingsGroupCard(
          title: 'OpenAI 兼容服务端点',
          children: [
            _SettingRow(
              title: '服务商预设',
              subtitle: '选择后自动填充 Base URL 与推荐模型，仅需补全 API Key',
              trailing: SizedBox(
                width: 260,
                child: ComboBox<String>(
                  key: const ValueKey('settings_ai_preset_combo'),
                  isExpanded: true,
                  value: matched?.label ?? _selectedPreset,
                  items: [
                    for (final p in _kAiPresets)
                      ComboBoxItem<String>(
                        value: p.label,
                        child: Text(p.label),
                      ),
                  ],
                  onChanged: (label) {
                    if (label == null) return;
                    final p = _kAiPresets.firstWhere(
                      (e) => e.label == label,
                      orElse: () => _kAiPresets.last,
                    );
                    _applyPreset(p);
                  },
                ),
              ),
            ),
            _SettingRow(
              title: 'Base URL',
              subtitle: '例：https://api.openai.com/v1、https://api.deepseek.com',
              trailing: SizedBox(
                width: 260,
                child: TextBox(
                  key: const ValueKey('settings_ai_base_url'),
                  controller: _baseUrl,
                  placeholder: '填到 /v1 为止',
                  onChanged: (v) {
                    tryAppServices()
                        ?.settings
                        .setString(SettingsStore.kAiBaseUrl, v.trim());
                  },
                ),
              ),
            ),
            _SettingRow(
              title: 'API Key',
              subtitle: '仅保存在本地数据库，不会上传至第三方服务',
              trailing: SizedBox(
                width: 260,
                child: PasswordBox(
                  key: const ValueKey('settings_ai_api_key'),
                  controller: _apiKey,
                  placeholder: 'sk-…',
                  revealMode: PasswordRevealMode.peek,
                  onChanged: (v) {
                    tryAppServices()
                        ?.settings
                        .setString(SettingsStore.kAiApiKey, v.trim());
                  },
                ),
              ),
            ),
            _SettingRow(
              title: '模型名称',
              subtitle: '例：gpt-4o-mini、deepseek-flash、qwen-plus',
              trailing: SizedBox(
                width: 260,
                child: TextBox(
                  key: const ValueKey('settings_ai_model'),
                  controller: _model,
                  placeholder: '模型 id',
                  onChanged: (v) {
                    tryAppServices()
                        ?.settings
                        .setString(SettingsStore.kAiModel, v.trim());
                  },
                ),
              ),
            ),
            _SettingRow(
              title: '最大回复长度 (Max Tokens)',
              subtitle: '推理模型建议 ≥ 2000，避免思考额耗尽导致正文为空',
              trailing: SizedBox(
                width: 200,
                child: NumberBox<int>(
                  key: const ValueKey('settings_ai_max_tokens'),
                  value: _maxTokens,
                  min: 64,
                  max: 128000,
                  smallChange: 256,
                  largeChange: 1000,
                  clearButton: false,
                  mode: SpinButtonPlacementMode.inline,
                  onChanged: (v) async {
                    if (v == null || v < 64) return;
                    setState(() => _maxTokens = v);
                    await tryAppServices()
                        ?.settings
                        .setInt(SettingsStore.kAiMaxTokens, v);
                  },
                ),
              ),
            ),
            if (matched != null && matched.hint.isNotEmpty)
              Text(
                matched.hint,
                style: theme.typography.caption?.copyWith(
                  color: theme.inactiveColor,
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _SettingsGroupCard(
          title: '连接校验',
          children: [
            _SettingRow(
              title: '保存并测试连接',
              subtitle: '写入本地配置并向 AI 发送测试消息验证端点可用性',
              trailing: _testing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: ProgressRing(strokeWidth: 2.2),
                    )
                  : FilledButton(
                      key: const ValueKey('settings_ai_test_btn'),
                      onPressed: _saveAndTestConnection,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(FluentIcons.plug_connected_16_regular, size: 15),
                          SizedBox(width: 6),
                          Text('保存并测试连接'),
                        ],
                      ),
                    ),
            ),
            if (_testStatus.isNotEmpty)
              InfoBar(
                title: const Text('AI 连接状态'),
                content: Text(_testStatus),
                severity: _testSeverity,
                isLong: _testStatus.length > 36,
              ),
          ],
        ),
      ],
    );
  }
}

// ---------- Section 4: 备份与更新 ----------

class _BackupPluginUpdateSection extends ConsumerStatefulWidget {
  const _BackupPluginUpdateSection();

  @override
  ConsumerState<_BackupPluginUpdateSection> createState() =>
      _BackupPluginUpdateSectionState();
}

class _BackupPluginUpdateSectionState
    extends ConsumerState<_BackupPluginUpdateSection> {
  String _dataDir = '';
  int _backupCount = 0;
  bool _backupAutoEnabled = false;
  int _backupAutoHours = 12;
  bool _backupOnExit = false;
  int _backupExitMinHours = 6;
  int _backupKeep = 20;
  int _saveBackupKeep = 10;

  bool _checkingUpdate = false;
  UpdateCheckResult? _lastUpdateResult;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final services = tryAppServices();
    if (services == null) return;
    final s = services.settings;
    final autoEnabled =
        await s.getBool(SettingsStore.kBackupAutoEnabled, def: false);
    final autoHours = await s.getInt(SettingsStore.kBackupAutoHours, 12);
    final onExit = await s.getBool(SettingsStore.kBackupOnExit, def: false);
    final exitMinHours = await s.getInt(SettingsStore.kBackupExitMinHours, 6);
    final backupKeep = await s.getInt(SettingsStore.kBackupKeep, 20);
    final saveKeep = await s.getInt(SettingsStore.kSaveBackupKeep, 10);

    final backupsDir = Directory(services.paths.backups);
    final count = backupsDir.existsSync()
        ? backupsDir
            .listSync()
            .whereType<File>()
            .where((f) =>
                f.path.endsWith(BackupService.ext) || f.path.endsWith('.db'))
            .length
        : 0;
    if (!mounted) return;
    setState(() {
      _dataDir = services.paths.root;
      _backupCount = count;
      _backupAutoEnabled = autoEnabled;
      _backupAutoHours = autoHours;
      _backupOnExit = onExit;
      _backupExitMinHours = exitMinHours;
      _backupKeep = backupKeep;
      _saveBackupKeep = saveKeep;
    });
  }

  Future<void> _runBackupTo() async {
    final services = tryAppServices();
    if (services == null) {
      showNotice('应用服务未初始化，无法执行备份', error: true);
      return;
    }
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '备份保存到（取消则存默认备份目录）',
    );
    final target = BackupService(
      dbFile: services.paths.dbFile,
      backupsDir: (dir != null && dir.isNotEmpty) ? dir : services.paths.backups,
      dataRoot: services.paths.root,
    );
    final path = await target.backup(checkpointDb: services.db);
    if (dir == null || dir.isEmpty) {
      final keep =
          await services.settings.getInt(SettingsStore.kBackupKeep, 20);
      await target.prune(keep);
    }
    await _load();
    if (!mounted) return;
    showNotice('备份完成：$path');
  }

  Future<void> _restoreFromFile(BuildContext context) async {
    final services = tryAppServices();
    if (services == null) {
      showNotice('应用服务未初始化，无法恢复备份', error: true);
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      dialogTitle: '选择要恢复的备份文件（.kgbak / .db）',
    );
    final path = result?.files.single.path;
    if (path == null || path.isEmpty) return;
    if (!BackupService.looksLikeArchive(path) &&
        !BackupService.looksLikeSqlite(path)) {
      if (!mounted) return;
      showNotice('所选文件不是有效的备份（应为 .kgbak 或 .db）', error: true);
      return;
    }
    if (!context.mounted) return;
    final ok = await showFluentConfirmDialog(
      context,
      title: '恢复备份',
      content:
          '将用 ${path.split(Platform.pathSeparator).last} 覆盖当前数据库，恢复后应用会自动重启。继续吗？',
      confirmLabel: '恢复并重启',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await services.db.close();
      BackupService(
        dbFile: services.paths.dbFile,
        backupsDir: services.paths.backups,
      ).removeSidecarFiles();
      await BackupService(
        dbFile: services.paths.dbFile,
        backupsDir: services.paths.backups,
        dataRoot: services.paths.root,
      ).restore(path);
    } catch (e) {
      if (!mounted) return;
      showNotice('恢复失败：$e（可手动将备份复制到数据目录覆盖 kisakigals.db）',
          error: true);
      return;
    }
    final exe = Platform.resolvedExecutable;
    await Process.start(
      exe,
      [],
      workingDirectory: File(exe).parent.path,
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }

  Future<void> _clearCacheDialog(BuildContext context) async {
    final services = tryAppServices();
    if (services == null) {
      showNotice('应用服务未初始化', error: true);
      return;
    }
    final ok = await showFluentConfirmDialog(
      context,
      title: '清理缓存',
      content: '将删除元数据缓存与封面缓存（本地数据库不受影响）。',
      confirmLabel: '清理',
      destructive: true,
    );
    if (!ok || !mounted) return;
    services.fetcher.cache.clear();
    final covers = Directory(services.paths.covers);
    if (covers.existsSync()) {
      for (final f in covers.listSync().whereType<File>()) {
        f.deleteSync();
      }
    }
    showNotice('缓存已清理');
  }

  Future<void> _checkForUpdates() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    try {
      final checker = GithubUpdateChecker(proxy: tryAppServices()?.fetcher.proxy);
      final result = await checker.check(currentVersion: AppInfo.version);
      if (!mounted) return;
      setState(() {
        _checkingUpdate = false;
        _lastUpdateResult = result;
      });
      if (!result.ok) {
        showNotice(result.message, error: true);
        return;
      }
      if (result.hasUpdate) {
        _showUpdateDialog(result);
      } else {
        showNotice(result.message);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _checkingUpdate = false);
      showNotice('检查更新失败：$e', error: true);
    }
  }

  void _showUpdateDialog(UpdateCheckResult result) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => ContentDialog(
        title: Row(
          children: [
            Icon(FluentIcons.arrow_download_24_regular, color: accent, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '发现新版本 v${result.latestVersion}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 340),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '当前版本：v${result.currentVersion}'
                  '${(result.publishedAt ?? '').isNotEmpty ? " · 发布于 ${result.publishedAt}" : ""}',
                  style: theme.typography.caption?.copyWith(
                    color: theme.inactiveColor,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  result.releaseNotes.isNotEmpty
                      ? result.releaseNotes
                      : 'GitHub 已发布 ${result.releaseTitle}，请前往下载最新版本。',
                  style: theme.typography.body?.copyWith(height: 1.55),
                ),
              ],
            ),
          ),
        ),
        actions: [
          Button(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('稍后'),
          ),
          Button(
            onPressed: () async {
              final uri = Uri.parse(result.htmlUrl.isNotEmpty
                  ? result.htmlUrl
                  : '${AppInfo.repository}/releases');
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
            child: const Text('查看 Release 页面'),
          ),
          if (result.downloadUrl != null && result.downloadUrl!.isNotEmpty)
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final uri = Uri.parse(result.downloadUrl!);
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              child: const Text('下载更新包'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final services = tryAppServices();
    final plugins = services?.plugins.plugins ?? const <KisakiPlugin>[];
    final imported =
        services?.plugins.importedManifests ?? const <Map<String, dynamic>>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingsGroupCard(
          title: '存储位置与数据目录',
          children: [
            _SettingRow(
              title: '数据目录',
              subtitle: _dataDir.isEmpty
                  ? '未初始化（独立预览/测试模式）；修改后重启生效'
                  : '$_dataDir\n包含数据库、封面缓存与备份；修改后重启生效',
              trailing: Button(
                onPressed: () async {
                  final dir = await FilePicker.platform
                      .getDirectoryPath(dialogTitle: '选择数据目录');
                  if (dir == null || dir.isEmpty) return;
                  await tryAppServices()
                      ?.settings
                      .setString(SettingsStore.kDataDir, dir);
                  if (!mounted) return;
                  showNotice('已保存，重启应用后生效');
                },
                child: const Text('更改目录…'),
              ),
            ),
            _SettingRow(
              title: '元数据与封面缓存',
              subtitle: '搜刮缓存 24 小时；本地数据库不受清理影响',
              trailing: Button(
                onPressed: () => _clearCacheDialog(context),
                child: const Text('清理缓存'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SettingsGroupCard(
          title: '自动备份与手动备份恢复',
          children: [
            _ToggleSettingRow(
              title: '定时自动备份',
              subtitle: _backupAutoEnabled
                  ? '每 $_backupAutoHours 小时自动备份一次（常驻或托盘期间生效）'
                  : '开启后按固定间隔自动备份，自动清理仅作用于 auto 前缀文件',
              checked: _backupAutoEnabled,
              onChanged: (v) async {
                final s = tryAppServices();
                await s?.settings
                    .setBool(SettingsStore.kBackupAutoEnabled, v);
                if (!mounted) return;
                setState(() => _backupAutoEnabled = v);
                await s?.autoBackup.reschedule();
              },
            ),
            _SettingRow(
              title: '定时备份间隔（小时）',
              subtitle: '最小 1 小时，建议 6–24 小时',
              trailing: SizedBox(
                width: 170,
                child: NumberBox<int>(
                  value: _backupAutoHours,
                  min: 1,
                  max: 720,
                  clearButton: false,
                  mode: SpinButtonPlacementMode.inline,
                  onChanged: (_backupAutoEnabled || _backupOnExit)
                      ? (v) async {
                          if (v == null || v < 1) return;
                          final s = tryAppServices();
                          setState(() => _backupAutoHours = v);
                          await s?.settings
                              .setInt(SettingsStore.kBackupAutoHours, v);
                          await s?.autoBackup.reschedule();
                        }
                      : null,
                ),
              ),
            ),
            _ToggleSettingRow(
              title: '退出时备份',
              subtitle: '关闭应用/退出托盘前触发一次备份',
              checked: _backupOnExit,
              onChanged: (v) async {
                await tryAppServices()
                    ?.settings
                    .setBool(SettingsStore.kBackupOnExit, v);
                if (!mounted) return;
                setState(() => _backupOnExit = v);
              },
            ),
            _SettingRow(
              title: '退出备份最小间隔（小时）',
              subtitle: '0 表示每次退出都尝试备份',
              trailing: SizedBox(
                width: 170,
                child: NumberBox<int>(
                  value: _backupExitMinHours,
                  min: 0,
                  max: 720,
                  clearButton: false,
                  mode: SpinButtonPlacementMode.inline,
                  onChanged: _backupOnExit
                      ? (v) async {
                          if (v == null || v < 0) return;
                          setState(() => _backupExitMinHours = v);
                          await tryAppServices()
                              ?.settings
                              .setInt(SettingsStore.kBackupExitMinHours, v);
                        }
                      : null,
                ),
              ),
            ),
            _SettingRow(
              title: '数据库自动备份保留份数',
              subtitle: '超出上限时自动裁剪最旧的自动备份包',
              trailing: SizedBox(
                width: 170,
                child: NumberBox<int>(
                  value: _backupKeep,
                  min: 1,
                  max: 200,
                  clearButton: false,
                  mode: SpinButtonPlacementMode.inline,
                  onChanged: (v) async {
                    if (v == null || v < 1) return;
                    setState(() => _backupKeep = v);
                    await tryAppServices()
                        ?.settings
                        .setInt(SettingsStore.kBackupKeep, v);
                  },
                ),
              ),
            ),
            _SettingRow(
              title: '游戏存档备份保留份数',
              subtitle: '单部游戏最多保留的历史存档快照数量',
              trailing: SizedBox(
                width: 170,
                child: NumberBox<int>(
                  value: _saveBackupKeep,
                  min: 1,
                  max: 200,
                  clearButton: false,
                  mode: SpinButtonPlacementMode.inline,
                  onChanged: (v) async {
                    if (v == null || v < 1) return;
                    setState(() => _saveBackupKeep = v);
                    await tryAppServices()
                        ?.settings
                        .setInt(SettingsStore.kSaveBackupKeep, v);
                  },
                ),
              ),
            ),
            _SettingRow(
              title: '立即运行与手动备份 / 恢复',
              subtitle: '默认备份目录已有 $_backupCount 份存档（支持 .kgbak / .db）',
              trailing: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Button(
                    onPressed: () async {
                      final s = tryAppServices();
                      if (s == null) {
                        showNotice('应用服务未初始化', error: true);
                        return;
                      }
                      await s.autoBackup.runNow();
                      await _load();
                      if (!mounted) return;
                      showNotice(
                        lastAutoBackupError.isEmpty
                            ? '自动备份完成'
                            : '自动备份失败：$lastAutoBackupError',
                        error: lastAutoBackupError.isNotEmpty,
                      );
                    },
                    child: const Text('立即备份'),
                  ),
                  Button(
                    onPressed: _runBackupTo,
                    child: const Text('备份到…'),
                  ),
                  Button(
                    onPressed: () => _restoreFromFile(context),
                    child: const Text('从文件恢复…'),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SettingsGroupCard(
          title: '插件与扩展清单',
          children: [
            if (plugins.isEmpty)
              const _SettingRow(
                title: '内置插件',
                subtitle: '当前无已注册的内置插件或处于独立预览模式',
              )
            else
              for (final p in plugins)
                _SettingRow(
                  title: '${p.name} · v${p.version}',
                  subtitle:
                      '${p.description}\n${p.settings.map((s) => '${s.label}：${p.config[s.key]}').join('  ')}',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final s in p.settings
                          .where((s) => s.type == PluginSettingType.int_))
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: SizedBox(
                            width: 140,
                            child: NumberBox<int>(
                              value: (p.config[s.key] is num)
                                  ? (p.config[s.key] as num).toInt()
                                  : int.tryParse('${p.config[s.key]}') ?? 0,
                              min: 0,
                              max: 1440,
                              clearButton: false,
                              mode: SpinButtonPlacementMode.inline,
                              onChanged: (v) async {
                                if (v == null) return;
                                await tryAppServices()
                                    ?.plugins
                                    .setConfig(p.id, s.key, v);
                                if (mounted) setState(() {});
                              },
                            ),
                          ),
                        ),
                      ToggleSwitch(
                        checked: p.enabled,
                        onChanged: (v) async {
                          final appServices = tryAppServices();
                          final ctx = appServices?.pluginContext;
                          if (appServices == null || ctx == null) return;
                          await appServices.plugins.setEnabled(p.id, v, ctx);
                          ref.read(libraryVersionProvider.notifier).state++;
                          if (mounted) setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
            if (imported.isEmpty)
              _SettingRow(
                title: '尚未导入外部插件',
                subtitle: '将插件清单 JSON 拖入 data/plugins 目录，或点击右侧导入清单',
                trailing: Button(
                  onPressed: () async {
                    final s = tryAppServices();
                    if (s == null) {
                      showNotice('应用服务未初始化，无法导入插件清单', error: true);
                      return;
                    }
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['json'],
                    );
                    final path = result?.files.single.path;
                    if (path == null || path.isEmpty) return;
                    final err = await s.plugins.importManifest(path);
                    if (!mounted) return;
                    setState(() {});
                    showNotice(err ?? '导入成功（元数据展示模式）', error: err != null);
                  },
                  child: const Text('导入清单'),
                ),
              )
            else ...[
              for (final m in imported)
                _SettingRow(
                  title: '${m['name']}（外部清单）',
                  subtitle:
                      '${m['description'] ?? ''} · 作者：${m['author'] ?? '未知'}',
                ),
              Align(
                alignment: Alignment.centerRight,
                child: Button(
                  onPressed: () async {
                    final s = tryAppServices();
                    if (s == null) return;
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['json'],
                    );
                    final path = result?.files.single.path;
                    if (path == null || path.isEmpty) return;
                    final err = await s.plugins.importManifest(path);
                    if (!mounted) return;
                    setState(() {});
                    showNotice(err ?? '导入成功（元数据展示模式）', error: err != null);
                  },
                  child: const Text('继续导入清单'),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        _SettingsGroupCard(
          title: '关于 KisakiGals 与更新',
          children: [
            _SettingRow(
              title: '${AppInfo.name} · v${AppInfo.version}',
              subtitle: '作者 ${AppInfo.author} · ${AppInfo.repository}',
              trailing: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Button(
                    onPressed: () async {
                      final url = Uri.parse(AppInfo.repository);
                      if (!await launchUrl(url,
                          mode: LaunchMode.externalApplication)) {
                        if (!mounted) return;
                        showNotice('无法打开浏览器：${AppInfo.repository}', error: true);
                      }
                    },
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(FluentIcons.open_16_regular, size: 15),
                        SizedBox(width: 6),
                        Text('打开仓库'),
                      ],
                    ),
                  ),
                  if (_checkingUpdate)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: ProgressRing(strokeWidth: 2),
                    )
                  else
                    FilledButton(
                      onPressed: _checkForUpdates,
                      child: const Text('检查更新'),
                    ),
                ],
              ),
            ),
            if (_lastUpdateResult != null)
              InfoBar(
                title: Text(
                  _lastUpdateResult!.hasUpdate
                      ? '发现新版本 v${_lastUpdateResult!.latestVersion}'
                      : '版本检查结果',
                ),
                content: Text(
                  _lastUpdateResult!.hasUpdate &&
                          _lastUpdateResult!.releaseNotes.isNotEmpty
                      ? _lastUpdateResult!.releaseNotes
                      : _lastUpdateResult!.message,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
                severity: !_lastUpdateResult!.ok
                    ? InfoBarSeverity.error
                    : (_lastUpdateResult!.hasUpdate
                        ? InfoBarSeverity.info
                        : InfoBarSeverity.success),
                isLong: true,
                action: _lastUpdateResult!.hasUpdate
                    ? Button(
                        onPressed: () => _showUpdateDialog(_lastUpdateResult!),
                        child: const Text('查看详情'),
                      )
                    : null,
              ),
            Text(
              '用 Flutter 与 Fluent 2 打造 · 元数据来自 VNDB / Bangumi / 月幕GAL / Hikarinagi / Steam / CnGal / KunGal / TouchGal',
              style: theme.typography.caption?.copyWith(
                color: theme.inactiveColor,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
