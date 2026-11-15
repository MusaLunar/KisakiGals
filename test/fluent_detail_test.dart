import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' hide FluentIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisakigals/core/constants.dart';
import 'package:kisakigals/data/models.dart';
import 'package:kisakigals/data/settings_store.dart';
import 'package:kisakigals/providers.dart';
import 'package:kisakigals/ui/detail/edit_dialog.dart';
import 'package:kisakigals/ui/detail/game_detail_page.dart';
import 'package:kisakigals/ui/detail/play_path_tab.dart';
import 'package:kisakigals/ui/detail/rate_dialog.dart';
import 'package:kisakigals/ui/fluent/fluent_notices.dart';
import 'package:kisakigals/ui/fluent/fluent_theme.dart';
import 'package:kisakigals/ui/shell/tabs.dart';

Widget _fluentHost({
  required Widget child,
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
      home: child,
    ),
  );
}

void main() {
  tearDown(() {
    NoticeCenter.instance.clear();
  });

  testWidgets('GameDetailPage shows R18 before score and Play Path tab',
      (tester) async {
    final g = Game(
      id: 7,
      name: 'DetailVN',
      nameCn: '详情作品',
      developer: 'Key',
      nsfw: true,
      userRating: 9.6,
      totalSeconds: 10800,
    );
    final nodes = [
      PlayPathNode(id: 1, gameId: 7, note: '第一章结局选择记录'),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gameProvider(7).overrideWith((ref) async => g),
          gameSourcesProvider(7).overrideWith((ref) async => const []),
          gameTagsProvider(7).overrideWith((ref) async => const []),
          playPathProvider(7).overrideWith((ref) async => nodes),
        ],
        child: const FluentApp(home: GameDetailPage(gameId: 7)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('详情作品'), findsWidgets);
    expect(find.text('R18'), findsWidgets);
    final r18Dx = tester.getTopLeft(find.text('R18').first).dx;
    final scoreDx = tester.getTopLeft(find.textContaining('9.6').first).dx;
    expect(r18Dx, lessThan(scoreDx));

    expect(find.text('游玩路径'), findsOneWidget);
    expect(find.text('第一章结局选择记录'), findsOneWidget);
  });

  testWidgets(
      'GameDetailPage switches tabs between Play Path, Archive/Tags, and Sessions/Saves',
      (tester) async {
    final g = Game(
      id: 8,
      name: 'Clannad Original',
      nameCn: '团子大家族',
      aliases: ['CLANNAD', 'クラナド'],
      developer: 'Key',
      releaseDate: '2004-04-28',
      summary: '光坂小镇上的家族与羁绊物语。',
      nsfw: false,
      playStatus: PlayStatus.played,
      userRating: 9.8,
      userReview: '神作无需多言。',
      totalSeconds: 14400,
      savePath: r'D:\Saves\Clannad',
      firstPlayedAt: DateTime(2026, 1, 10),
      lastPlayedAt: DateTime(2026, 11, 10),
    )..sessionCount = 4;

    final sources = [
      SourceRecord(
        gameId: 8,
        source: KisakiSources.vndb,
        sourceId: 'v4',
        rating: 9.1,
        voteCount: 12000,
      ),
    ];
    final tags = [
      TagItem(name: '纯爱', weight: 3.0, source: KisakiSources.vndb),
      TagItem(name: '催泪', weight: 2.8, source: KisakiSources.bangumi),
    ];

    final container = ProviderContainer(
      overrides: [
        gameProvider(8).overrideWith((ref) async => g),
        gameSourcesProvider(8).overrideWith((ref) async => sources),
        gameTagsProvider(8).overrideWith((ref) async => tags),
        playPathProvider(8).overrideWith((ref) async => const []),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: FluentApp(
          theme: buildFluentTheme(
            brightness: Brightness.light,
            preset: AccentPreset.azure,
            systemAccent: kDefaultWin11Azure,
            backdrop: BackdropEffectPref.solid,
          ),
          home: const GameDetailPage(gameId: 8),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BreadcrumbBar<String>), findsOneWidget);
    expect(find.byType(CommandBar), findsOneWidget);
    expect(find.text('游玩路径'), findsOneWidget);
    expect(find.text('档案与标签'), findsOneWidget);
    expect(find.text('会话与存档'), findsOneWidget);

    // 切换到「会话与存档」
    await tester.tap(find.text('会话与存档'));
    await tester.pumpAndSettle();
    expect(find.textContaining('4.0 小时'), findsWidgets);
    expect(find.text(r'D:\Saves\Clannad'), findsOneWidget);

    // 切换到「档案与标签」并点击标签筛选跳转
    await tester.tap(find.text('档案与标签'));
    await tester.pumpAndSettle();
    expect(find.text('光坂小镇上的家族与羁绊物语。'), findsOneWidget);
    expect(find.text('CLANNAD'), findsOneWidget);
    expect(find.text('VNDB'), findsOneWidget);
    expect(find.text('#纯爱'), findsOneWidget);

    await tester.ensureVisible(find.text('#纯爱'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('#纯爱'));
    await tester.pumpAndSettle();

    expect(container.read(libraryFilterProvider).tag, '纯爱');
    expect(container.read(tabIndexProvider), Tabs.library);
  });

  testWidgets(
      'PlayPathTab displays F12 hotkey, authors notes with image, opens lightbox, edits, and deletes',
      (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('kisaki_playpath_ui_');
    addTearDown(() {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });
    // 1x1 valid PNG bytes
    final imgFile = File('${tempDir.path}/shot.png')
      ..writeAsBytesSync(const [
        137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0,
        1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 10, 73, 68,
        65, 84, 120, 156, 99, 0, 1, 0, 0, 5, 0, 1, 13, 10, 45, 180, 0, 0, 0,
        0, 73, 69, 78, 68, 174, 66, 96, 130,
      ]);

    final game = Game(id: 15, name: 'PlayPathTest', nameCn: '路径测试作');
    String? addedNote;
    String? addedImage;
    String? updatedNote;
    int? deletedNodeId;

    final existingNode = PlayPathNode(
      id: 99,
      gameId: 15,
      imagePath: imgFile.path,
      note: '旧分支笔记',
      createdAt: DateTime(2026, 11, 15, 10, 30),
    );

    await tester.pumpWidget(
      _fluentHost(
        overrides: [
          playPathProvider(15).overrideWith((ref) async => [existingNode]),
        ],
        child: ScaffoldPage(
          content: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: PlayPathTab(
              game: game,
              pickImageFile: () async => imgFile.path,
              onAddNode: (note, imagePath) async {
                addedNote = note;
                addedImage = imagePath;
              },
              onUpdateNode: (node) async {
                updatedNote = node.note;
              },
              onDeleteNode: (nodeId) async {
                deletedNodeId = nodeId;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('F12'), findsWidgets);
    expect(find.text('导入截图'), findsOneWidget);
    expect(find.text('添加节点'), findsOneWidget);
    expect(find.text('旧分支笔记'), findsOneWidget);

    // 1. Authoring note + image import
    await tester.enterText(find.byType(TextBox).first, '第二章新路线');
    await tester.tap(find.text('导入截图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加节点'));
    await tester.pumpAndSettle();

    expect(addedNote, '第二章新路线');
    expect(addedImage, imgFile.path);

    // 2. Click thumbnail -> opens showFluentLightboxDialog
    await tester.tap(find.byKey(const ValueKey('playpath-thumb-99')));
    await tester.pumpAndSettle();
    expect(find.byType(ContentDialog), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    // 3. Edit node
    await tester.tap(find.byKey(const ValueKey('playpath-edit-99')));
    await tester.pumpAndSettle();
    expect(find.byType(ContentDialog), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byType(ContentDialog),
        matching: find.byType(TextBox),
      ),
      '已修改分支笔记',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(updatedNote, '已修改分支笔记');

    // 4. Delete node with confirmation
    await tester.tap(find.byKey(const ValueKey('playpath-delete-99')));
    await tester.pumpAndSettle();
    expect(find.text('删除游玩路径节点'), findsOneWidget);
    await tester.tap(find.widgetWithText(Button, '删除').last);
    await tester.pumpAndSettle();
    expect(deletedNodeId, 99);
    NoticeCenter.instance.clear();
  });

  testWidgets('showRateGameDialog updates rating, review, and bumps library',
      (tester) async {
    final game = Game(
      id: 21,
      name: 'RateVN',
      nameCn: '评分测试作',
      playStatus: PlayStatus.wish,
      userRating: 7.5,
      userReview: '初始短评',
    );
    Game? savedGame;
    bool? dialogResult;
    int libVersion = 0;

    await tester.pumpWidget(
      _fluentHost(
        child: Consumer(
          builder: (context, ref, _) {
            libVersion = ref.watch(libraryVersionProvider);
            return ScaffoldPage(
              content: Center(
                child: FilledButton(
                  onPressed: () async {
                    dialogResult = await showRateGameDialog(
                      context,
                      ref,
                      game,
                      sources: const [],
                      onSave: (g) async {
                        savedGame = g;
                      },
                    );
                  },
                  child: const Text('打开评分'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('打开评分'));
    await tester.pumpAndSettle();

    expect(find.byType(ContentDialog), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('7.5 / 10'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('rate-inc-btn')));
    await tester.pump();
    expect(find.text('7.6 / 10'), findsOneWidget);

    await tester.enterText(find.byType(TextBox), '剧情反转精彩');
    await tester.tap(find.text('保存评分'));
    await tester.pumpAndSettle();

    expect(dialogResult, isTrue);
    expect(savedGame?.userRating, 7.6);
    expect(savedGame?.userReview, '剧情反转精彩');
    expect(savedGame?.playStatus, PlayStatus.played);
    expect(libVersion, 1);
    expect(NoticeCenter.instance.items.last.message, contains('已保存评分'));
    NoticeCenter.instance.clear();
  });

  testWidgets(
      'showRateGameDialog does not mutate game in-place when onSave fails',
      (tester) async {
    final game = Game(
      id: 22,
      name: 'FailRateVN',
      nameCn: '失败不改原对象',
      playStatus: PlayStatus.wish,
      userRating: 6.0,
      userReview: '原始短评',
    );
    bool? dialogResult;

    await tester.pumpWidget(
      _fluentHost(
        child: Consumer(
          builder: (context, ref, _) => ScaffoldPage(
            content: Center(
              child: FilledButton(
                onPressed: () async {
                  dialogResult = await showRateGameDialog(
                    context,
                    ref,
                    game,
                    sources: const [],
                    onSave: (_) async {
                      throw StateError('db write failed');
                    },
                  );
                },
                child: const Text('打开评分'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开评分'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('rate-inc-btn')));
    await tester.pump();
    await tester.enterText(find.byType(TextBox), '不应写入的短评');
    await tester.tap(find.text('保存评分'));
    await tester.pumpAndSettle();

    expect(dialogResult, isNull);
    expect(game.userRating, 6.0);
    expect(game.userReview, '原始短评');
    expect(game.playStatus, PlayStatus.wish);
    expect(NoticeCenter.instance.items.last.error, isTrue);
    expect(NoticeCenter.instance.items.last.message, contains('保存评分失败'));
    NoticeCenter.instance.clear();
  });

  testWidgets(
      'showEditGameDialog shows anchor bar, Expanders, and saves edited fields',
      (tester) async {
    final game = Game(
      id: 33,
      name: 'EditVN',
      nameCn: '编辑原名',
      aliases: ['Alias1'],
      developer: 'OldDev',
      releaseDate: '2025-01-01',
      summary: '旧简介',
      playStatus: PlayStatus.wish,
      nsfw: false,
      isFavorite: false,
      localeMode: 'none',
    );
    Game? savedGame;
    bool? dialogResult;
    int libVersion = 0;

    await tester.pumpWidget(
      _fluentHost(
        child: Consumer(
          builder: (context, ref, _) {
            libVersion = ref.watch(libraryVersionProvider);
            return ScaffoldPage(
              content: Center(
                child: FilledButton(
                  onPressed: () async {
                    dialogResult = await showEditGameDialog(
                      context,
                      ref,
                      game,
                      loadSources: (_) async => const [],
                      loadTags: (_) async => const [],
                      onSave: (g) async {
                        savedGame = g;
                      },
                    );
                  },
                  child: const Text('打开编辑'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('打开编辑'));
    await tester.pumpAndSettle();

    expect(find.byType(ContentDialog), findsOneWidget);
    expect(find.text('基本信息'), findsWidgets);
    expect(find.text('启动与目录'), findsWidgets);
    expect(find.text('存档与备份'), findsWidgets);
    expect(find.text('视觉封面'), findsWidgets);
    expect(find.byType(Expander), findsNWidgets(4));
    expect(find.byType(ComboBox<PlayStatus>), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('edit-name-cn')),
      '编辑后中文名',
    );
    await tester.enterText(
      find.byKey(const ValueKey('edit-aliases')),
      '别名甲, 别名乙',
    );
    await tester.tap(find.byKey(const ValueKey('edit-nsfw-switch')));
    await tester.pumpAndSettle();

    final leSwitchFinder = find.byKey(const ValueKey('edit-le-switch'));
    await tester.ensureVisible(leSwitchFinder);
    await tester.pumpAndSettle();
    await tester.tap(leSwitchFinder);
    await tester.pumpAndSettle();

    // Anchor jump to 视觉封面
    await tester.tap(find.byKey(const ValueKey('edit-anchor-media')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();

    expect(dialogResult, isTrue);
    expect(savedGame?.nameCn, '编辑后中文名');
    expect(savedGame?.aliases, ['别名甲', '别名乙']);
    expect(savedGame?.nsfw, isTrue);
    expect(savedGame?.localeMode, 'japanese');
    expect(savedGame?.useLocaleEmulator, isTrue);
    expect(libVersion, 1);
    NoticeCenter.instance.clear();
  });

  testWidgets(
      'showEditGameDialog normalizes legacy "le" localeMode to canonical "japanese"',
      (tester) async {
    final game = Game(
      id: 34,
      name: 'LegacyLeVN',
      localeMode: 'le',
    );
    Game? savedGame;

    await tester.pumpWidget(
      _fluentHost(
        child: Consumer(
          builder: (context, ref, _) {
            return ScaffoldPage(
              content: Center(
                child: FilledButton(
                  onPressed: () async {
                    await showEditGameDialog(
                      context,
                      ref,
                      game,
                      loadSources: (_) async => const [],
                      loadTags: (_) async => const [],
                      onSave: (g) async {
                        savedGame = g;
                      },
                    );
                  },
                  child: const Text('打开编辑'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('打开编辑'));
    await tester.pumpAndSettle();

    final leSwitchFinder = find.byKey(const ValueKey('edit-le-switch'));
    await tester.ensureVisible(leSwitchFinder);
    await tester.pumpAndSettle();
    final leSwitch = tester.widget<ToggleSwitch>(leSwitchFinder);
    expect(leSwitch.checked, isTrue);

    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();

    expect(savedGame?.localeMode, 'japanese');
    expect(savedGame?.useLocaleEmulator, isTrue);
    NoticeCenter.instance.clear();
  });
}
