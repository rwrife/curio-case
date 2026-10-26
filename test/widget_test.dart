import 'package:curio_case/main.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Curio Case scaffold smoke tests', () {
    const screenSizes = <String, Size>{
      'phone': Size(390, 844),
      'tablet': Size(820, 1180),
      'desktop': Size(1440, 900),
    };

    for (final entry in screenSizes.entries) {
      testWidgets('renders truthful status message at ${entry.key} size', (
        tester,
      ) async {
        tester.view.physicalSize = entry.value;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(const CurioCaseApp());
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('scaffold-status')), findsOneWidget);
        expect(find.text(scaffoldStatusMessage), findsOneWidget);
        expect(find.text('Curio Case'), findsOneWidget);

        // Verify zero fake collection/catalog records are presented
        expect(find.textContaining('Enamel pins'), findsNothing);
        expect(find.textContaining('Sample collection'), findsNothing);
        expect(find.textContaining('Dummy item'), findsNothing);
      });
    }

    testWidgets('renders Cupertino layout on TargetPlatform.iOS', (
      tester,
    ) async {
      await tester.pumpWidget(
        const CurioCaseApp(platformOverride: TargetPlatform.iOS),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoApp), findsOneWidget);
      expect(find.text(scaffoldStatusMessage), findsOneWidget);
      expect(find.text('Curio Case'), findsOneWidget);
    });

    testWidgets('renders Fluent layout on TargetPlatform.windows', (
      tester,
    ) async {
      await tester.pumpWidget(
        const CurioCaseApp(platformOverride: TargetPlatform.windows),
      );
      await tester.pumpAndSettle();

      expect(find.byType(fluent.FluentApp), findsOneWidget);
      expect(find.text(scaffoldStatusMessage), findsOneWidget);
      expect(find.text('Curio Case'), findsOneWidget);
    });

    testWidgets('renders Material layout on TargetPlatform.android', (
      tester,
    ) async {
      await tester.pumpWidget(
        const CurioCaseApp(platformOverride: TargetPlatform.android),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MaterialApp), findsOneWidget);
      expect(find.text(scaffoldStatusMessage), findsOneWidget);
      expect(find.text('Curio Case'), findsOneWidget);
    });
  });
}
