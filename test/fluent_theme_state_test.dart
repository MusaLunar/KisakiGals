import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:kisakigals/data/db.dart';
import 'package:kisakigals/data/settings_store.dart';
import 'package:kisakigals/ui/shell/tabs.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('SettingsStore persists AccentPreset and BackdropEffectPref', () async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)',
          );
        },
      ),
    );
    addTearDown(() => db.close());

    final store = SettingsStore(db);
    expect(await store.accentPreset(), AccentPreset.system);
    expect(await store.backdropEffect(), BackdropEffectPref.mica);

    await store.setString(SettingsStore.kAccentPreset, AccentPreset.sakura.id);
    await store.setString(
      SettingsStore.kBackdropEffect,
      BackdropEffectPref.acrylic.id,
    );

    expect(await store.accentPreset(), AccentPreset.sakura);
    expect(await store.backdropEffect(), BackdropEffectPref.acrylic);
    expect(AccentPreset.fromId('unknown'), AccentPreset.system);
    expect(BackdropEffectPref.fromId('unknown'), BackdropEffectPref.mica);
  });

  test('Tabs preserves 0..5 indices and exposes Tabs.add = 6', () {
    expect(Tabs.home, 0);
    expect(Tabs.library, 1);
    expect(Tabs.discover, 2);
    expect(Tabs.stats, 3);
    expect(Tabs.ai, 4);
    expect(Tabs.settings, 5);
    expect(Tabs.add, 6);
    expect(Tabs.count, 7);
    expect(const Color(0xFF0078D4), isNotNull);
  });
}
