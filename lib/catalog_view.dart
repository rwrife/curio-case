import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'adaptive.dart';
import 'catalog.dart';
import 'catalog_session.dart';

class CatalogView extends StatefulWidget {
  const CatalogView({super.key, required this.session, required this.controls});
  final CatalogSession session;
  final AdaptiveControls controls;
  @override
  State<CatalogView> createState() => _CatalogViewState();
}

class _CatalogViewState extends State<CatalogView> {
  final search = TextEditingController();
  final searchFocus = FocusNode();
  final locationInput = TextEditingController();
  final moveInput = TextEditingController();
  String collection = '';
  LocationPath? locationFilter;
  String condition = '';
  String? error;
  Widget? editor;
  String? expandedItemId;
  bool busy = false;
  CatalogSession get session => widget.session;
  AdaptiveControls get ui => widget.controls;

  @override
  void initState() {
    super.initState();
    session.addListener(refresh);
  }

  void refresh() {
    if (mounted) {
      setState(() {
        if (!session.collections.any((c) => c.id == collection)) {
          collection = '';
          locationFilter = null;
        }
      });
    }
  }

  @override
  void dispose() {
    session.removeListener(refresh);
    search.dispose();
    searchFocus.dispose();
    locationInput.dispose();
    moveInput.dispose();
    super.dispose();
  }

  Future<void> action(Future<void> Function() work) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await work();
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not save the change. Please try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void editCollection([CollectionRecord? record]) {
    setState(
      () => editor = CollectionEditor(
        key: UniqueKey(),
        ui: ui,
        record: record,
        onCancel: closeEditor,
        onSave: (value) async {
          await session.saveCollection(value, isNew: record == null);
          if (mounted) {
            setState(() {
              collection = value.id;
              editor = null;
            });
          }
        },
      ),
    );
  }

