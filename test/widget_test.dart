import 'dart:io';
import 'dart:convert';

import 'package:curio_case/catalog_session.dart';
import 'package:curio_case/catalog_store.dart';
import 'package:curio_case/main.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class TestPhotos extends PhotoLibrary {
  TestPhotos(super.root);
  int requests = 0;
  bool denied = false;
  bool providePhoto = false;
  // Widget fixtures use synchronous file operations so FakeAsync owns every
  // UI timer. The session tests exercise production asynchronous file I/O.
  @override
  Future<String> importBytes(List<int> bytes) async {
    final ref = 'photos/${newCatalogId()}.image';
    final target = file(ref);
    target.parent.createSync(recursive: true);
    target.writeAsBytesSync(bytes);
    return ref;
  }

  @override
  Future<void> discard(Iterable<String> refs) async {
    for (final ref in refs) {
      final target = file(ref);
      if (target.existsSync()) target.deleteSync();
    }
  }

  @override
  Future<String?> attach(ImageSource source) async {
    requests++;
    if (denied) throw StateError('Access denied');
    if (providePhoto) {
      return importBytes(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a2ioAAAAASUVORK5CYII=',
        ),
      );
    }
    return null;
  }
}

Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 80)),
  );
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String text) async {
  final target = find.text(text).last;
  await tester.ensureVisible(target);
  await tester.tap(target);
  await settle(tester);
}

Future<void> enter(WidgetTester tester, String label, String text) async {
  final target = find.byKey(Key(label));
  await tester.ensureVisible(target);
  await tester.enterText(target, text);
  await tester.pump();
}

