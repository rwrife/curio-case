import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'catalog.dart';
import 'catalog_backup.dart';
import 'catalog_store.dart';

String newCatalogId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

/// Only relative references to copies owned by this application are persisted.
class PhotoLibrary {
  PhotoLibrary(this.root);
  final Directory root;

  Future<String?> attach(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source);
    if (picked == null) return null;
    return importBytes(await picked.readAsBytes());
  }

  Future<String> importBytes(List<int> bytes) async {
    final ref = 'photos/${newCatalogId()}.image';
    final destination = file(ref);
    await destination.parent.create(recursive: true);
    await destination.writeAsBytes(bytes, flush: true);
    return ref;
  }

  File file(String ref) {
    requireRelativePhoto(ref);
    return File('${root.path}/$ref');
  }

  Future<void> discard(Iterable<String> refs) async {
    for (final ref in refs) {
      final target = file(ref);
      if (await target.exists()) await target.delete();
    }
  }
}

class CatalogSession extends ChangeNotifier {
  CatalogSession(this.store, this.photos);
  final CatalogStore store;
  final PhotoLibrary photos;
  List<CollectionRecord> collections = [];
  List<CatalogItem> items = [];

  static Future<CatalogSession> open() async {
    final root = await getApplicationSupportDirectory();
    await root.create(recursive: true);
    final DatabaseFactory factory;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      factory = databaseFactoryFfi;
    } else {
      factory = mobile.databaseFactory;
    }
    final db = await CatalogStore.open(factory, '${root.path}/catalog.db');
    final session = CatalogSession(CatalogStore(db), PhotoLibrary(root));
    await session.reload();
    return session;
  }

  Future<void> reload() async {
    collections = await store.collections();
    items = await store.items();
    notifyListeners();
  }

  Future<void> saveCollection(
    CollectionRecord record, {
    required bool isNew,
  }) async {
    if (isNew) {
      await store.saveCollection(record);
    } else {
      await store.updateCollection(record);
    }
    await reload();
  }

  Future<void> createLocation(String collectionId, LocationPath path) async {
    await store.createLocation(collectionId, path);
    notifyListeners();
  }

  Future<void> moveItem(CatalogItem item, LocationPath path) async {
    await store.moveItem(item.id, path, DateTime.now().toUtc());
    await reload();
  }

  Future<void> saveItem(CatalogItem item, {required bool isNew}) async {
    final old = items.where((value) => value.id == item.id).firstOrNull;
    if (isNew) {
      await store.saveItem(item);
    } else {
      await store.updateItem(item);
    }
    await reload();
    await _discardUnreferenced(old?.photoRefs ?? []);
  }

  Future<void> deleteItem(CatalogItem item) async {
    await store.deleteItem(item.id);
    await reload();
    await _discardUnreferenced(item.photoRefs);
  }

  Future<void> deleteCollection(CollectionRecord collection) async {
    final refs = items
        .where((i) => i.collectionId == collection.id)
        .expand((i) => i.photoRefs)
        .toList();
    await store.deleteCollection(collection.id);
    await reload();
    await _discardUnreferenced(refs);
  }

  Future<void> _discardUnreferenced(Iterable<String> refs) async {
    final used = items.expand((i) => i.photoRefs).toSet();
    // A failed cleanup must not report a committed catalog change as failed.
    try {
      await photos.discard(refs.where((ref) => !used.contains(ref)));
    } on FileSystemException catch (error) {
      debugPrint('Photo cleanup deferred: ${error.osError?.errorCode}');
    }
  }

  Future<void> exportJson({required bool includePhotos}) async {
    final payload = await CatalogBackup(
      store,
      photos.root,
    ).exportJson(includePhotos: includePhotos);
    await FilePicker.saveFile(
      fileName: 'curio-case-backup.json',
      bytes: Uint8List.fromList(utf8.encode(payload)),
    );
  }

  Future<void> exportCsv() async {
    final csv = CatalogBackup.exportCsv(collections, items);
    await FilePicker.saveFile(
      fileName: 'curio-case-catalog.csv',
      bytes: Uint8List.fromList(utf8.encode(csv)),
    );
  }

  Future<void> importJson() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (picked == null) return;
    final length = picked.lengthSync() ?? await picked.length();
    if (length == null || length > 400 * 1024 * 1024) {
      throw const FormatException('Backup too large or size unavailable');
    }
    final source = utf8.decode(await picked.readAsBytes());
    await CatalogBackup(store, photos.root).restoreJson(source);
    await reload();
  }
}
