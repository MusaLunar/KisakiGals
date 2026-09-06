/// 设置页：系统 / 账号 / 数据源 / 数据 / 插件 / 关于。
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_services.dart';
import '../../core/constants.dart';
import '../../core/utils.dart' show fmtDateTime;
import '../../data/settings_store.dart';
import '../../main.dart' show applyCloseBehavior;
import '../../providers.dart';
import '../../services/ai_service.dart';
import '../../services/autostart.dart';
import '../../services/cloud_sync.dart';
import '../../services/plugin_system.dart';
import '../../services/upload/upload.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/notifications.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late int _section = ref.read(settingsSectionProvider);

  @override
  void initState() {
    super.initState();
    ref.listenManual(settingsSectionProvider, (prev, next) {
      if (next != _section && mounted) setState(() => _section = next);
    });
  }

  static const _sections = [
    (Icons.tune_rounded, '系统'),
    (Icons.account_circle_rounded, '账号'),
    (Icons.travel_explore_rounded, '数据源'),
    (Icons.auto_awesome_rounded, 'AI'),
    (Icons.storage_rounded, '数据'),
    (Icons.extension_rounded, '插件'),
    (Icons.info_outline_rounded, '关于'),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 分区导航
          SizedBox(
            width: 148,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 10),
                  child: Text('设置',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ),
                for (var i = 0; i < _sections.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Material(
                      color: _section == i
                          ? (dark
                              ? KisakiColors.pink.withValues(alpha: 0.2)
                              : KisakiColors.pinkContainer)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          setState(() => _section = i);
                          ref.read(settingsSectionProvider.notifier).state = i;
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 11),
                          child: Row(
                            children: [
                              Icon(_sections[i].$1,
                                  size: 19,
                                  color: _section == i
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant),
                              const SizedBox(width: 10),
                              Text(_sections[i].$2,
                                  style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: _section == i
                                          ? FontWeight.w700
                                          : FontWeight.w500)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const VerticalDivider(width: 20),
          // 内容
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 24),
              child: switch (_section) {
                0 => const _SystemSection(),
                1 => const _AccountSection(),
                2 => const _SourceSection(),
                3 => const _AiSection(),
                4 => const _DataSection(),
                5 => const _PluginSection(),
                _ => const _AboutSection(),
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- 通用控件 ----------

class SettingsGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const SettingsGroup({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
          child: Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
        ),
        SoftCard(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          child: Column(children: children),
        ),
        const SizedBox(height: 18),
      ],
    );
  }
}

class SettingRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const SettingRow({super.key, required this.title, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600)),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(subtitle!,
                      style: TextStyle(
                          fontSize: 11.5,
                          color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 16), trailing!],
        ],
      ),
    );
  }
}

// ---------- 系统 ----------

class _SystemSection extends ConsumerStatefulWidget {
  const _SystemSection();

  @override
  ConsumerState<_SystemSection> createState() => _SystemSectionState();
}