Future<void> choose(
  WidgetTester tester,
  TargetPlatform platform,
  String label,
  String value,
) async {
  final target = find.byKey(Key(label));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

void main() {
  sqfliteFfiInit();
  testWidgets(
    'photo access is explicit; denial, cancel, remove and no-photo validation remain usable',
    (tester) async {
      late CatalogSession session;
      late TestPhotos photos;
      await tester.runAsync(() async {
        final db = await CatalogStore.open(
          databaseFactoryFfiNoIsolate,
          inMemoryDatabasePath,
        );
        final root = await Directory.systemTemp.createTemp(
          'curio-photo-widget-',
        );
        photos = TestPhotos(root);
        session = CatalogSession(CatalogStore(db), photos);
        addTearDown(() async {
          await db.close();
          await root.delete(recursive: true);
        });
      });
      await tester.pumpWidget(
        CurioCaseApp(
          session: session,
          platformOverride: TargetPlatform.android,
        ),
      );
      await settle(tester);
      await tap(tester, 'Create collection');
      await enter(tester, 'Collection name', 'Photos');
      await tap(tester, 'Save collection');
      await tap(tester, 'Add item');
      expect(photos.requests, 0);
      await enter(tester, 'Item name', 'Portrait');
      photos.denied = true;
      await tap(tester, 'Attach from gallery');
      expect(photos.requests, 1);
      expect(find.textContaining('Could not attach photo.'), findsOneWidget);
      photos.denied = false;
      photos.providePhoto = true;
      await tap(tester, 'Attach from gallery');
      expect(find.text('Remove photo'), findsOneWidget);
      await tap(tester, 'Cancel');
      await tester.runAsync(() async {
        expect(
          await Directory('${photos.root.path}/photos').list().toList(),
          isEmpty,
        );
      });
      await tap(tester, 'Add item');
      await enter(tester, 'Item name', 'Portrait');
      await tap(tester, 'Attach from gallery');
      await tap(tester, 'Save item');
      final ref = session.items.single.photoRefs.single;
      await tester.runAsync(() async {
        expect(await photos.file(ref).exists(), isTrue);
      });
      await tap(tester, 'Edit Portrait');
      await tap(tester, 'Remove photo');
      await enter(tester, 'Acquired date (YYYY-MM-DD, optional)', '2023-02-29');
      await tap(tester, 'Save item');
      expect(find.textContaining('Enter a valid date'), findsOneWidget);
      await enter(tester, 'Acquired date (YYYY-MM-DD, optional)', '');
      await enter(tester, 'Declared value (optional)', '-1');
      await tap(tester, 'Save item');
      expect(find.textContaining('Enter a nonnegative value'), findsOneWidget);
      await enter(tester, 'Declared value (optional)', '9999999999999999.99');
      await tap(tester, 'Save item');
      expect(session.items.single.photoRefs, isEmpty);
      expect(session.items.single.declaredValueMinor, 999999999999999999);
      await tester.runAsync(() async {
        expect(await photos.file(ref).exists(), isFalse);
      });
      await tap(tester, 'Edit Portrait');
      final valueField = tester.widget<TextField>(
        find.byKey(const Key('Declared value (optional)')),
      );
      expect(valueField.controller!.text, '9999999999999999.99');
      await tap(tester, 'Cancel');
      expect(tester.takeException(), isNull);
    },
  );
  const sizes = {
    'phone': Size(390, 844),
    'tablet': Size(820, 1180),
    'desktop': Size(1440, 900),
  };
  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.android,
    TargetPlatform.windows,
  ]) {
    for (final size in sizes.entries) {
      testWidgets(
        '${platform.name} ${size.key}: empty/create/edit/search/filter/delete without photos',
        (tester) async {
          tester.view.physicalSize = size.value;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          late CatalogSession session;
          late TestPhotos photos;
          await tester.runAsync(() async {
            final db = await CatalogStore.open(
              databaseFactoryFfiNoIsolate,
              inMemoryDatabasePath,
            );
            final root = await Directory.systemTemp.createTemp('curio-widget-');
            photos = TestPhotos(root);
            session = CatalogSession(CatalogStore(db), photos);
            await session.reload();
            addTearDown(() async {
              await db.close();
              await root.delete(recursive: true);
            });
          });
          await tester.pumpWidget(
            CurioCaseApp(platformOverride: platform, session: session),
          );
          await settle(tester);
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
          if (platform != TargetPlatform.android) {
            expect(find.byType(TextField), findsNothing);
          }
          await tap(tester, 'Create collection');
          await tap(tester, 'Save collection');
          expect(find.text('Enter a collection name.'), findsOneWidget);
          await enter(tester, 'Collection name', 'Coins');
          await enter(tester, 'Custom text fields (comma separated)', 'Mint');
          await tap(tester, 'Save collection');
          expect(session.collections.single.name, 'Coins');
          await tap(tester, 'Edit collection');
          await enter(tester, 'Collection name', 'Treasures');
          await tap(tester, 'Save collection');
          expect(session.collections.single.name, 'Treasures');
          await tap(tester, 'Add item');
          await enter(tester, 'Item name', 'Penny');
          await choose(tester, platform, 'Condition', 'good');
          await enter(tester, 'Tags (comma separated)', 'copper, old');
          await enter(tester, 'Notes', 'Family heirloom');
          await enter(
            tester,
            'Acquired date (YYYY-MM-DD, optional)',
            '2024-02-29',
          );
          await enter(tester, 'Declared value (optional)', '12.34');
          await enter(tester, 'Custom: Mint', 'Denver');
          await tap(tester, 'Save item');
          expect(session.items.single.declaredValueMinor, 1234);
          expect(session.items.single.acquiredAt, DateTime.utc(2024, 2, 29));
          expect(session.items.single.customFields, {'Mint': 'Denver'});
          expect(session.items.single.photoRefs, isEmpty);
          expect(find.text('Items: 1'), findsOneWidget);
          expect(
            find.text('Declared total (user-entered, not appraisal): 12.34'),
            findsOneWidget,
          );
          expect(find.text('Missing declared value: 0 of 1'), findsOneWidget);
          await enter(tester, 'New location path (Shelf / Box)', 'Shelf / Box');
          await tap(tester, 'Create location');
          await settle(tester);
          expect(find.text('Browse Shelf / Box'), findsOneWidget);
          await tap(tester, 'Penny');
          await enter(tester, 'Move to path (Shelf / Box)', 'Shelf / Box');
          await tap(tester, 'Move Penny');
          expect(find.text('Location: Shelf / Box'), findsOneWidget);
          await tap(tester, 'Browse Shelf');
          expect(find.text('Showing: Shelf'), findsOneWidget);
          expect(find.text('Penny'), findsOneWidget);
          await tap(tester, 'Unfiled');
          expect(find.text('Penny'), findsNothing);
          await tap(tester, 'All locations');
          await tap(tester, 'Penny');
          expect(find.text('Family heirloom'), findsOneWidget);
          expect(find.text('Mint: Denver'), findsOneWidget);
          expect(find.text('Declared value: 12.34'), findsOneWidget);
          await tap(tester, 'Edit Penny');
          await enter(tester, 'Item name', 'Cent');
          await tap(tester, 'Save item');
          expect(session.items.single.name, 'Cent');
          await tap(tester, 'Create collection');
          await enter(tester, 'Collection name', 'Shells');
          await tap(tester, 'Save collection');
          await tap(tester, 'Add item');
          await enter(tester, 'Item name', 'Conch');
          await tap(tester, 'Save item');
          await choose(
            tester,
            platform,
            'Collection filter',
            'All collections',
          );
          for (final query in ['cent', 'COPPER', 'heirloom', 'Denver']) {
            await enter(tester, 'Search items', query);
            expect(find.text('Cent'), findsOneWidget);
            expect(find.text('Conch'), findsNothing);
          }
          await enter(tester, 'Search items', 'missing');
          expect(
            find.text('No items found. Add an item or change your search.'),
            findsOneWidget,
          );
          await enter(tester, 'Search items', '');
          await choose(tester, platform, 'Condition filter', 'good');
          expect(find.text('Cent'), findsOneWidget);
          expect(find.text('Conch'), findsNothing);
          await choose(tester, platform, 'Condition filter', 'All conditions');
          await choose(tester, platform, 'Collection filter', 'Treasures');
          expect(find.text('Conch'), findsNothing);
          await tap(tester, 'Delete Cent');
          await tap(tester, 'Cancel');
          expect(session.items.length, 2);
          await tap(tester, 'Delete Cent');
          await tap(tester, 'Delete');
          expect(session.items.single.name, 'Conch');
          await tap(tester, 'Delete collection');
          await tap(tester, 'Delete');
          expect(session.collections.single.name, 'Shells');
          await choose(tester, platform, 'Collection filter', 'Shells');
          await tap(tester, 'Delete collection');
          await tap(tester, 'Delete');
          expect(session.collections, isEmpty);
          expect(session.items, isEmpty);
          expect(
            photos.requests,
            0,
            reason: 'No camera/gallery prompt without explicit attachment',
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
