import 'dart:io';

import 'package:ai_team/ui/chat/image_picker_button.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('image picker emits picked files and ignores missing paths',
      (tester) async {
    var pickedFiles = <File>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImagePickerButton(
            pickImages: () async => FilePickerResult([
              PlatformFile(
                name: 'one.png',
                path: '/tmp/one.png',
                size: 1,
              ),
              PlatformFile(
                name: 'no-path.png',
                size: 1,
              ),
              PlatformFile(
                name: 'two.jpg',
                path: '/tmp/two.jpg',
                size: 1,
              ),
            ]),
            onImagesPicked: (files) => pickedFiles = files,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('添加图片'));
    await tester.pumpAndSettle();

    expect(pickedFiles.map((file) => file.path), [
      '/tmp/one.png',
      '/tmp/two.jpg',
    ]);
  });

  testWidgets('image picker ignores cancel and empty path results',
      (tester) async {
    var pickedCount = 0;

    Future<void> pumpWithResult(FilePickerResult? result) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImagePickerButton(
              pickImages: () async => result,
              onImagesPicked: (_) => pickedCount++,
            ),
          ),
        ),
      );
    }

    await pumpWithResult(null);
    await tester.tap(find.byTooltip('添加图片'));
    await tester.pumpAndSettle();

    await pumpWithResult(FilePickerResult([
      PlatformFile(name: 'no-path.png', size: 1),
    ]));
    await tester.tap(find.byTooltip('添加图片'));
    await tester.pumpAndSettle();

    expect(pickedCount, 0);
  });

  testWidgets('disabled image picker does not open the file dialog',
      (tester) async {
    var openCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImagePickerButton(
            enabled: false,
            pickImages: () async {
              openCount++;
              return null;
            },
            onImagesPicked: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('添加图片'));
    await tester.pumpAndSettle();

    expect(openCount, 0);
  });

  testWidgets('image picker reports platform errors without throwing',
      (tester) async {
    Object? reportedError;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImagePickerButton(
            pickImages: () async {
              throw PlatformException(
                code: 'ENTITLEMENT_NOT_FOUND',
                message: 'Missing file picker entitlement.',
              );
            },
            onPickError: (error, _) => reportedError = error,
            onImagesPicked: (_) => fail('No files should be emitted.'),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('添加图片'));
    await tester.pumpAndSettle();

    expect(reportedError, isA<PlatformException>());
  });

  testWidgets('image picker error hook can surface user feedback',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ImagePickerButton(
              pickImages: () async {
                throw PlatformException(
                  code: 'ENTITLEMENT_NOT_FOUND',
                  message: 'Missing file picker entitlement.',
                );
              },
              onPickError: (_, __) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('图片选择失败')),
                );
              },
              onImagesPicked: (_) => fail('No files should be emitted.'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('添加图片'));
    await tester.pumpAndSettle();

    expect(find.text('图片选择失败'), findsOneWidget);
  });
}