  void closeEditor() => setState(() => editor = null);
  void editItem(CollectionRecord parent, [CatalogItem? item]) {
    setState(
      () => editor = ItemEditor(
        key: UniqueKey(),
        ui: ui,
        session: session,
        collection: parent,
        item: item,
        onCancel: closeEditor,
        onSave: (value) async {
          await session.saveItem(value, isNew: item == null);
          if (mounted) closeEditor();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (editor != null) return editor!;
    final parent = session.collections
        .where((c) => c.id == collection)
        .firstOrNull;
    final query = search.text.trim().toLowerCase();
    final results = session.items
        .where(
          (i) =>
              (collection.isEmpty || i.collectionId == collection) &&
              (locationFilter == null ||
                  (locationFilter!.segments.isEmpty
                      ? i.location.segments.isEmpty
                      : i.location.isWithin(locationFilter!))) &&
              (condition.isEmpty || i.condition.name == condition) &&
              (query.isEmpty ||
                  [
                    i.name,
                    i.notes,
                    ...i.tags,
                    ...i.customFields.keys,
                    ...i.customFields.values,
                  ].any((s) => s.toLowerCase().contains(query))),
        )
        .toList();
    final filters = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ui.desktop)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Ctrl+F search · Esc clears search'),
          ),
        ui.field(
          'Search items',
          search,
          focusNode: searchFocus,
          onChanged: (_) => setState(() {}),
        ),
        ui.choice(
          context,
          'Collection filter',
          collection,
          {
            '': 'All collections',
            for (final c in session.collections) c.id: c.name,
          },
          (v) => setState(() {
            collection = v;
            locationFilter = null;
          }),
        ),
        ui.choice(context, 'Condition filter', condition, {
          '': 'All conditions',
          for (final c in ItemCondition.values) c.name: c.name,
        }, (v) => setState(() => condition = v)),
        ui.button('Create collection', busy ? null : () => editCollection()),
        if (session.collections.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Collections', style: TextStyle(fontSize: 20)),
          ),
          for (final c in session.collections)
            ui.button(
              '${c.name} (${session.items.where((i) => i.collectionId == c.id).length})',
              () => setState(() {
                collection = c.id;
                locationFilter = null;
              }),
              key: Key('collection-${c.id}'),
            ),
        ],
        if (parent != null) ...[
          ui.button(
            'Edit collection',
            busy ? null : () => editCollection(parent),
          ),
          ui.button(
            'Delete collection',
            busy
                ? null
                : () async {
                    if (!await ui.confirm(
                      context,
                      'Delete collection?',
                      'Delete ${parent.name} and all its items and photos?',
                    )) {
                      return;
                    }
                    await action(() async {
                      await session.deleteCollection(parent);
                      collection = '';
                    });
                  },
          ),
          ui.button('Add item', busy ? null : () => editItem(parent)),
          const Text('Locations', style: TextStyle(fontSize: 20)),
          ui.field('New location path (Shelf / Box)', locationInput),
          ui.button(
            'Create location',
            busy
                ? null
                : () async {
                    try {
                      final path = LocationPath.parse(locationInput.text);
                      await action(
                        () => session.createLocation(parent.id, path),
                      );
                      if (mounted && error == null) locationInput.clear();
                    } on ArgumentError {
                      setState(() => error = 'Enter a valid location path.');
                    }
                  },
          ),
          FutureBuilder<List<LocationPath>>(
            future: session.store.locations(parent.id),
            builder: (context, snapshot) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ui.button(
                  'All locations',
                  () => setState(() => locationFilter = null),
                ),
                ui.button(
                  'Unfiled',
                  () => setState(() => locationFilter = LocationPath([])),
                ),
                for (final path in snapshot.data ?? <LocationPath>[])
                  ui.button(
                    'Browse ${path.label}',
                    () => setState(() => locationFilter = path),
                  ),
                if (snapshot.hasError) const Text('Could not load locations.'),
              ],
            ),
          ),
          if (locationFilter != null) Text('Showing: ${locationFilter!.label}'),
          const Text('Collection summary', style: TextStyle(fontSize: 20)),
          Builder(
            builder: (context) {
              final stats = CollectionStatistics(
                session.items
                    .where((i) => i.collectionId == parent.id)
                    .toList(),
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Items: ${stats.itemCount}'),
                  Text(
                    'Declared total (user-entered, not appraisal): ${stats.declaredTotalMinor ~/ 100}.${(stats.declaredTotalMinor % 100).toString().padLeft(2, '0')}',
                  ),
                  Text(
                    'Missing declared value: ${stats.withoutDeclaredValue} of ${stats.itemCount}',
                  ),
                  for (final entry in stats.conditions.entries)
                    Text('${entry.key.name}: ${entry.value}'),
                  for (final year
                      in stats.acquisitionsByYear.keys.toList()..sort())
                    Text('Acquired $year: ${stats.acquisitionsByYear[year]}'),
                ],
              );
            },
          ),
        ],
        if (parent == null && session.collections.isNotEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Select a collection to add or manage items.'),
          ),
      ],
    );
    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null) Text(error!),
        if (session.collections.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No collections yet. Create your first collection.'),
          )
        else if (results.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No items found. Add an item or change your search.'),
          ),
        for (final item in results)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF888888)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ui.button(
                      item.name,
                      () => setState(
                        () => expandedItemId = expandedItemId == item.id
                            ? null
                            : item.id,
                      ),
                      key: Key('item-${item.id}'),
                    ),
                    Text(
                      '${session.collections.firstWhere((c) => c.id == item.collectionId).name} · ${item.condition.name}',
                    ),
                    Text('Location: ${item.location.label}'),
                    if (item.tags.isNotEmpty) Text(item.tags.join(', ')),
                    Text(
                      item.photoRefs.isEmpty
                          ? 'No photo'
                          : '${item.photoRefs.length} photo(s)',
                    ),
                    if (expandedItemId == item.id) ...[
                      ui.field('Move to path (Shelf / Box)', moveInput),
                      ui.button(
                        'Move ${item.name}',
                        busy
                            ? null
                            : () async {
                                try {
                                  final path = LocationPath.parse(
                                    moveInput.text,
                                  );
                                  await action(
                                    () => session.moveItem(item, path),
                                  );
                                  if (mounted && error == null) {
                                    moveInput.clear();
                                  }
                                } on ArgumentError {
                                  setState(
                                    () =>
                                        error = 'Enter a valid location path.',
                                  );
                                }
                              },
                      ),
                      FutureBuilder<List<ItemMove>>(
                        future: session.store.moves(item.id),
                        builder: (context, snapshot) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final move in snapshot.data ?? <ItemMove>[])
                              Text(
                                'Moved ${move.at.toUtc().toIso8601String().substring(0, 10)}: ${move.from.label} → ${move.to.label}',
                              ),
                            if (snapshot.hasError)
                              const Text('Could not load move history.'),
                          ],
                        ),
                      ),
                      if (item.notes.isNotEmpty) Text(item.notes),
                      if (item.acquiredAt != null)
                        Text(
                          'Acquired: ${item.acquiredAt!.toIso8601String().substring(0, 10)}',
                        ),
                      if (item.declaredValueMinor != null)
                        Text(
                          'Declared value: ${item.declaredValueMinor! ~/ 100}.${(item.declaredValueMinor! % 100).toString().padLeft(2, '0')}',
                        ),
                      for (final entry in item.customFields.entries)
                        Text('${entry.key}: ${entry.value}'),
                      for (final ref in item.photoRefs)
                        Image.file(
                          session.photos.file(ref),
                          height: 160,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) =>
                              const Text('Photo unavailable'),
                        ),
                    ],
                    Wrap(
                      spacing: 8,
                      children: [
                        ui.button(
                          'Edit ${item.name}',
                          busy
                              ? null
                              : () => editItem(
                                  session.collections.firstWhere(
                                    (c) => c.id == item.collectionId,
                                  ),
                                  item,
                                ),
                        ),
                        ui.button(
                          'Delete ${item.name}',
                          busy
                              ? null
                              : () async {
                                  if (!await ui.confirm(
                                    context,
                                    'Delete item?',
                                    'Delete ${item.name} and its photos?',
                                  )) {
                                    return;
                                  }
                                  await action(() => session.deleteItem(item));
                                },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
    final content = LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 300,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: filters,
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: list,
                ),
              ),
            ],
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [filters, list],
          ),
        );
      },
    );
    if (!ui.desktop) return content;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            searchFocus.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (search.text.isNotEmpty) {
            search.clear();
            setState(() {});
          } else {
            searchFocus.unfocus();
          }
        },
      },
      child: Focus(autofocus: true, child: content),
    );
  }
}