class _SystemSectionState extends ConsumerState<_SystemSection> {
  bool _autostart = false;
  String _afterLaunch = 'none';
  String _close = 'exit';
  String _tracking = 'foreground';
  String _nsfw = 'blur';
  double _nsfwBlur = 12;
  double _bgBlur = 14;
  String _theme = 'system';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = AppServices.I.settings;
    final autostart = await AppServices.I.autostart.isEnabled();
    final after = await s.getString(SettingsStore.kAfterLaunch, 'none');
    final close = await s.getString(SettingsStore.kCloseBehavior, 'exit');
    final tracking = await s.getString(SettingsStore.kTrackingMode, 'foreground');
    final nsfw = await s.getString(SettingsStore.kNsfwMode, 'blur');
    final nsfwBlur = await s.getDouble('nsfw.blur', 12);
    final bgBlur = await s.getDouble('detail.bg_blur', 14);
    final theme = await s.getString(SettingsStore.kThemeMode, 'system');
    if (!mounted) return;
    setState(() {
      _autostart = autostart;
      _afterLaunch = after;
      _close = close;
      _tracking = tracking;
      _nsfw = nsfw;
      _nsfwBlur = nsfwBlur;
      _bgBlur = bgBlur;
      _theme = theme;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsGroup(title: '启动与窗口', children: [
          SettingRow(
            title: '开机自启',
            subtitle: '登录 Windows 后自动启动 KisakiGals',
            trailing: Switch(
              value: _autostart,
              onChanged: (v) async {
                await AppServices.I.autostart.setEnabled(v);
                setState(() => _autostart = v);
              },
            ),
          ),
          const Divider(),
          SettingRow(
            title: '启动游戏后',
            subtitle: '游戏开始运行时主窗口的行为',
            trailing: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'none', label: Text('保持前台')),
                ButtonSegment(value: 'minimize', label: Text('最小化')),
              ],
              selected: {_afterLaunch},
              onSelectionChanged: (v) async {
                await AppServices.I.settings
                    .setString(SettingsStore.kAfterLaunch, v.first);
                setState(() => _afterLaunch = v.first);
              },
            ),
          ),
          const Divider(),
          SettingRow(
            title: '关闭应用时',
            subtitle: '最小化到托盘后可从托盘图标恢复或退出',
            trailing: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'exit', label: Text('直接关闭')),
                ButtonSegment(value: 'tray', label: Text('最小化到托盘')),
              ],
              selected: {_close},
              onSelectionChanged: (v) async {
                await AppServices.I.settings
                    .setString(SettingsStore.kCloseBehavior, v.first);
                setState(() => _close = v.first);
                await applyCloseBehavior();
              },
            ),
          ),
        ]),
        SettingsGroup(title: '游玩记录', children: [
          SettingRow(
            title: '时间记录方式',
            subtitle: '仅前台：只有游戏窗口在前台时计时；挂机即计时：进程存活即计时',
            trailing: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'foreground', label: Text('仅前台')),
                ButtonSegment(value: 'elapsed', label: Text('挂机即计时')),
              ],
              selected: {_tracking},
              onSelectionChanged: (v) async {
                await AppServices.I.settings
                    .setString(SettingsStore.kTrackingMode, v.first);
                setState(() => _tracking = v.first);
              },
            ),
          ),
        ]),
        SettingsGroup(title: '外观', children: [
          SettingRow(
            title: '主题',
            subtitle: '跟随系统 / 浅色 / 深色',
            trailing: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'system', label: Text('系统')),
                ButtonSegment(value: 'light', label: Text('浅色')),
                ButtonSegment(value: 'dark', label: Text('深色')),
              ],
              selected: {_theme},
              onSelectionChanged: (v) {
                ref.read(themeProvider.notifier).set(switch (v.first) {
                  'light' => ThemeModePref.light,
                  'dark' => ThemeModePref.dark,
                  _ => ThemeModePref.system,
                });
                setState(() => _theme = v.first);
              },
            ),
          ),
          const Divider(),
          SettingRow(
            title: 'NSFW 封面处理',
            subtitle: 'R-18 封面的显示方式',
            trailing: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'blur', label: Text('模糊')),
                ButtonSegment(value: 'placeholder', label: Text('占位图')),
                ButtonSegment(value: 'show', label: Text('直接显示')),
              ],
              selected: {_nsfw},
              onSelectionChanged: (v) async {
                await AppServices.I.settings
                    .setString(SettingsStore.kNsfwMode, v.first);
                ref.read(nsfwModeProvider.notifier).state = v.first;
                setState(() => _nsfw = v.first);
              },
            ),
          ),
          if (_nsfw == 'blur')
            SettingRow(
              title: 'NSFW 模糊强度',
              subtitle: '当前 ${_nsfwBlur.round()}',
              trailing: SizedBox(
                width: 200,
                child: Slider(
                  value: _nsfwBlur,
                  min: 0,
                  max: 20,
                  divisions: 20,
                  label: '${_nsfwBlur.round()}',
                  onChanged: (v) {
                    ref.read(nsfwBlurProvider.notifier).state = v;
                    setState(() => _nsfwBlur = v);
                  },
                  onChangeEnd: (v) =>
                      AppServices.I.settings.setDouble('nsfw.blur', v),
                ),
              ),
            ),
          const Divider(),
          SettingRow(
            title: '详情页背景模糊度',
            subtitle: '背景图压暗模糊的强度（0 = 不模糊）',
            trailing: SizedBox(
              width: 200,
              child: Slider(
                value: _bgBlur,
                min: 0,
                max: 20,
                divisions: 20,
                label: '${_bgBlur.round()}',
                onChanged: (v) {
                  ref.read(detailBgBlurProvider.notifier).state = v;
                  setState(() => _bgBlur = v);
                },
                onChangeEnd: (v) =>
                    AppServices.I.settings.setDouble('detail.bg_blur', v),
              ),
            ),
          ),
        ]),
      ],
    );
  }
}

