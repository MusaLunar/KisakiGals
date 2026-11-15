import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisakigals/core/constants.dart';
import 'package:kisakigals/data/models.dart';
import 'package:kisakigals/data/settings_store.dart';
import 'package:kisakigals/providers.dart';
import 'package:kisakigals/scraping/scraped_game.dart';
import 'package:kisakigals/services/save_backup.dart';
import 'package:kisakigals/services/save_dir_detector.dart';
import 'package:kisakigals/ui/add/scrape_search_dialog.dart';
import 'package:kisakigals/ui/detail/save_backup_dialog.dart';
import 'package:kisakigals/ui/fluent/fluent_notices.dart';
import 'package:kisakigals/ui/fluent/fluent_surfaces.dart';
import 'package:kisakigals/ui/fluent/fluent_theme.dart';
import 'package:kisakigals/ui/widgets/image_picker_dialog.dart';
import 'package:kisakigals/ui/widgets/save_dir_picker_dialog.dart';

Widget _testHost({
  required Widget Function(BuildContext context, WidgetRef ref) builder,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: FluentApp(
      theme: buildFluentTheme(
        brightness: Brightness.light,
        preset: AccentPreset.azure,
        systemAccent: kDefaultWin11Azure,
        backdrop: BackdropEffectPref.solid,
      ),
      home: Consumer(
        builder: (context, ref, _) => ScaffoldPage(
          content: Center(child: builder(context, ref)),
        ),
      ),
    ),
  );
}

