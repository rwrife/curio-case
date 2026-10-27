import 'package:curio_case/catalog.dart';
import 'package:curio_case/catalog_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;

  test(
    'CRUD, filters, moves, ordering, declared totals, and cascade deletion',
    () async {
      final db = await CatalogStore.open(factory, inMemoryDatabasePath);
      final store = CatalogStore(db);
      addTearDown(db.close);
      await store.saveCollection(
        CollectionRecord(
          id: 'b',
          name: 'Zeta',
          template: 'coins',
          customFields: {'grade': 'A'},
        ),
      );
      await store.saveCollection(CollectionRecord(id: 'a', name: 'Alpha'));
      expect((await store.collections()).map((c) => c.id), ['a', 'b']);
      await store.updateCollection(
        CollectionRecord(id: 'b', name: 'Beta', customFields: {'grade': 'B'}),
      );
      expect((await store.collections()).last.customFields['grade'], 'B');
      final old = LocationPath(['Shelf', 'Box 1']);
      await store.saveItem(
        CatalogItem(
          id: '2',
          collectionId: 'b',
          name: 'amber',
          condition: ItemCondition.good,
          location: old,
          photoRefs: ['photos/a.jpg'],
          tags: ['fossil'],
          declaredValueMinor: 125,
          notes: 'mine',
        ),
      );
      await store.saveItem(
        CatalogItem(
          id: '1',
          collectionId: 'b',
          name: 'Amber',
          acquiredAt: DateTime.utc(2020),
          declaredValueMinor: 75,
        ),
      );
      await store.saveItem(
        CatalogItem(id: '3', collectionId: 'a', name: 'Zebra'),
      );
      expect((await store.items(collectionId: 'b')).map((i) => i.id), [
        '1',
        '2',
      ]);
      expect(
        (await store.items(
          collectionId: 'b',
          condition: ItemCondition.good,
          nameContains: 'AM',
        )).single.photoRefs,
        ['photos/a.jpg'],
      );
      expect((await store.items(nameContains: 'z')).single.id, '3');
      await store.updateItem(
        CatalogItem(
          id: '2',
          collectionId: 'b',
          name: 'Aster',
          condition: ItemCondition.fair,
          declaredValueMinor: 125,
        ),
      );
      expect(
        (await store.items(
          collectionId: 'b',
          condition: ItemCondition.fair,
        )).single.name,
        'Aster',
      );
      final moved = DateTime.utc(2010, 2, 3);
      await store.moveItem('1', LocationPath(['Cabinet']), moved);
      await store.moveItem('1', LocationPath(['Cabinet', 'Tray']), moved);
      expect((await store.moves('1')).map((m) => m.to.segments.join('/')), [
        'Cabinet',
        'Cabinet/Tray',
      ]);
      expect((await store.moves('1')).first.at, moved);
      expect(
        (await store.items(collectionId: 'b')).first.location,
        LocationPath(['Cabinet', 'Tray']),
      );
      final stats = await store.statistics('b');
      expect(
        [
          stats.itemCount,
          stats.withDeclaredValue,
          stats.withoutDeclaredValue,
          stats.declaredTotalMinor,
        ],
        [2, 2, 0, 200],
      );
      await store.deleteItem('2');
      expect((await store.statistics('b')).declaredTotalMinor, 75);
      await store.deleteCollection('b');
      expect(await store.items(collectionId: 'b'), isEmpty);
      expect(await store.moves('1'), isEmpty);
      expect((await store.items()).single.id, '3');
    },
  );

  test('v1 migration preserves data and adds defaults', () async {
    final path =
        '${await factory.getDatabasesPath()}/curio-migration-${DateTime.now().microsecondsSinceEpoch}.db';
    final legacy = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE collections (id TEXT PRIMARY KEY, name TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE items (id TEXT PRIMARY KEY, collection_id TEXT NOT NULL REFERENCES collections(id) ON DELETE CASCADE, name TEXT NOT NULL)',
          );
          await db.insert('collections', {'id': 'c', 'name': 'Old'});
          await db.insert('items', {
            'id': 'i',
            'collection_id': 'c',
            'name': 'Legacy',
          });
        },
      ),
    );
    await legacy.close();
    try {
      final db = await CatalogStore.open(factory, path);
      final store = CatalogStore(db);
      expect((await store.items()).single.condition, ItemCondition.unknown);
      expect((await store.items()).single.location.segments, isEmpty);
      expect((await store.collections()).single.customFields, isEmpty);
      await store.moveItem('i', LocationPath(['Box']), DateTime.utc(2000));
      expect((await store.moves('i')).single.from.segments, isEmpty);
      await db.close();
    } finally {
      await factory.deleteDatabase(path);
    }
  });

  test('invalid domain values, foreign keys, and failed moves reject without damage', () async {
    expect(() => LocationPath(['..']), throwsArgumentError);
    expect(() => LocationPath(['a/b']), throwsArgumentError);
    expect(
      () => CatalogItem(
        id: 'i',
        collectionId: 'c',
        name: 'X',
        photoRefs: ['/tmp/private.jpg'],
      ),
      throwsArgumentError,
    );
    expect(
      () => CatalogItem(
        id: 'i',
        collectionId: 'c',
        name: 'X',
        photoRefs: ['../secret.jpg'],
      ),
      throwsArgumentError,
    );
    expect(
      () => CatalogItem(
        id: 'i',
        collectionId: 'c',
        name: 'X',
        declaredValueMinor: -1,
      ),
      throwsArgumentError,
    );
    final db = await CatalogStore.open(factory, inMemoryDatabasePath);
    addTearDown(db.close);
    final store = CatalogStore(db);
    await expectLater(
      store.saveItem(CatalogItem(id: 'i', collectionId: 'absent', name: 'X')),
      throwsA(isA<Exception>()),
    );
    await expectLater(
      store.moveItem('absent', LocationPath(['Box']), DateTime.utc(2000)),
      throwsStateError,
    );
    expect(await store.items(), isEmpty);
    expect(await store.moves('absent'), isEmpty);
    await store.saveCollection(CollectionRecord(id: 'c', name: 'C'));
    await store.saveItem(CatalogItem(id: 'i', collectionId: 'c', name: 'X'));
    await expectLater(
      store.saveItem(
        CatalogItem(id: 'i', collectionId: 'c', name: 'Duplicate'),
      ),
      throwsA(isA<Exception>()),
    );
    expect((await store.items()).single.name, 'X');
    expect((await store.statistics('c')).withoutDeclaredValue, 1);
  });
}
