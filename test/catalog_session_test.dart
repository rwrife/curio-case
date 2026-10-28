import 'dart:io';

import 'package:curio_case/catalog.dart';
import 'package:curio_case/catalog_session.dart';
import 'package:curio_case/catalog_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  test('photo imports are owned copies; replacing and cascading deletes clean only unused files', () async {
    final root = await Directory.systemTemp.createTemp('curio-photos-');
    final db = await CatalogStore.open(
      databaseFactoryFfi,
      '${root.path}/catalog.db',
    );
    addTearDown(() async {
      await db.close();
      await root.delete(recursive: true);
    });
    final photos = PhotoLibrary(root);
    final source = File('${root.path}/source.jpg');
    await source.writeAsBytes([1, 2, 3]);
    final ref = await photos.importBytes(await source.readAsBytes());
    await source.writeAsBytes([9]);
    expect(await photos.file(ref).readAsBytes(), [1, 2, 3]);
    expect(ref.startsWith('photos/'), isTrue);
    expect(() => photos.file('../outside'), throwsArgumentError);
    final session = CatalogSession(CatalogStore(db), photos);
    await session.saveCollection(
      CollectionRecord(id: 'c', name: 'Coins'),
      isNew: true,
    );
    await session.saveItem(
      CatalogItem(id: 'i', collectionId: 'c', name: 'Cent', photoRefs: [ref]),
      isNew: true,
    );
    await session.saveItem(
      CatalogItem(id: 'j', collectionId: 'c', name: 'Shared', photoRefs: [ref]),
      isNew: true,
    );
    await session.deleteItem(session.items.firstWhere((i) => i.id == 'i'));
    expect(await photos.file(ref).exists(), isTrue);
    final second = await photos.importBytes([4, 5]);
    await session.saveItem(
      CatalogItem(
        id: 'j',
        collectionId: 'c',
        name: 'Shared',
        photoRefs: [second],
      ),
      isNew: false,
    );
    expect(await photos.file(ref).exists(), isFalse);
    expect(await photos.file(second).exists(), isTrue);
    await session.deleteCollection(session.collections.single);
    expect(await photos.file(second).exists(), isFalse);
    expect(await source.readAsBytes(), [9]);
  });

  test('v2 migration and reopen preserve all catalog metadata and literal cross-collection search', () async {
    final root = await Directory.systemTemp.createTemp('curio-v2-');
    final path = '${root.path}/catalog.db';
    final factory = databaseFactoryFfi;
    var db = await CatalogStore.open(factory, path);
    var store = CatalogStore(db);
    await store.saveCollection(
      CollectionRecord(id: 'a', name: 'Coins', customFields: {'Mint': ''}),
    );
    await store.saveItem(
      CatalogItem(id: 'old', collectionId: 'a', name: 'Legacy'),
    );
    await db.execute('ALTER TABLE items DROP COLUMN custom_fields');
    await db.execute('PRAGMA user_version = 2');
    await db.close();
    db = await CatalogStore.open(factory, path);
    store = CatalogStore(db);
    expect((await store.items()).single.customFields, isEmpty);
    await store.saveCollection(CollectionRecord(id: 'b', name: 'Shells'));
    await store.saveItem(
      CatalogItem(
        id: 'new',
        collectionId: 'b',
        name: 'Conch',
        notes: 'Ocean 100%',
        tags: ['Beach'],
        condition: ItemCondition.good,
        acquiredAt: DateTime.utc(2024, 2, 29),
        declaredValueMinor: 1234,
        photoRefs: ['photos/owned.image'],
        customFields: {'Origin': 'Pacific'},
      ),
    );
    await db.close();
    db = await CatalogStore.open(factory, path);
    addTearDown(() async {
      await db.close();
      await root.delete(recursive: true);
    });
    store = CatalogStore(db);
    for (final query in ['CONCH', 'beach', '100%', 'ORIGIN', 'pacific']) {
      expect((await store.items(search: query)).single.id, 'new');
    }
    expect(await store.items(search: 'Pacific', collectionId: 'a'), isEmpty);
    expect(
      await store.items(search: 'Pacific', condition: ItemCondition.poor),
      isEmpty,
    );
    expect(await store.items(search: '_'), isEmpty);
    final item = (await store.items(
      search: 'Pacific',
      collectionId: 'b',
      condition: ItemCondition.good,
    )).single;
    expect(item.declaredValueMinor, 1234);
    expect(item.acquiredAt, DateTime.utc(2024, 2, 29));
    expect(item.photoRefs, ['photos/owned.image']);
    expect(item.customFields, {'Origin': 'Pacific'});
  });
}
