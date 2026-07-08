import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('macOS entitlements', () {
    test('allow outbound model API requests in sandboxed builds', () async {
      for (final path in [
        'macos/Runner/DebugProfile.entitlements',
        'macos/Runner/Release.entitlements',
      ]) {
        final entitlements = await File(path).readAsString();

        expect(
          entitlements,
          contains('<key>com.apple.security.network.client</key>'),
          reason: '$path must allow outbound HTTPS model calls.',
        );
        expect(
          entitlements,
          contains('<true/>'),
          reason: '$path must enable the network client entitlement.',
        );
      }
    });

    test('allow user-selected files for file picker dialogs', () async {
      for (final path in [
        'macos/Runner/DebugProfile.entitlements',
        'macos/Runner/Release.entitlements',
      ]) {
        final entitlements = await File(path).readAsString();

        expect(
          entitlements,
          contains(
            '<key>com.apple.security.files.user-selected.read-write</key>',
          ),
          reason: '$path must allow macOS file picker selections.',
        );
      }
    });
  });
}