class CollectionEditor extends StatefulWidget {
  const CollectionEditor({
    super.key,
    required this.ui,
    this.record,
    required this.onSave,
    required this.onCancel,
  });
  final AdaptiveControls ui;
  final CollectionRecord? record;
  final Future<void> Function(CollectionRecord) onSave;
  final VoidCallback onCancel;
  @override
  State<CollectionEditor> createState() => _CollectionEditorState();
}

class _CollectionEditorState extends State<CollectionEditor> {
  late final name = TextEditingController(text: widget.record?.name);
  late final fields = TextEditingController(
    text: widget.record?.customFields.keys.join(', '),
  );
  bool busy = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    fields.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && !busy) widget.onCancel();
    },
    child: EditorLayout(
      children: [
        Text(
          widget.record == null ? 'Create collection' : 'Edit collection',
          style: const TextStyle(fontSize: 24),
        ),
        widget.ui.field('Collection name', name),
        widget.ui.field('Custom text fields (comma separated)', fields),
        const Text(
          'Define field names here; enter each item’s values in its editor. Removing a field hides it from new items; existing values remain available.',
        ),
        if (error != null) Text(error!),
        Wrap(
          spacing: 12,
          children: [
            widget.ui.button(
              'Save collection',
              busy
                  ? null
                  : () async {
                      if (name.text.trim().isEmpty) {
                        setState(() => error = 'Enter a collection name.');
                        return;
                      }
                      final keys = fields.text
                          .split(',')
                          .map((s) => s.trim())
                          .where((s) => s.isNotEmpty)
                          .toList();
                      if (keys.toSet().length != keys.length) {
                        setState(
                          () => error = 'Custom field names must be unique.',
                        );
                        return;
                      }
                      setState(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await widget.onSave(
                          CollectionRecord(
                            id: widget.record?.id ?? newCatalogId(),
                            name: name.text.trim(),
                            template: widget.record?.template ?? '',
                            customFields: {
                              for (final key in keys)
                                key: widget.record?.customFields[key] ?? '',
                            },
                          ),
                        );
                      } catch (_) {
                        if (mounted) {
                          setState(
                            () => error =
                                'Could not save collection. Please try again.',
                          );
                        }
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    },
            ),
            widget.ui.button('Cancel', busy ? null : widget.onCancel),
          ],
        ),
      ],
    ),
  );
}

class EditorLayout extends StatelessWidget {
  const EditorLayout({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 850),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  );
}