void main() {
  tearDown(() {
    NoticeCenter.instance.clear();
  });

  group('ImagePickerDialog', () {
    testWidgets('renders Fluent ContentDialog and cancels returning null',
        (tester) async {
      String? picked = 'initial';
      await tester.pumpWidget(
        _testHost(
          builder: (context, _) => FilledButton(
            onPressed: () async {
              picked = await showImagePickerDialog(
                context,
                title: '选择封面',
                candidates: const ['https://example.com/a.jpg'],
              );
            },
            child: const Text('打开'),
          ),
        ),
      );

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      expect(find.byType(ContentDialog), findsOneWidget);
      expect(find.text('选择封面'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(picked, isNull);
      expect(Game(name: 'Test').displayName, 'Test');
    });

    testWidgets('returns typed URL/path or picked local file path',
        (tester) async {
      String? picked;
      final tempDir = Directory.systemTemp.createTempSync('kisaki_img_dlg_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      final localImg = File('${tempDir.path}/cover.png')
        ..writeAsBytesSync(const [0, 1, 2]);

      await tester.pumpWidget(
        _testHost(
          builder: (context, _) => FilledButton(
            onPressed: () async {
              picked = await showImagePickerDialog(
                context,
                title: '选择背景图',
                candidates: const ['https://example.com/bg1.jpg'],
                pickLocalFile: () async => localImg.path,
              );
            },
            child: const Text('打开图片选择'),
          ),
        ),
      );

      await tester.tap(find.text('打开图片选择'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('浏览本地图片…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(picked, localImg.path);
    });

    testWidgets('selects candidate thumbnail and returns its URL',
        (tester) async {
      String? picked;
      await tester.pumpWidget(
        _testHost(
          builder: (context, _) => FilledButton(
            onPressed: () async {
              picked = await showImagePickerDialog(
                context,
                title: '选择封面',
                candidates: const [
                  'https://example.com/a.jpg',
                  'https://example.com/b.jpg',
                ],
              );
            },
            child: const Text('选封面'),
          ),
        ),
      );

      await tester.tap(find.text('选封面'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FluentCoverImage).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(find.byType(ContentDialog), findsNothing);
      expect(picked, 'https://example.com/b.jpg');
    });

    testWidgets(
        'filters partial URL typing from preview grid while keeping confirm synchronous',
        (tester) async {
      String? picked;
      await tester.pumpWidget(
        _testHost(
          builder: (context, _) => FilledButton(
            onPressed: () async {
              picked = await showImagePickerDialog(
                context,
                title: '选择封面',
                candidates: const ['https://example.com/a.jpg'],
              );
            },
            child: const Text('打开'),
          ),
        ),
      );

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.byType(FluentCoverImage), findsOneWidget);

      for (final partial in const ['h', 'htt', 'http://', 'https://']) {
        await tester.enterText(find.byType(TextBox), partial);
        await tester.pump();
        expect(
          find.byType(FluentCoverImage),
          findsOneWidget,
          reason: 'Partial input "$partial" should not mount a preview tile',
        );
      }

      await tester.enterText(
        find.byType(TextBox),
        'https://example.com/new.jpg',
      );
      await tester.pump();
      expect(find.byType(FluentCoverImage), findsNWidgets(2));

      await tester.enterText(find.byType(TextBox), 'htt');
      await tester.pump();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(picked, 'htt');
    });
  });

  group('SaveDirPickerDialog', () {
    testWidgets('shows ProgressRing while loading then radio-selectable cards',
        (tester) async {
      String? picked;
      final candidates = [
        SaveDirCandidate(
          path: r'C:\Games\Senren\savedata',
          reason: '游戏目录内 savedata',
          fileCount: 12,
          confidence: 92,
          exists: true,
        ),
        const SaveDirCandidate(
          path: r'C:\Missing\save',
          reason: '注册表记录的路径',
          fileCount: 0,
          confidence: 60,
          exists: false,
        ),
      ];

      await tester.pumpWidget(
        _testHost(
          builder: (context, _) => FilledButton(
            onPressed: () async {
              picked = await showSaveDirPickerDialog(
                context,
                Game(id: 1, name: '千恋万花'),
                detectCandidates: (_) async {
                  await Future<void>.delayed(const Duration(milliseconds: 80));
                  return candidates;
                },
              );
            },
            child: const Text('识别存档目录'),
          ),
        ),
      );

      await tester.tap(find.text('识别存档目录'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.byType(ProgressRing), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byType(ProgressRing), findsNothing);
      expect(find.text('高 92'), findsOneWidget);
      expect(find.text('目录不存在'), findsOneWidget);
      expect(find.text('手动浏览目录'), findsOneWidget);

      // 点击已失效候选不应启用确定
      await tester.tap(find.textContaining('注册表记录的路径'));
      await tester.pump();

      // 点击有效候选可单选并确认返回完整路径
      await tester.tap(find.textContaining('游戏目录内 savedata'));
      await tester.pump();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(picked, r'C:\Games\Senren\savedata');
    });

    testWidgets('manual browse button returns picked directory immediately',
        (tester) async {
      String? picked;
      await tester.pumpWidget(
        _testHost(
          builder: (context, _) => FilledButton(
            onPressed: () async {
              picked = await showSaveDirPickerDialog(
                context,
                Game(id: 2, name: 'ATRI'),
                detectCandidates: (_) async => const [],
                pickManualDir: () async => r'D:\Saves\ATRI',
              );
            },
            child: const Text('打开目录选择'),
          ),
        ),
      );

      await tester.tap(find.text('打开目录选择'));
      await tester.pumpAndSettle();
      expect(find.text('没有找到疑似存档目录'), findsOneWidget);

      await tester.tap(find.text('手动浏览目录'));
      await tester.pumpAndSettle();
      expect(picked, r'D:\Saves\ATRI');
    });
  });

  group('SaveBackupDialog', () {
    late Directory tempRoot;
    late Directory saveDir;
    late SaveBackupService backupService;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('kisaki_bak_dlg_');
      saveDir = Directory('${tempRoot.path}/game_save')..createSync();
      File('${saveDir.path}/slot1.sav').writeAsStringSync('save-v1');
      backupService = SaveBackupService('${tempRoot.path}/data');
    });

    tearDown(() {
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    });

    testWidgets(
        'backs up, blocks restore while running, restores with snapshot, and deletes with confirmation',
        (tester) async {
      var running = false;
      final game = Game(
        id: 7,
        name: 'ATRI',
        savePath: saveDir.path,
      );
      int libVersion = 0;

      await tester.pumpWidget(
        _testHost(
          builder: (context, ref) {
            libVersion = ref.watch(libraryVersionProvider);
            return FilledButton(
              onPressed: () => showSaveBackupDialog(
                context,
                ref,
                game,
                backupService: backupService,
                readKeepCount: () async => 5,
                saveGamePath: (_) async {},
                isGameRunning: (_) => running,
                pickSaveDir: (_, __) async => saveDir.path,
              ),
              child: const Text('存档备份'),
            );
          },
        ),
      );

      await tester.tap(find.text('存档备份'));
      await tester.pumpAndSettle();
      expect(find.text('暂无备份'), findsOneWidget);
      expect(find.text(saveDir.path), findsOneWidget);

      // 立即备份
      await tester.tap(find.text('立即备份'));
      await tester.pumpAndSettle();
      expect(backupService.list(7).length, 1);
      expect(find.textContaining('1 个文件'), findsOneWidget);
      expect(NoticeCenter.instance.items.last.error, isFalse);

      // 游戏中阻止恢复
      running = true;
      await tester.tap(find.text('恢复'));
      await tester.pumpAndSettle();
      expect(NoticeCenter.instance.items.last.error, isTrue);
      expect(NoticeCenter.instance.items.last.message, contains('正在运行'));

      // 退出游戏后允许恢复并生成恢复前快照（auto 徽标）
      running = false;
      File('${saveDir.path}/slot1.sav').writeAsStringSync('save-v2');
      await tester.tap(find.text('恢复'));
      await tester.pumpAndSettle();
      expect(find.text('恢复存档'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '恢复'));
      await tester.pumpAndSettle();

      expect(File('${saveDir.path}/slot1.sav').readAsStringSync(), 'save-v1');
      expect(backupService.list(7).length, 2);
      expect(find.text('自动'), findsOneWidget);

      // 删除需二次破坏性确认
      await tester.tap(find.text('删除').first);
      await tester.pumpAndSettle();
      expect(find.text('删除备份'), findsOneWidget);
      await tester.tap(find.widgetWithText(Button, '删除').last);
      await tester.pumpAndSettle();
      expect(backupService.list(7).length, 1);

      // 识别目录后同步保存并刷新 libraryVersionProvider
      await tester.tap(find.text('识别候选…'));
      await tester.pumpAndSettle();
      expect(libVersion, 1);
      NoticeCenter.instance.clear();
    });
  });

  group('ScrapeSearchDialog', () {
    testWidgets(
        'filters sources, searches grouped hits in Expander with R18 before score, and applies metadata',
        (tester) async {
      final game = Game(id: 11, name: 'Senren', nameCn: '千恋万花');
      List<String> searchedSources = const [];
      List<ScrapedGame>? appliedList;
      bool? dialogResult;
      int libVersion = 0;

      final hit = ScrapedGame(
        source: KisakiSources.vndb,
        sourceId: 'v19073',
        name: '千恋＊万花',
        nameCn: '千恋万花',
        developer: 'ゆずソフト',
        releaseDate: '2016-07-29',
        summary: '在穗织邂逅巫女与刀剑的故事。',
        rating: 8.6,
        voteCount: 3200,
        nsfw: true,
        tags: const [ScrapedTag('纯爱', weight: 3.0)],
      );
      final group = ScrapeHitGroup(hit, [hit], 95);

      await tester.pumpWidget(
        _testHost(
          builder: (context, ref) {
            libVersion = ref.watch(libraryVersionProvider);
            return FilledButton(
              onPressed: () async {
                dialogResult = await showScrapeSearchDialog(
                  context,
                  ref,
                  game,
                  initialQuery: '千恋万花',
                  onSearch: (kw, only) async {
                    searchedSources = only;
                    return [group];
                  },
                  onMergeGroup: (g) async => [g.merged],
                  onApply: (target, all) async {
                    appliedList = all;
                  },
                );
              },
              child: const Text('刮削匹配'),
            );
          },
        ),
      );

      await tester.tap(find.text('刮削匹配'));
      await tester.pumpAndSettle();

      expect(find.byType(ContentDialog), findsOneWidget);
      expect(find.text('千恋万花'), findsOneWidget);
      expect(find.text('VNDB'), findsOneWidget);
      expect(find.text('Bangumi'), findsOneWidget);

      // 切换关闭 Bangumi 来源筛选
      await tester.tap(find.text('Bangumi'));
      await tester.pump();

      await tester.tap(find.text('搜索'));
      await tester.pumpAndSettle();

      expect(searchedSources, isNot(contains(KisakiSources.bangumi)));
      expect(searchedSources, contains(KisakiSources.vndb));
      expect(find.byType(Expander), findsOneWidget);

      // R18 徽标必须严格在评分之前
      final r18Box = tester.getTopLeft(find.text('R18'));
      final scoreBox = tester.getTopLeft(find.textContaining('8.6'));
      expect(r18Box.dx, lessThan(scoreBox.dx));

      await tester.tap(find.text('应用到当前作品'));
      await tester.pumpAndSettle();

      expect(dialogResult, isTrue);
      expect(appliedList, isNotNull);
      expect(appliedList!.first.sourceId, 'v19073');
      expect(libVersion, 1);
      expect(NoticeCenter.instance.items, isNotEmpty);
      NoticeCenter.instance.clear();
    });

    testWidgets('returns false when cancelled', (tester) async {
      bool? dialogResult;
      await tester.pumpWidget(
        _testHost(
          builder: (context, ref) => FilledButton(
            onPressed: () async {
              dialogResult = await showScrapeSearchDialog(
                context,
                ref,
                Game(id: 12, name: 'Summer Pockets'),
              );
            },
            child: const Text('打开刮削'),
          ),
        ),
      );

      await tester.tap(find.text('打开刮削'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(dialogResult, isFalse);
      NoticeCenter.instance.clear();
    });
  });
}