// ---------- 账号 ----------

class _AccountSection extends ConsumerStatefulWidget {
  const _AccountSection();

  @override
  ConsumerState<_AccountSection> createState() => _AccountSectionState();
}

/// 各平台 Token 获取入口（参考 ReinaManager）。
const Map<String, String> kTokenUrls = {
  KisakiSources.bangumi: 'https://next.bgm.tv/demo/access-token/create',
  KisakiSources.vndb: 'https://vndb.org/u/tokens',
  KisakiSources.hikarinagi: 'https://www.hikarinagi.org/person/settings',
};

const Map<String, String> kTokenHints = {
  KisakiSources.bangumi: '登录后创建 Access Token（勾选 collections 权限）',
  KisakiSources.vndb: '用户面板 → API Tokens（同步需 list 权限，上传需 listwrite）',
  KisakiSources.hikarinagi: '登录后在个人设置中生成 Access Token',
};

class _AccountSectionState extends ConsumerState<_AccountSection> {
  final _tokens = <String, TextEditingController>{
    KisakiSources.bangumi: TextEditingController(),
    KisakiSources.vndb: TextEditingController(),
    KisakiSources.hikarinagi: TextEditingController(),
  };
  final _status = <String, String>{};
  final _syncing = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _tokens.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    for (final platform in _tokens.keys) {
      final token = await AppServices.I.accounts.token(platform);
      if (token != null) _tokens[platform]!.text = token;
      final info = await AppServices.I.accounts.info(platform);
      if (info['status'] != null) _status[platform] = info['status'];
    }
    if (mounted) setState(() {});
  }

  Future<void> _sync(String platform) async {
    final token = _tokens[platform]!.text.trim();
    if (token.isEmpty) {
      setState(() => _status[platform] = '请先填入 Token');
      return;
    }
    setState(() => _syncing.add(platform));
    try {
      final index = await AppServices.I.repo.sourceIndex();
      final svc = CloudSyncService(proxy: AppServices.I.fetcher.proxy);
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
        onSave: (g, _) => AppServices.I.repo.updateGame(g),
      );
      ref.read(libraryVersionProvider.notifier).state++;
      final at = DateTime.now();
      await AppServices.I.accounts.setToken(platform, token, extra: {
        'status': r.ok ? '上次同步 ${fmtDateTime(at)}' : r.message,
        'last_sync': at.toIso8601String(),
      });
      if (!mounted) return;
      setState(() {
        _status[platform] = r.ok
            ? '上次同步 ${fmtDateTime(at)}\n${r.message}'
            : r.message;
      });
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(r.ok ? r.message : r.message)));
    } finally {
      if (mounted) setState(() => _syncing.remove(platform));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsGroup(
          title: '平台账号',
          children: [
            for (final platform in _tokens.keys) ...[
              if (platform != _tokens.keys.first) const Divider(),
              _AccountRow(
                platform: platform,
                controller: _tokens[platform]!,
                status: _status[platform],
                syncing: _syncing.contains(platform),
                onStatus: (msg) => setState(() => _status[platform] = msg),
                onSync: () => _sync(platform),
              ),
            ],
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Text(
            'Token 仅保存在本地数据库。点击「获取 Token」前往对应平台生成；'
            '「同步云端记录」会按平台条目 id 匹配本地游戏并更新游玩状态与评分（不覆盖本地已填评分）。',
            style: TextStyle(
                fontSize: 11.5,
                height: 1.6,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _AccountRow extends StatelessWidget {
  final String platform;
  final TextEditingController controller;
  final String? status;
  final bool syncing;
  final ValueChanged<String> onStatus;
  final VoidCallback onSync;

  const _AccountRow({
    required this.platform,
    required this.controller,
    required this.status,
    required this.syncing,
    required this.onStatus,
    required this.onSync,
  });

  @override
  Widget build(BuildContext context) {
    return SettingRow(
      title: KisakiSources.labels[platform] ?? platform,
      subtitle: status ?? kTokenHints[platform],
      trailing: SizedBox(
        width: 430,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    obscureText: true,
                    decoration: const InputDecoration(
                        hintText: '粘贴 Access Token', isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                // 获取 Token：跳转浏览器
                IconButton(
                  tooltip: '获取 Token（打开浏览器）',
                  onPressed: () async {
                    final url = Uri.parse(
                        kTokenUrls[platform] ?? 'https://example.com');
                    if (!await launchUrl(url,
                        mode: LaunchMode.externalApplication)) {
                      onStatus('无法打开浏览器，请手动访问：$url');
                    }
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                ),
                TextButton(
                  onPressed: () async {
                    final token = controller.text.trim();
                    if (token.isEmpty) {
                      onStatus('请先填入 Token');
                      return;
                    }
                    onStatus('测试中…');
                    final uploader = ReviewUploader(
                        proxy: AppServices.I.fetcher.proxy);
                    final r = await uploader.testAccount(platform, token);
                    if (r.ok) {
                      await AppServices.I.accounts
                          .setToken(platform, token, extra: {'status': r.message});
                    }
                    onStatus(r.message);
                  },
                  child: const Text('测试'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 30,
              child: syncing
                  ? const Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : OutlinedButton.icon(
                      onPressed: onSync,
                      icon: const Icon(Icons.cloud_download_rounded, size: 16),
                      label: const Text('同步云端记录',
                          style: TextStyle(fontSize: 12.5)),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- 数据源 ----------

class _SourceSection extends ConsumerStatefulWidget {
  const _SourceSection();

  @override
  ConsumerState<_SourceSection> createState() => _SourceSectionState();
}

class _SourceSectionState extends ConsumerState<_SourceSection> {
  List<String> _enabled = KisakiSources.defaultEnabled;
  final _proxyController = TextEditingController();
  final Map<String, bool> _testing = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _proxyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = AppServices.I.settings;
    _enabled = await s.getStringList(SettingsStore.kEnabledSources,
        KisakiSources.defaultEnabled);
    final proxy = await s.getString('sources.proxy', '');
    _proxyController.text = proxy;
    if (mounted) setState(() {});
  }

  Future<void> _saveEnabled(List<String> v) async {
    await AppServices.I.settings
        .setStringList(SettingsStore.kEnabledSources, v);
    setState(() => _enabled = v);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsGroup(
          title: '网络',
          children: [
            SettingRow(
              title: '代理地址',
              subtitle:
                  '例：http://127.0.0.1:7890；留空时自动使用系统代理（当前检测：${AppServices.I.fetcher.proxy ?? '直连'}）',
              trailing: SizedBox(
                width: 240,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _proxyController,
                        decoration:
                            const InputDecoration(hintText: '留空=自动', isDense: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () async {
                        await AppServices.I.settings.setString(
                            'sources.proxy', _proxyController.text.trim());
                        await AppServices.I.fetcher.init(tokens: {});
                        if (context.mounted) {
                          showNotice(ref, '代理设置已保存并重新加载');
                        }
                      },
                      child: const Text('保存'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: '元数据源（搜刮时并发查询）',
          children: [
            for (final id in KisakiSources.defaultEnabled + [KisakiSources.dlsite, KisakiSources.cngal]) ...[
              SettingRow(
                title: KisakiSources.labels[id] ?? id,
                subtitle: id == KisakiSources.cngal ? '公开 API 不太稳定，默认关闭' : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _testing[id] == true
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : TextButton(
                            onPressed: () async {
                              setState(() => _testing[id] = true);
                              final ok =
                                  await AppServices.I.fetcher.testSource(id);
                              if (!context.mounted) return;
                              showNotice(ref,
                                  '${KisakiSources.labels[id]}：${ok ? '连接正常' : '连接失败'}',
                                  error: !ok);
                              if (context.mounted) {
                                setState(() => _testing[id] = false);
                              }
                            },
                            child: const Text('测试'),
                          ),
                    Switch(
                      value: _enabled.contains(id),
                      onChanged: (v) {
                        final next = [..._enabled];
                        if (v) {
                          next.add(id);
                        } else {
                          next.remove(id);
                        }
                        _saveEnabled(next);
                      },
                    ),
                  ],
                ),
              ),
              if (id != KisakiSources.cngal) const Divider(),
            ],
          ],
        ),
      ],
    );
  }
}

// ---------- AI ----------

class _AiSection extends ConsumerStatefulWidget {
  const _AiSection();

  @override
  ConsumerState<_AiSection> createState() => _AiSectionState();
}

class _AiSectionState extends ConsumerState<_AiSection> {
  final _baseUrl = TextEditingController();
  final _apiKey = TextEditingController();
  final _model = TextEditingController();
  String _testStatus = '';
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
    final s = AppServices.I.settings;
    _baseUrl.text = await s.getString(SettingsStore.kAiBaseUrl, '');
    _apiKey.text = await s.getString(SettingsStore.kAiApiKey, '');
    _model.text = await s.getString(SettingsStore.kAiModel, '');
    if (mounted) setState(() {});
  }

  AiConfig _config() => AiConfig(
      baseUrl: _baseUrl.text.trim(),
      apiKey: _apiKey.text.trim(),
      model: _model.text.trim());

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsGroup(title: 'AI 服务（OpenAI 兼容）', children: [
          SettingRow(
            title: 'Base URL',
            subtitle: '例：https://api.openai.com/v1、https://api.deepseek.com/v1 或本地 Ollama/LM Studio 端点',
            trailing: SizedBox(
              width: 260,
              child: TextField(
                controller: _baseUrl,
                decoration: const InputDecoration(hintText: '填到 /v1 为止', isDense: true),
                onChanged: (v) => AppServices.I.settings
                    .setString(SettingsStore.kAiBaseUrl, v.trim()),
              ),
            ),
          ),
          const Divider(),
          SettingRow(
            title: 'API Key',
            subtitle: '仅保存在本地数据库',
            trailing: SizedBox(
              width: 260,
              child: TextField(
                controller: _apiKey,
                obscureText: true,
                decoration: const InputDecoration(hintText: 'sk-…', isDense: true),
                onChanged: (v) => AppServices.I.settings
                    .setString(SettingsStore.kAiApiKey, v.trim()),
              ),
            ),
          ),
          const Divider(),
          SettingRow(
            title: '模型名称',
            subtitle: '例：gpt-4o-mini、deepseek-chat、qwen-plus',
            trailing: SizedBox(
              width: 260,
              child: TextField(
                controller: _model,
                decoration: const InputDecoration(hintText: '模型 id', isDense: true),
                onChanged: (v) => AppServices.I.settings
                    .setString(SettingsStore.kAiModel, v.trim()),
              ),
            ),
          ),
        ]),
        SettingsGroup(title: '连接', children: [
          SettingRow(
            title: '测试连接',
            subtitle: _testStatus.isEmpty ? '向 AI 发送一条测试消息验证配置' : _testStatus,
            trailing: _testing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : OutlinedButton(
                    onPressed: () async {
                      final config = _config();
                      if (!config.ready) {
                        setState(() => _testStatus = '请先填写完整配置');
                        return;
                      }
                      setState(() {
                        _testing = true;
                        _testStatus = '测试中…';
                      });
                      final r = await AppServices.I.ai.chat(
                        config: config,
                        system: '你是 KisakiGals 的连接测试助手。',
                        user: '请只回复：连接成功',
                        maxTokens: 20,
                      );
                      if (!mounted) return;
                      setState(() {
                        _testing = false;
                        _testStatus = r.ok ? '连接正常：${r.content}' : r.message;
                      });
                    },
                    child: const Text('测试'),
                  ),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Text(
            '配置后可在「AI」页生成游玩总结与作品推荐；推荐结果以卡片展示，可一键搜刮入库。'
            '任何 OpenAI 兼容端点（DeepSeek / 通义 / Ollama / LM Studio 等）均可使用。',
            style: TextStyle(
                fontSize: 11.5,
                height: 1.6,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

// ---------- 数据 ----------

class _DataSection extends ConsumerStatefulWidget {
  const _DataSection();

  @override
  ConsumerState<_DataSection> createState() => _DataSectionState();
}

class _DataSectionState extends ConsumerState<_DataSection> {
  String _dataDir = '';
  int _backupCount = 0;
  bool _autoBackup = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _dataDir = AppServices.I.paths.root;
    _autoBackup = await AppServices.I.settings
        .getBool(SettingsStore.kAutoBackup, def: true);
    final backups = AppServices.I.paths.backups;
    final dir = Directory(backups);
    _backupCount = dir.existsSync()
        ? dir.listSync().whereType<File>().where((f) => f.path.endsWith('.db')).length
        : 0;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsGroup(title: '存储位置', children: [
          SettingRow(
            title: '数据目录',
            subtitle: '$_dataDir\n（包含数据库、封面缓存、备份；修改后重启生效）',
            trailing: SizedBox(
              width: 130,
              child: OutlinedButton(
                onPressed: () async {
                  final result = await FilePicker.platform.getDirectoryPath(
                      dialogTitle: '选择数据目录');
                  if (result != null) {
                    await AppServices.I.settings
                        .setString(SettingsStore.kDataDir, result);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已保存，重启应用后生效')));
                  }
                },
                child: const Text('更改'),
              ),
            ),
          ),
        ]),
        SettingsGroup(title: '备份与恢复', children: [
          SettingRow(
            title: '每日自动备份',
            subtitle: '启动时若距上次备份超过 24 小时则自动创建',
            trailing: Switch(
              value: _autoBackup,
              onChanged: (v) async {
                await AppServices.I.settings
                    .setBool(SettingsStore.kAutoBackup, v);
                setState(() => _autoBackup = v);
              },
            ),
          ),
          const Divider(),
          SettingRow(
            title: '当前备份',
            subtitle: '默认备份目录已有 $_backupCount 份；「备份到…」可选任意位置，方便把数据拷到另一台电脑',
            trailing: Row(
              children: [
                OutlinedButton(
                  onPressed: () async {
                    // 默认存数据目录 backups/；也可选择其他位置（便于拷贝到别的电脑）
                    final dir = await FilePicker.platform.getDirectoryPath(
                        dialogTitle: '备份保存到（取消则存默认备份目录）');
                    final target = BackupService(
                        dbFile: AppServices.I.paths.dbFile,
                        backupsDir: (dir != null && dir.isNotEmpty)
                            ? dir
                            : AppServices.I.paths.backups);
                    final path =
                        await target.backup(checkpointDb: AppServices.I.db);
                    if (dir == null || dir.isEmpty) {
                      final keep = await AppServices.I.settings
                          .getInt(SettingsStore.kBackupKeep, 20);
                      await target.prune(keep);
                    }
                    await _load();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('备份完成：$path')));
                    }
                  },
                  child: const Text('备份到…'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.any,
                      dialogTitle: '选择要恢复的备份文件（.db）',
                    );
                    final path = result?.files.single.path;
                    if (path == null || path.isEmpty) return;
                    if (!BackupService.looksLikeSqlite(path)) {
                      if (context.mounted) {
                        showNotice(ref, '所选文件不是有效的数据库备份', error: true);
                      }
                      return;
                    }
                    if (!context.mounted) return;
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('恢复备份'),
                        content: Text(
                            '将用 ${path.split(Platform.pathSeparator).last} 覆盖当前数据库，恢复后应用会自动重启。继续吗？'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('取消')),
                          FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('恢复并重启')),
                        ],
                      ),
                    );
                    if (ok != true || !context.mounted) return;
                    try {
                      // 1. 关闭数据库连接（释放文件锁）
                      await AppServices.I.db.close();
                      // 2. 清理 WAL/SHM 附属文件（否则旧数据会回写覆盖恢复结果）
                      BackupService(
                              dbFile: AppServices.I.paths.dbFile,
                              backupsDir: AppServices.I.paths.backups)
                          .removeSidecarFiles();
                      // 3. 覆盖
                      await BackupService(
                              dbFile: AppServices.I.paths.dbFile,
                              backupsDir: AppServices.I.paths.backups)
                          .restore(path);
                    } catch (e) {
                      if (context.mounted) {
                        showNotice(ref,
                            '恢复失败：$e（可手动将备份复制到数据目录覆盖 kisakigals.db）',
                            error: true);
                      }
                      return;
                    }
                    // 4. 自动重启应用
                    final exe = Platform.resolvedExecutable;
                    await Process.start(exe, [],
                        workingDirectory: File(exe).parent.path,
                        mode: ProcessStartMode.detached);
                    exit(0);
                  },
                  child: const Text('从文件恢复…'),
                ),
              ],
            ),
          ),
        ]),
        SettingsGroup(title: '缓存', children: [
          SettingRow(
            title: '元数据缓存',
            subtitle: '搜刮结果缓存 24 小时；封面缓存在 covers 目录',
            trailing: OutlinedButton(
              onPressed: () {
                _clearCacheDialog(context);
              },
              child: const Text('清理'),
            ),
          ),
        ]),
      ],
    );
  }

  void _clearCacheDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清理缓存'),
        content: const Text('将删除元数据缓存与封面缓存（本地数据库不受影响）。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              AppServices.I.fetcher.cache.clear();
              final covers = Directory(AppServices.I.paths.covers);
              if (covers.existsSync()) {
                covers.listSync().whereType<File>().forEach((f) => f.deleteSync());
              }
              Navigator.pop(ctx);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('缓存已清理')));
            },
            child: const Text('清理'),
          ),
        ],
      ),
    );
  }
}

// ---------- 插件 ----------

class _PluginSection extends ConsumerWidget {
  const _PluginSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plugins = AppServices.I.plugins.plugins;
    final imported = AppServices.I.plugins.importedManifests;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsGroup(
          title: '内置插件',
          children: [
            for (final p in plugins) ...[
              SettingRow(
                title: '${p.name} · v${p.version}',
                subtitle: '${p.description}\n${p.settings.map((s) => '${s.label}：${p.config[s.key]}').join('  ')}',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final s in p.settings.where((s) => s.type == PluginSettingType.int_))
                      SizedBox(
                        width: 130,
                        child: TextFormField(
                          key: ValueKey('plugin_${p.id}_${s.key}_${p.config[s.key]}'),
                          initialValue: '${p.config[s.key]}',
                          decoration: InputDecoration(
                              isDense: true, hintText: s.label),
                          keyboardType: TextInputType.number,
                          onFieldSubmitted: (v) async {
                            final n = int.tryParse(v);
                            if (n != null) {
                              await AppServices.I.plugins.setConfig(p.id, s.key, n);
                            }
                          },
                        ),
                      ),
                    const SizedBox(width: 10),
                    Switch(
                      value: p.enabled,
                      onChanged: (v) async {
                        await AppServices.I.plugins
                            .setEnabled(p.id, v, AppServices.I.pluginContext!);
                        ref.read(libraryVersionProvider.notifier).state++;
                      },
                    ),
                  ],
                ),
              ),
              if (p != plugins.last) const Divider(),
            ],
          ],
        ),
        SettingsGroup(
          title: '外部插件（v1 支持清单导入展示）',
          children: [
            if (imported.isEmpty)
              const SettingRow(
                title: '尚未导入外部插件',
                subtitle: '将插件清单 JSON 拖入 data/plugins 目录，或点击右侧导入',
              )
            else
              for (final m in imported)
                SettingRow(
                  title: '${m['name']}（外部）',
                  subtitle: '${m['description'] ?? ''} · 作者：${m['author'] ?? '未知'}',
                ),
            SettingRow(
              title: '',
              trailing: OutlinedButton(
                onPressed: () async {
                  final result = await FilePicker.platform.pickFiles(
                      type: FileType.custom, allowedExtensions: ['json']);
                  if (result?.files.single.path != null) {
                    final err = await AppServices.I.plugins
                        .importManifest(result!.files.single.path!);
                    if (context.mounted) {
                      showNotice(ref, err ?? '导入成功（元数据展示模式）', error: err != null);
                    }
                  }
                },
                child: const Text('导入清单'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------- 关于 ----------

class _AboutSection extends ConsumerWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 30),
        ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Image.asset('assets/logo/logo_128.png',
              width: 110, height: 110,
              errorBuilder: (_, __, ___) => Icon(Icons.local_florist_rounded,
                  size: 80, color: KisakiColors.pink)),
        ),
        const SizedBox(height: 16),
        Text('KisakiGals',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text('版本 ${AppInfo.version}',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 22),
        SettingsGroup(title: '信息', children: [
          SettingRow(
              title: '作者',
              trailing: Text(AppInfo.author,
                  style: const TextStyle(fontWeight: FontWeight.w700))),
          const Divider(),
          SettingRow(
              title: '项目地址',
              subtitle: AppInfo.repository,
              trailing: OutlinedButton.icon(
                onPressed: () async {
                  final url = Uri.parse(AppInfo.repository);
                  if (!await launchUrl(url,
                      mode: LaunchMode.externalApplication)) {
                    if (context.mounted) {
                      showNotice(ref, '无法打开浏览器：${AppInfo.repository}', error: true);
                    }
                  }
                },
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('打开'),
              )),
          const Divider(),
          SettingRow(
            title: '检查更新',
            subtitle: '当前已是最新版本',
            trailing: OutlinedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('你已经在最新版本 ${AppInfo.version}')));
              },
              child: const Text('检查'),
            ),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            '用 Flutter 与 ♥ 打造 · 元数据来自 VNDB / Bangumi / 月幕GAL / Hikarinagi / Steam / CnGal / KunGal / TouchGal',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 11,
                color: dark ? KisakiColors.nightInkSoft : KisakiColors.inkSoft),
          ),
        ),
      ],
    );
  }
}
