import 'dart:convert';

/// IDs are caller-generated and stable across exports and imports.
final class CollectionRecord {
  CollectionRecord({
    required this.id,
    required this.name,
    this.template = '',
    Map<String, String> customFields = const {},
  }) : customFields = Map.unmodifiable(customFields) {
    requireText(id, 'collection ID');
    requireText(name, 'collection name');
    for (final entry in customFields.entries) {
      requireText(entry.key, 'field name');
    }
  }

  final String id;
  final String name;
  final String template;
  final Map<String, String> customFields;
}

enum ItemCondition { mint, good, fair, poor, unknown }

final class LocationPath {
  LocationPath(Iterable<String> segments)
    : segments = List.unmodifiable(segments) {
    for (final segment in this.segments) {
      requireText(segment, 'location segment');
      if (segment == '.' ||
          segment == '..' ||
          segment.contains('/') ||
          segment.contains('\\')) {
        throw ArgumentError.value(segment, 'location segment');
      }
    }
  }

  final List<String> segments;

  String toJson() => jsonEncode(segments);
  static LocationPath fromJson(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! List || decoded.any((element) => element is! String)) {
      throw FormatException('Invalid location path');
    }
    return LocationPath(decoded.cast<String>());
  }

  @override
  bool operator ==(Object other) =>
      other is LocationPath && toJson() == other.toJson();
  @override
  int get hashCode => Object.hashAll(segments);
}

final class CatalogItem {
  CatalogItem({
    required this.id,
    required this.collectionId,
    required this.name,
    this.condition = ItemCondition.unknown,
    LocationPath? location,
    Iterable<String> photoRefs = const [],
    Iterable<String> tags = const [],
    this.acquiredAt,
    this.notes = '',
    this.declaredValueMinor,
    Map<String, String> customFields = const {},
  }) : location = location ?? LocationPath([]),
       photoRefs = List.unmodifiable(photoRefs),
       tags = List.unmodifiable(tags),
       customFields = Map.unmodifiable(customFields) {
    for (final key in customFields.keys) {
      requireText(key, 'field name');
    }
    requireText(id, 'item ID');
    requireText(collectionId, 'collection ID');
    requireText(name, 'item name');
    if (declaredValueMinor != null && declaredValueMinor! < 0) {
      throw ArgumentError.value(declaredValueMinor, 'declaredValueMinor');
    }
    for (final ref in this.photoRefs) {
      requireRelativePhoto(ref);
    }
    for (final tag in this.tags) {
      requireText(tag, 'tag');
    }
  }

  final String id;
  final String collectionId;
  final String name;
  final ItemCondition condition;
  final LocationPath location;
  final List<String> photoRefs;
  final List<String> tags;
  final DateTime? acquiredAt;
  final String notes;

  /// User-declared amount, not an appraisal. Currency is set by the caller.
  final int? declaredValueMinor;
  final Map<String, String> customFields;
}

final class ItemMove {
  ItemMove({
    required this.itemId,
    required this.from,
    required this.to,
    required this.at,
  }) {
    requireText(itemId, 'item ID');
  }
  final String itemId;
  final LocationPath from;
  final LocationPath to;
  final DateTime at;
}

final class CollectionStatistics {
  const CollectionStatistics(
    this.itemCount,
    this.withDeclaredValue,
    this.withoutDeclaredValue,
    this.declaredTotalMinor,
  );
  final int itemCount;
  final int withDeclaredValue;
  final int withoutDeclaredValue;

  /// Sum of user-declared minor units; never an appraisal.
  final int declaredTotalMinor;
}

void requireText(String value, String field) {
  if (value.trim().isEmpty || value != value.trim()) {
    throw ArgumentError.value(value, field);
  }
}

void requireRelativePhoto(String ref) {
  requireText(ref, 'photo ref');
  final segments = ref.split(RegExp(r'[/\\]'));
  if (ref.startsWith('/') ||
      ref.contains('\\') ||
      ref.contains(':') ||
      segments.any((s) => s.isEmpty || s == '.' || s == '..')) {
    throw ArgumentError.value(
      ref,
      'photo ref',
      'Must be relative to app documents directory',
    );
  }
}