class ItemEditor extends StatefulWidget {
  const ItemEditor({
    super.key,
    required this.ui,
    required this.session,
    required this.collection,
    this.item,
    required this.onSave,
    required this.onCancel,
  });
  final AdaptiveControls ui;
  final CatalogSession session;
  final CollectionRecord collection;
  final CatalogItem? item;
  final Future<void> Function(CatalogItem) onSave;
  final VoidCallback onCancel;
  @override
  State<ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<ItemEditor> {
  late final name = TextEditingController(text: widget.item?.name);
  late final tags = TextEditingController(text: widget.item?.tags.join(', '));
  late final notes = TextEditingController(text: widget.item?.notes);
  late final date = TextEditingController(
    text: widget.item?.acquiredAt?.toIso8601String().substring(0, 10),
  );
  late final value = TextEditingController(
    text: widget.item?.declaredValueMinor == null
        ? ''
        : '${widget.item!.declaredValueMinor! ~/ 100}.${(widget.item!.declaredValueMinor! % 100).toString().padLeft(2, '0')}',
  );
  late final custom = {
    for (final key in {
      ...widget.collection.customFields.keys,
      ...?widget.item?.customFields.keys,
    })
      key: TextEditingController(
        text:
            widget.item?.customFields[key] ??
            widget.collection.customFields[key] ??
            '',
      ),
  };
  late String condition = widget.item?.condition.name ?? 'unknown';
  late final refs = [...?widget.item?.photoRefs];
  final imported = <String>[];
  bool busy = false;
  bool saved = false;
  String? error;
  @override
  void dispose() {
    for (final c in [name, tags, notes, date, value, ...custom.values]) {
      c.dispose();
    }
    if (!saved) {
      widget.session.photos.discard(imported).catchError((Object _) {});
    }
    super.dispose();
  }

  Future<void> cancel() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.session.photos.discard(imported);
      imported.clear();
      if (mounted) widget.onCancel();
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not discard attached photos. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> attach(ImageSource source) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final ref = await widget.session.photos.attach(source);
      if (ref != null) {
        if (!mounted) {
          await widget.session.photos.discard([ref]);
          return;
        }
        refs.add(ref);
        imported.add(ref);
      }
    } catch (_) {
      if (mounted) error = 'Could not attach photo. Check access or try another photo. You can save without photos.';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    DateTime? acquired;
    int? minor;
    try {
      if (name.text.trim().isEmpty) {
        throw const FormatException('Enter an item name.');
      }
      if (date.text.trim().isNotEmpty) {
        final raw = date.text.trim();
        acquired = DateTime.tryParse('${raw}T00:00:00Z');
        if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw) ||
            acquired == null ||
            acquired.toIso8601String().substring(0, 10) != raw) {
          throw const FormatException(
            'Enter a valid date as YYYY-MM-DD or leave it empty.',
          );
        }
      }
      if (value.text.trim().isNotEmpty) {
        final raw = value.text.trim();
        if (!RegExp(r'^\d{1,16}(\.\d{1,2})?$').hasMatch(raw)) {
          throw const FormatException(
            'Enter a nonnegative value with up to two decimal places.',
          );
        }
        final parts = raw.split('.');
        minor =
            int.parse(parts[0]) * 100 +
            (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
      }
    } on FormatException catch (e) {
      setState(() => error = e.message);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.onSave(
        CatalogItem(
          id: widget.item?.id ?? newCatalogId(),
          collectionId: widget.collection.id,
          name: name.text.trim(),
          condition: ItemCondition.values.byName(condition),
          location: widget.item?.location,
          photoRefs: refs,
          tags: tags.text
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toSet(),
          acquiredAt: acquired,
          notes: notes.text.trim(),
          declaredValueMinor: minor,
          customFields: {
            for (final entry in custom.entries)
              entry.key: entry.value.text.trim(),
          },
        ),
      );
      saved = true;
      await widget.session.photos.discard(
        imported.where((r) => !refs.contains(r)),
      );
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not save item. Please try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && !busy) cancel();
    },
    child: EditorLayout(
      children: [
        Text(
          widget.item == null
              ? 'Add item to ${widget.collection.name}'
              : 'Edit item',
          style: const TextStyle(fontSize: 24),
        ),
        widget.ui.field('Item name', name),
        widget.ui.choice(context, 'Condition', condition, {
          for (final c in ItemCondition.values) c.name: c.name,
        }, (v) => setState(() => condition = v)),
        widget.ui.field('Tags (comma separated)', tags),
        widget.ui.field('Notes', notes, lines: 3),
        widget.ui.field('Acquired date (YYYY-MM-DD, optional)', date),
        widget.ui.field('Declared value (optional)', value),
        const Text(
          'Your declared amount in your own currency, not an appraisal.',
        ),
        for (final entry in custom.entries)
          widget.ui.field('Custom: ${entry.key}', entry.value),
        const SizedBox(height: 12),
        Text(refs.isEmpty ? 'No photo — photos are optional.' : 'Photos'),
        for (final ref in refs)
          Row(
            children: [
              Expanded(
                child: Image.file(
                  widget.session.photos.file(ref),
                  height: 120,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Text('Photo unavailable'),
                ),
              ),
              widget.ui.button(
                'Remove photo',
                busy ? null : () => setState(() => refs.remove(ref)),
              ),
            ],
          ),
        Wrap(
          spacing: 12,
          children: [
            widget.ui.button(
              'Attach from gallery',
              busy ? null : () => attach(ImageSource.gallery),
            ),
            if (!widget.ui.desktop &&
                widget.ui.platform != TargetPlatform.macOS)
              widget.ui.button(
                'Take photo',
                busy ? null : () => attach(ImageSource.camera),
              ),
          ],
        ),
        if (error != null) Text(error!),
        Wrap(
          spacing: 12,
          children: [
            widget.ui.button('Save item', busy ? null : save),
            widget.ui.button('Cancel', busy ? null : cancel),
          ],
        ),
      ],
    ),
  );
}
