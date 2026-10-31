import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common/sqlite_api.dart';

import 'catalog.dart';
import 'catalog_store.dart';

/// Portable, versioned snapshot. File selection and user confirmation belong to UI.
final class CatalogBackup {
  CatalogBackup(this.store, this.photoRoot);
  final CatalogStore store;
  final Directory photoRoot;

  static const _tables = ['collections', 'items', 'locations', 'moves'];
  static const _maxBytes = 200 * 1024 * 1024;

  Future<String> exportJson({bool includePhotos = true}) async {
    final tables = await store.db.transaction(
      (tx) async => {
        for (final name in _tables)
          name: await tx.query(name, orderBy: 'rowid'),
      },
    );
    final photos = <String, String>{};
    if (includePhotos) {
      for (final row in tables['items']!) {
        for (final ref in (jsonDecode(
          row['photo_refs'] as String,
        ) as List).cast<String>()) {
          requireRelativePhoto(ref);
          final file = _photo(ref);
          if (!await file.exists()) {
            throw FormatException('Missing photo: $ref');
          }
          final bytes = await file.readAsBytes();
          if (bytes.length > _maxBytes) {
            throw const FormatException('Photo too large');
          }
          photos[ref] = base64Encode(bytes);
        }
      }
    } else if (tables['items']!.any(
      (row) => (jsonDecode(row['photo_refs'] as String) as List).isNotEmpty,
    )) {
      // Explicitly strip references: a photo-free backup must remain importable.
      tables['items'] = [
        for (final row in tables['items']!) {...row, 'photo_refs': '[]'},
      ];
    }
    return jsonEncode({'version': 1, ...tables, 'photos': photos});
  }

  Future<void> restoreJson(String source) async {
    if (utf8.encode(source).length > _maxBytes * 2) {
      throw const FormatException('Backup too large');
    }
    final dynamic decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
      throw const FormatException('Unsupported backup version');
    }
    final data = <String, List<Map<String, Object?>>>{};
    for (final table in _tables) {
      final rows = decoded[table];
      if (rows is! List || rows.length > 100000) {
        throw FormatException('Invalid $table');
      }
      data[table] = [
        for (final row in rows)
          if (row is Map<String, dynamic>)
            row.cast<String, Object?>()
          else
            throw FormatException('Invalid $table row'),
      ];
    }
    final rawPhotos = decoded['photos'];
    if (rawPhotos is! Map<String, dynamic>) {
      throw const FormatException('Invalid photos');
    }
    final photos = <String, List<int>>{};
    var total = 0;
    for (final entry in rawPhotos.entries) {
      _photo(entry.key);
      if (entry.value is! String) {
        throw const FormatException('Invalid photo payload');
      }
      final bytes = base64Decode(entry.value as String);
      total += bytes.length;
      if (total > _maxBytes) throw const FormatException('Photos too large');
      photos[entry.key] = bytes;
    }
    _validate(data, photos.keys.toSet());

