import 'dart:convert';
import 'dart:io';

import 'package:curio_case/catalog.dart';
import 'package:curio_case/catalog_backup.dart';
import 'package:curio_case/catalog_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('round trip collections, fields, moves, locations and photos', () async {
    final root = await Directory.systemTemp.createTemp('curio-backup-');
    addTearDown(() => root.delete(recursive: true));
    final db = await CatalogStore.open(
      databaseFactoryFfi,
      inMemoryDatabasePath,
    );
    addTearDown(db.close);
    final store = CatalogStore(db);
    final backup = CatalogBackup(store, root);
    await store.saveCollection(
      CollectionRecord(id: 'c', name: 'Coins', customFields: {'Year': '2020'}),
    );
    await store.createLocation('c', LocationPath(['Shelf', 'Box']));
    await store.saveItem(
      CatalogItem(
        id: 'i',
        collectionId: 'c',
        name: 'Mint coin',
        customFields: {'Mint': 'Denver'},
        photoRefs: ['photos/coin.image'],
      ),
    );
    await store.moveItem(
      'i',
      LocationPath(['Shelf', 'Box']),
      DateTime.utc(2026),
    );
    await Directory('${root.path}/photos').create();
    await File('${root.path}/photos/coin.image').writeAsBytes([0, 1, 255]);
    final snapshot = await backup.exportJson();
    await store.deleteCollection('c');
    await File('${root.path}/photos/coin.image').delete();
    await backup.restoreJson(snapshot);
    expect((await store.collections()).single.customFields, {'Year': '2020'});
    expect((await store.items()).single.customFields, {'Mint': 'Denver'});
    expect((await store.moves('i')).single.to.label, 'Shelf / Box');
    expect((await store.locations('c')).length, 2);
    expect(await File('${root.path}/photos/coin.image').readAsBytes(), [
      0,
      1,
      255,
    ]);
    final without = await backup.exportJson(includePhotos: false);
    await backup.restoreJson(without);
    expect((await store.items()).single.photoRefs, isEmpty);
    expect(
      CatalogBackup.exportCsv(await store.collections(), await store.items()),
      contains('Mint'),
    );
  });

  test('invalid and future snapshots leave live catalog intact', () async {
    final root = await Directory.systemTemp.createTemp('curio-backup-');
    addTearDown(() => root.delete(recursive: true));
    final db = await CatalogStore.open(
      databaseFactoryFfi,
      inMemoryDatabasePath,
    );
    addTearDown(db.close);
    final store = CatalogStore(db);
    final backup = CatalogBackup(store, root);
    await store.saveCollection(CollectionRecord(id: 'live', name: 'Original'));
    final good = jsonDecode(await backup.exportJson()) as Map<String, dynamic>;
    final failures = <Map<String, dynamic>>[
      {...good, 'version': 2},
      {
        ...good,
        'collections': [
          ...(good['collections'] as List),
          (good['collections'] as List).first,
        ],
      },
      {
        ...good,
        'items': [
          {
            'id': 'x',
            'collection_id': 'live',
            'name': 'X',
            'condition': 'good',
            'location': '[]',
            'photo_refs': '["../secret"]',
            'tags': '[]',
            'acquired_at': null,
            'notes': '',
            'declared_value_minor': null,
            'custom_fields': '{}',
          },
        ],
      },
      {
        ...good,
        'items': [
          {
            'id': 'x',
            'collection_id': 'live',
            'name': 'X',
            'condition': 'good',
            'location': '[]',
            'photo_refs': '["photos/missing"]',
            'tags': '[]',
            'acquired_at': null,
            'notes': '',
            'declared_value_minor': null,
            'custom_fields': '{}',
          },
        ],
      },
    ];
    for (final bad in failures) {
      await expectLater(
        backup.restoreJson(jsonEncode(bad)),
        throwsA(isA<Object>()),
      );
      expect((await store.collections()).single.name, 'Original');
    }
    await expectLater(backup.restoreJson('{broken'), throwsFormatException);
    expect((await store.collections()).single.id, 'live');
  });

  test('failed photo write rolls database back', () async {
    final root = await Directory.systemTemp.createTemp('curio-backup-');
    addTearDown(() => root.delete(recursive: true));
    final db = await CatalogStore.open(
      databaseFactoryFfi,
      inMemoryDatabasePath,
    );
    addTearDown(db.close);
    final store = CatalogStore(db);
    final backup = CatalogBackup(store, root);
    await store.saveCollection(CollectionRecord(id: 'live', name: 'Original'));
    final data = jsonDecode(await backup.exportJson()) as Map<String, dynamic>;
    data['collections'] = [
      {'id': 'new', 'name': 'New', 'template': '', 'custom_fields': '{}'},
    ];
    data['items'] = [
      {
        'id': 'i',
        'collection_id': 'new',
        'name': 'Item',
        'condition': 'good',
        'location': '[]',
        'photo_refs': '["photos/blocked"]',
        'tags': '[]',
        'acquired_at': null,
        'notes': '',
        'declared_value_minor': null,
        'custom_fields': '{}',
      },
    ];
    data['photos'] = {
      'photos/blocked': base64Encode([1, 2]),
    };
    await File('${root.path}/photos').writeAsString('not a directory');
    await expectLater(
      backup.restoreJson(jsonEncode(data)),
      throwsA(isA<FileSystemException>()),
    );
    expect((await store.collections()).single.id, 'live');
    expect(await store.items(), isEmpty);
  });

  test('CSV quotes fields and neutralizes spreadsheet formulas', () {
    final csv = CatalogBackup.exportCsv(
      [CollectionRecord(id: 'c', name: '=SUM(1)')],
      [
        CatalogItem(
          id: 'i',
          collectionId: 'c',
          name: '+cmd',
          notes: '"quoted",\nline',
          customFields: {'key': '@evil'},
        ),
      ],
    );
    expect(csv, startsWith('\uFEFF'));
    expect(csv, contains('"\'=SUM(1)"'));
    expect(csv, contains('"\'+cmd"'));
    expect(csv, contains('"""quoted"",\nline"'));
  });
}
