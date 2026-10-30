import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class AdaptiveControls {
  const AdaptiveControls(this.platform);
  final TargetPlatform platform;
  bool get apple =>
      platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
  bool get desktop =>
      platform == TargetPlatform.windows || platform == TargetPlatform.linux;

  Widget button(String label, VoidCallback? onPressed, {Key? key}) {
    final child = Text(label);
    if (apple) {
      return CupertinoButton(key: key, onPressed: onPressed, child: child);
    }
    if (desktop) {
      return fluent.Button(key: key, onPressed: onPressed, child: child);
    }
    return OutlinedButton(key: key, onPressed: onPressed, child: child);
  }

  Widget field(
    String label,
    TextEditingController controller, {
    int lines = 1,
    ValueChanged<String>? onChanged,
    FocusNode? focusNode,
  }) {
    final key = Key(label);
    final input = apple
        ? CupertinoTextField(
            key: key,
            controller: controller,
            focusNode: focusNode,
            placeholder: label,
            maxLines: lines,
            onChanged: onChanged,
          )
        : desktop
        ? fluent.TextBox(
            key: key,
            controller: controller,
            focusNode: focusNode,
            placeholder: label,
            maxLines: lines,
            onChanged: onChanged,
          )
        : TextField(
            key: key,
            controller: controller,
            focusNode: focusNode,
            maxLines: lines,
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
            ),
            onChanged: onChanged,
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (apple || desktop) Text(label),
          if (apple || desktop)
            Semantics(label: label, child: input)
          else
            input,
        ],
      ),
    );
  }

  Widget choice(
    BuildContext context,
    String label,
    String value,
    Map<String, String> options,
    ValueChanged<String> onChanged,
  ) {
    Widget input;
    if (apple) {
      input = CupertinoButton(
        key: Key(label),
        padding: const EdgeInsets.symmetric(vertical: 12),
        onPressed: () async {
          final result = await showCupertinoModalPopup<String>(
            context: context,
            builder: (context) => CupertinoActionSheet(
              title: Text(label),
              actions: [
                for (final entry in options.entries)
                  CupertinoActionSheetAction(
                    onPressed: () => Navigator.pop(context, entry.key),
                    child: Text(entry.value),
                  ),
              ],
              cancelButton: CupertinoActionSheetAction(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ),
          );
          if (result != null) onChanged(result);
        },
        child: Text('$label: ${options[value]}'),
      );
    } else if (desktop) {
      input = fluent.ComboBox<String>(
        key: Key(label),
        value: value,
        isExpanded: true,
        items: [
          for (final entry in options.entries)
            fluent.ComboBoxItem(value: entry.key, child: Text(entry.value)),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      );
    } else {
      input = DropdownButton<String>(
        key: Key(label),
        value: value,
        isExpanded: true,
        items: [
          for (final entry in options.entries)
            DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [if (!apple) Text(label), input],
      ),
    );
  }

  Future<bool> confirm(
    BuildContext context,
    String title,
    String message,
  ) async {
    if (apple) {
      return await showCupertinoDialog<bool>(
            context: context,
            builder: (context) => CupertinoAlertDialog(
              title: Text(title),
              content: Text(message),
              actions: [
                CupertinoDialogAction(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                CupertinoDialogAction(
                  isDestructiveAction: true,
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete'),
                ),
              ],
            ),
          ) ??
          false;
    }
    if (desktop) {
      return await fluent.showDialog<bool>(
            context: context,
            builder: (context) => fluent.ContentDialog(
              title: Text(title),
              content: Text(message),
              actions: [
                fluent.Button(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                fluent.FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete'),
                ),
              ],
            ),
          ) ??
          false;
    }
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
  }
}
