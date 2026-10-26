import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/foundation.dart';

void main() {
  runApp(const CurioCaseApp());
}

/// Root widget. Issue #1 is scaffold-only: real data-backed screens arrive in
/// #2/#3. The full adaptive layer lands in #5; until then iOS uses Cupertino
/// and every other target uses Material 3 so nothing ships the wrong platform
/// look. Widgets read [defaultTargetPlatform], never `dart:io`, so widget
/// tests can pump every [TargetPlatform].
class CurioCaseApp extends StatelessWidget {
  const CurioCaseApp({super.key, this.platformOverride});

  final TargetPlatform? platformOverride;

  @override
  Widget build(BuildContext context) {
    final platform = platformOverride ?? defaultTargetPlatform;
    return switch (platform) {
      TargetPlatform.iOS => const _CupertinoShell(),
      TargetPlatform.windows => const _WindowsShell(),
      _ => const _MaterialShell(), // ponytail: macOS/Linux shell pending #5.
    };
  }
}

/// True while no persistence layer exists. Never a fake catalog record.
const String scaffoldStatusMessage =
    'Scaffold ready — no collections stored yet.';

class _MaterialShell extends StatelessWidget {
  const _MaterialShell();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Curio Case',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6D4C41)),
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('Curio Case')),
        body: const _ScaffoldStatus(),
      ),
    );
  }
}

class _WindowsShell extends StatelessWidget {
  const _WindowsShell();

  @override
  Widget build(BuildContext context) {
    return fluent.FluentApp(
      title: 'Curio Case',
      home: fluent.NavigationView(
        titleBar: const fluent.TitleBar(title: Text('Curio Case')),
        content: const _ScaffoldStatus(),
      ),
    );
  }
}

class _CupertinoShell extends StatelessWidget {
  const _CupertinoShell();

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: 'Curio Case',
      theme: const CupertinoThemeData(brightness: Brightness.light),
      home: const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: Text('Curio Case')),
        child: SafeArea(child: _ScaffoldStatus()),
      ),
    );
  }
}

class _ScaffoldStatus extends StatelessWidget {
  const _ScaffoldStatus();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            scaffoldStatusMessage,
            key: const Key('scaffold-status'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18),
          ),
        ),
      ),
    );
  }
}
