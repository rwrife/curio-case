import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'adaptive.dart';
import 'catalog_session.dart';
import 'catalog_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CurioCaseApp());
}

class CurioCaseApp extends StatefulWidget {
  const CurioCaseApp({super.key, this.platformOverride, this.session});
  final TargetPlatform? platformOverride;
  final CatalogSession? session;

  @override
  State<CurioCaseApp> createState() => _CurioCaseAppState();
}

class _CurioCaseAppState extends State<CurioCaseApp> {
  late Future<CatalogSession> session;
  @override
  void initState() {
    super.initState();
    session = widget.session != null
        ? Future.value(widget.session)
        : CatalogSession.open();
  }

  @override
  Widget build(BuildContext context) {
    final platform = widget.platformOverride ?? defaultTargetPlatform;
    final controls = AdaptiveControls(platform);
    final home = FutureBuilder<CatalogSession>(
      future: session,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not open the local catalog.'),
                controls.button(
                  'Retry',
                  () => setState(() => session = CatalogSession.open()),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: Text('Opening catalog…'));
        }
        return CatalogView(session: snapshot.requireData, controls: controls);
      },
    );
    if (controls.apple) {
      return CupertinoApp(
        title: 'Curio Case',
        debugShowCheckedModeBanner: false,
        home: CupertinoPageScaffold(
          navigationBar: const CupertinoNavigationBar(
            middle: Text('Curio Case'),
          ),
          child: SafeArea(child: home),
        ),
      );
    }
    if (controls.desktop) {
      return fluent.FluentApp(
        title: 'Curio Case',
        debugShowCheckedModeBanner: false,
        home: fluent.NavigationView(
          titleBar: const fluent.TitleBar(title: Text('Curio Case')),
          content: home,
        ),
      );
    }
    return MaterialApp(
      title: 'Curio Case',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6D4C41)),
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('Curio Case')),
        body: home,
      ),
    );
  }
}
