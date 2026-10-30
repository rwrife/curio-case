import 'dart:io';

import 'package:curio_case/adaptive.dart';
import 'package:curio_case/catalog_session.dart';
import 'package:curio_case/catalog_store.dart';
import 'package:curio_case/main.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.android,
    TargetPlatform.windows,
  ]) {
    testWidgets(
      '${platform.name} empty catalog native controls and screenshot',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        late CatalogSession session;
        await tester.runAsync(() async {
          final db = await CatalogStore.open(
            databaseFactoryFfiNoIsolate,
            inMemoryDatabasePath,
          );
          final root = await Directory.systemTemp.createTemp('curio-adaptive-');
          session = CatalogSession(CatalogStore(db), PhotoLibrary(root));
          await session.reload();
          addTearDown(() async {
            await db.close();
            await root.delete(recursive: true);
          });
        });
        await tester.pumpWidget(
          CurioCaseApp(platformOverride: platform, session: session),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('No collections yet. Create your first collection.'),
          findsOneWidget,
        );
        expect(
          find.byType(
            platform == TargetPlatform.iOS
                ? CupertinoApp
                : platform == TargetPlatform.windows
                ? fluent.FluentApp
                : MaterialApp,
          ),
          findsOneWidget,
        );
        expect(
          find.byType(
            platform == TargetPlatform.iOS
                ? CupertinoButton
                : platform == TargetPlatform.windows
                ? fluent.Button
                : OutlinedButton,
          ),
          findsWidgets,
        );
        await expectLater(
          find.byType(CurioCaseApp),
          matchesGoldenFile('goldens/${platform.name}-empty.png'),
        );
        await tester.tap(find.text('Create collection'));
        await tester.pumpAndSettle();
        expect(find.text('Save collection'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Windows large text, semantics, focus and search shortcut', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    tester.view.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.platformDispatcher.clearTextScaleFactorTestValue);
    late CatalogSession session;
    await tester.runAsync(() async {
      final db = await CatalogStore.open(
        databaseFactoryFfiNoIsolate,
        inMemoryDatabasePath,
      );
      final root = await Directory.systemTemp.createTemp('curio-shortcuts-');
      session = CatalogSession(CatalogStore(db), PhotoLibrary(root));
      await session.reload();
      addTearDown(() async {
        await db.close();
        await root.delete(recursive: true);
      });
    });
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      CurioCaseApp(platformOverride: TargetPlatform.windows, session: session),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ctrl+F search · Esc clears search'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    final search = tester.widget<fluent.TextBox>(
      find.byKey(const Key('Search items')),
    );
    expect(search.focusNode!.hasFocus, isTrue);
    expect(
      tester.getSemantics(find.byKey(const Key('Search items'))).label,
      contains('Search items'),
    );
    await tester.enterText(find.byKey(const Key('Search items')), 'absent');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(search.controller!.text, isEmpty);
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  test('native choice for all target platforms', () {
    expect(AdaptiveControls(TargetPlatform.iOS).apple, isTrue);
    expect(AdaptiveControls(TargetPlatform.android).desktop, isFalse);
    expect(AdaptiveControls(TargetPlatform.windows).desktop, isTrue);
  });
}
