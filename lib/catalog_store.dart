import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import 'catalog.dart';

/// Caller owns database lifetime and chooses the app-private database path.
final class CatalogStore {
  CatalogStore(this.db);
  final Database db;

  static Future<Database> open(DatabaseFactory factory, String path) =>
      factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 3,
          onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, version) async {
            await _createV1(db);
            await _upgradeV2(db);
            await _upgradeV3(db);
          },
          onUpgrade: (db, from, to) async {
            if (from < 2) await _upgradeV2(db);
            if (from < 3) await _upgradeV3(db);
          },
        ),
      );

  static Future<void> _createV1(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE collections (id TEXT PRIMARY KEY, name TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE items (id TEXT PRIMARY KEY, collection_id TEXT NOT NULL REFERENCES collections(id) ON DELETE CASCADE, name TEXT NOT NULL)',
    );
  }

  static Future<void> _upgradeV2(DatabaseExecutor db) async {
    await db.execute(
      "ALTER TABLE collections ADD COLUMN template TEXT NOT NULL DEFAULT ''",
    );
    await db.execute(
      "ALTER TABLE collections ADD COLUMN custom_fields TEXT NOT NULL DEFAULT '{}'",
    );
    await db.execute(
      "ALTER TABLE items ADD COLUMN condition TEXT NOT NULL DEFAULT 'unknown'",
    );
    await db.execute(
      "ALTER TABLE items ADD COLUMN location TEXT NOT NULL DEFAULT '[]'",
    );
    await db.execute(
      "ALTER TABLE items ADD COLUMN photo_refs TEXT NOT NULL DEFAULT '[]'",
    );
    await db.execute(
      "ALTER TABLE items ADD COLUMN tags TEXT NOT NULL DEFAULT '[]'",
    );
    await db.execute('ALTER TABLE items ADD COLUMN acquired_at TEXT');
    await db.execute(
      "ALTER TABLE items ADD COLUMN notes TEXT NOT NULL DEFAULT ''",
    );
    await db.execute(
      'ALTER TABLE items ADD COLUMN declared_value_minor INTEGER CHECK (declared_value_minor >= 0)',
    );
    await db.execute(
      'CREATE TABLE moves (id INTEGER PRIMARY KEY AUTOINCREMENT, item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE, from_path TEXT NOT NULL, to_path TEXT NOT NULL, moved_at TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE INDEX items_collection ON items(collection_id, name COLLATE NOCASE, id)',
    );
    await db.execute('CREATE INDEX moves_item ON moves(item_id, moved_at, id)');
  }

  static Future<void> _upgradeV3(DatabaseExecutor db) async {
    await db.execute(
      "ALTER TABLE items ADD COLUMN custom_fields TEXT NOT NULL DEFAULT '{}'",
    );
  }

  Future<void> saveCollection(CollectionRecord collection) async {
    await db.insert('collections', {
      'id': collection.id,
      'name': collection.name,
      'template': collection.template,
      'custom_fields': jsonEncode(collection.customFields),
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<void> updateCollection(CollectionRecord collection) async {
    final changed = await db.update(
      'collections',
      {
        'name': collection.name,
        'template': collection.template,
        'custom_fields': jsonEncode(collection.customFields),
      },
      where: 'id = ?',
      whereArgs: [collection.id],
    );
    if (changed != 1) {
      throw StateError('Collection not found: ${collection.id}');
    }
  }

  Future<List<CollectionRecord>> collections() async => [
    for (final row in await db.query(
      'collections',
      orderBy: 'name COLLATE NOCASE, id',
    ))
      CollectionRecord(
        id: row['id'] as String,
        name: row['name'] as String,
        template: row['template'] as String,
        customFields: (jsonDecode(row['custom_fields'] as String) as Map)
            .cast<String, String>(),
      ),
  ];

  /// Cascades to items and their moves; photo files remain caller-owned.
  Future<void> deleteCollection(String id) async {
    requireText(id, 'collection ID');
    await db.delete('collections', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> saveItem(CatalogItem item) async {
    await db.insert(
      'items',
      _itemColumns(item),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> updateItem(CatalogItem item) async {
    final columns = _itemColumns(item)..remove('id');
    final changed = await db.update(
      'items',
      columns,
      where: 'id = ? AND collection_id = ?',
      whereArgs: [item.id, item.collectionId],
    );
    if (changed != 1) {
      throw StateError('Item not found in collection: ${item.id}');
    }
  }

  Map<String, Object?> _itemColumns(CatalogItem item) => {
    'id': item.id,
    'collection_id': item.collectionId,
    'name': item.name,
    'condition': item.condition.name,
    'location': item.location.toJson(),
    'photo_refs': jsonEncode(item.photoRefs),
    'tags': jsonEncode(item.tags),
    'acquired_at': item.acquiredAt?.toUtc().toIso8601String(),
    'notes': item.notes,
    'declared_value_minor': item.declaredValueMinor,
    'custom_fields': jsonEncode(item.customFields),
  };

  CatalogItem _item(Map<String, Object?> row) => CatalogItem(
    id: row['id'] as String,
    collectionId: row['collection_id'] as String,
    name: row['name'] as String,
    condition: ItemCondition.values.byName(row['condition'] as String),
    location: LocationPath.fromJson(row['location'] as String),
    photoRefs: (jsonDecode(row['photo_refs'] as String) as List).cast<String>(),
    tags: (jsonDecode(row['tags'] as String) as List).cast<String>(),
    acquiredAt: row['acquired_at'] == null
        ? null
        : DateTime.parse(row['acquired_at'] as String),
    notes: row['notes'] as String,
    declaredValueMinor: row['declared_value_minor'] as int?,
    customFields: (jsonDecode(row['custom_fields'] as String) as Map)
        .cast<String, String>(),
  );

  Future<List<CatalogItem>> items({
    String? collectionId,
    ItemCondition? condition,
    String? nameContains,
    String? search,
  }) async {
    final clauses = <String>[];
    final args = <Object?>[];
    if (collectionId != null) {
      clauses.add('collection_id = ?');
      args.add(collectionId);
    }
    if (condition != null) {
      clauses.add('condition = ?');
      args.add(condition.name);
    }
    if (nameContains != null) {
      clauses.add('instr(lower(name), lower(?)) > 0');
      args.add(nameContains);
    }
    final result = [
      for (final row in await db.query(
        'items',
        where: clauses.isEmpty ? null : clauses.join(' AND '),
        whereArgs: args.isEmpty ? null : args,
        orderBy: 'name COLLATE NOCASE, id',
      ))
        _item(row),
    ];
    final query = search?.trim().toLowerCase() ?? '';
    return query.isEmpty
        ? result
        : result
              .where(
                (item) => [
                  item.name,
                  item.notes,
                  ...item.tags,
                  ...item.customFields.keys,
                  ...item.customFields.values,
                ].any((value) => value.toLowerCase().contains(query)),
              )
              .toList();
  }

  Future<void> deleteItem(String id) async {
    requireText(id, 'item ID');
    await db.delete('items', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> moveItem(String id, LocationPath to, DateTime at) async {
    requireText(id, 'item ID');
    await db.transaction((tx) async {
      final rows = await tx.query(
        'items',
        columns: ['location'],
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty) throw StateError('Item not found: $id');
      final from = LocationPath.fromJson(rows.single['location'] as String);
      await tx.update(
        'items',
        {'location': to.toJson()},
        where: 'id = ?',
        whereArgs: [id],
      );
      await tx.insert('moves', {
        'item_id': id,
        'from_path': from.toJson(),
        'to_path': to.toJson(),
        'moved_at': at.toUtc().toIso8601String(),
      });
    });
  }

  Future<List<ItemMove>> moves(String itemId) async {
    requireText(itemId, 'item ID');
    return [
      for (final row in await db.query(
        'moves',
        where: 'item_id = ?',
        whereArgs: [itemId],
        orderBy: 'moved_at, id',
      ))
        ItemMove(
          itemId: row['item_id'] as String,
          from: LocationPath.fromJson(row['from_path'] as String),
          to: LocationPath.fromJson(row['to_path'] as String),
          at: DateTime.parse(row['moved_at'] as String),
        ),
    ];
  }

  Future<CollectionStatistics> statistics(String collectionId) async {
    requireText(collectionId, 'collection ID');
    // ponytail: iterate minor units to catch int overflow; add currency grouping when multi-currency support exists.
    final rows = await db.query(
      'items',
      columns: ['declared_value_minor'],
      where: 'collection_id = ?',
      whereArgs: [collectionId],
    );
    var count = 0;
    var total = 0;
    for (final row in rows) {
      final value = row['declared_value_minor'] as int?;
      if (value != null) {
        if (value > 9223372036854775807 - total) {
          throw StateError('Declared total exceeds int64');
        }
        total += value;
        count++;
      }
    }
    return CollectionStatistics(rows.length, count, rows.length - count, total);
  }
}