    // Save old bytes before entering transaction. A failed disk write restores both
    // DB (SQLite rollback) and photo files. No cleanup of old files until commit.
    final previous = <String, List<int>?>{};
    final written = <String>[];
    try {
      for (final ref in photos.keys) {
        final file = _photo(ref);
        previous[ref] = await file.exists() ? await file.readAsBytes() : null;
      }
      await store.db.transaction((tx) async {
        for (final table in _tables.reversed) {
          await tx.delete(table);
        }
        for (final table in _tables) {
          for (final row in data[table]!) {
            await tx.insert(
              table,
              row,
              conflictAlgorithm: ConflictAlgorithm.abort,
            );
          }
        }
        for (final entry in photos.entries) {
          final file = _photo(entry.key);
          await file.parent.create(recursive: true);
          written.add(entry.key);
          await file.writeAsBytes(entry.value, flush: true);
        }
      });
    } catch (_) {
      for (final ref in written.reversed) {
        final file = _photo(ref);
        if (previous[ref] case final bytes?) {
          await file.writeAsBytes(bytes, flush: true);
        } else if (await file.exists()) {
          await file.delete();
        }
      }
      rethrow;
    }
    // ponytail: orphaned old photo files remain after restore; prune via explicit maintenance later.
  }

  File _photo(String ref) {
    requireRelativePhoto(ref);
    if (!RegExp(r'^photos/[^/]+$').hasMatch(ref)) {
      throw FormatException('Invalid photo ref: $ref');
    }
    return File('${photoRoot.path}/$ref');
  }

  static void _validate(
    Map<String, List<Map<String, Object?>>> data,
    Set<String> photos,
  ) {
    final collections = <String>{};
    for (final row in data['collections']!) {
      _keys(row, {'id', 'name', 'template', 'custom_fields'});
      final record = CollectionRecord(
        id: row['id'] as String,
        name: row['name'] as String,
        template: row['template'] as String,
        customFields: _fields(row['custom_fields']),
      );
      if (!collections.add(record.id)) {
        throw const FormatException('Duplicate collection ID');
      }
    }
    final items = <String>{};
    final referenced = <String>{};
    for (final row in data['items']!) {
      _keys(row, {
        'id',
        'collection_id',
        'name',
        'condition',
        'location',
        'photo_refs',
        'tags',
        'acquired_at',
        'notes',
        'declared_value_minor',
        'custom_fields',
      });
      final item = CatalogItem(
        id: row['id'] as String,
        collectionId: row['collection_id'] as String,
        name: row['name'] as String,
        condition: ItemCondition.values.byName(row['condition'] as String),
        location: LocationPath.fromJson(row['location'] as String),
        photoRefs: (jsonDecode(row['photo_refs'] as String) as List)
            .cast<String>(),
        tags: (jsonDecode(row['tags'] as String) as List).cast<String>(),
        acquiredAt: row['acquired_at'] == null
            ? null
            : DateTime.parse(row['acquired_at'] as String),
        notes: row['notes'] as String,
        declaredValueMinor: row['declared_value_minor'] as int?,
        customFields: _fields(row['custom_fields']),
      );
      if (!items.add(item.id)) throw const FormatException('Duplicate item ID');
      if (!collections.contains(item.collectionId)) {
        throw const FormatException('Orphan item');
      }
      referenced.addAll(item.photoRefs);
    }
    if (!photos.containsAll(referenced) || !referenced.containsAll(photos)) {
      throw const FormatException('Missing or unreferenced photo payload');
    }
    final locations = <String>{};
    for (final row in data['locations']!) {
      _keys(row, {'collection_id', 'path'});
      final id = row['collection_id'] as String;
      final path = LocationPath.fromJson(row['path'] as String);
      if (!collections.contains(id) ||
          path.segments.isEmpty ||
          !locations.add('$id:${path.toJson()}')) {
        throw const FormatException('Invalid or duplicate location');
      }
    }
    final moveIds = <int>{};
    for (final row in data['moves']!) {
      _keys(row, {'id', 'item_id', 'from_path', 'to_path', 'moved_at'});
      final id = row['id'] as int;
      if (id <= 0 || !moveIds.add(id) || !items.contains(row['item_id'])) {
        throw const FormatException('Invalid move ID');
      }
      ItemMove(
        itemId: row['item_id'] as String,
        from: LocationPath.fromJson(row['from_path'] as String),
        to: LocationPath.fromJson(row['to_path'] as String),
        at: DateTime.parse(row['moved_at'] as String),
      );
    }
  }

  static Map<String, String> _fields(Object? source) =>
      (jsonDecode(source as String) as Map).cast<String, String>();

  static void _keys(Map<String, Object?> row, Set<String> expected) {
    if (row.keys.toSet().difference(expected).isNotEmpty ||
        expected.difference(row.keys.toSet()).isNotEmpty) {
      throw const FormatException('Invalid backup columns');
    }
  }

  static String exportCsv(
    List<CollectionRecord> collections,
    List<CatalogItem> items,
  ) {
    String cell(Object? value) {
      final text = '$value';
      final safe = RegExp(r'^\s*[=+@\-\t\r]').hasMatch(text) ? "'$text" : text;
      return '"${safe.replaceAll('"', '""')}"';
    }

    final names = {for (final c in collections) c.id: c.name};
    final rows = <List<Object?>>[
      [
        'Collection',
        'Item',
        'Condition',
        'Location',
        'Tags',
        'Notes',
        'Acquired UTC',
        'Declared minor units',
        'Custom fields',
      ],
      for (final item in items)
        [
          names[item.collectionId] ?? '',
          item.name,
          item.condition.name,
          item.location.label,
          item.tags.join('; '),
          item.notes,
          item.acquiredAt?.toUtc().toIso8601String() ?? '',
          item.declaredValueMinor ?? '',
          jsonEncode(item.customFields),
        ],
    ];
    return '\uFEFF${rows.map((row) => row.map(cell).join(',')).join('\r\n')}\r\n';
  }
}
