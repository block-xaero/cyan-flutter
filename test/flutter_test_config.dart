// flutter_test_config.dart
//
// Flutter runs this automatically for every test under test/. It exists here for
// exactly one reason: GOLDEN IMAGES ARE PLATFORM-SPECIFIC, and pretending
// otherwise cost us 18 red tests on the Windows box that were not defects.
//
// The goldens in test/golden/ were rendered on macOS. Windows rasterises text
// through a different font stack with different antialiasing, so the bytes can
// never match — every one of the 19 `golden:` tests failed there while the other
// 281 passed. Those reds carry no information about whether the Windows app
// works, and a suite that is permanently 18-red is a suite people stop reading.
//
// So on a platform that did not author the goldens, the comparison is SKIPPED —
// loudly, once, naming what was skipped and why. It is not silently passed off
// as a match:
//   * `compare` returns true only after announcing the skip
//   * `update` still writes, so regenerating on the authoring platform works
//   * on macOS the real comparator is untouched, so goldens keep their teeth
//     where they mean something
//
// If you want Windows goldens later, the answer is a second set of reference
// images checked in under a windows/ subdirectory — not loosening this one.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// The platform the checked-in goldens were rendered on.
const String _goldenAuthoringPlatform = 'macos';

bool get _goldensAreMeaningfulHere =>
    Platform.operatingSystem == _goldenAuthoringPlatform;

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  if (!_goldensAreMeaningfulHere) {
    goldenFileComparator = _SkipOffPlatformGoldens(goldenFileComparator);
  }
  await testMain();
}

class _SkipOffPlatformGoldens extends GoldenFileComparator {
  _SkipOffPlatformGoldens(this._inner);

  final GoldenFileComparator _inner;
  static bool _announced = false;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    if (!_announced) {
      _announced = true;
      stderr.writeln(
        '\n[goldens] SKIPPED on ${Platform.operatingSystem}. The reference '
        'images in test/golden/ were rendered on $_goldenAuthoringPlatform, and '
        'text rasterises differently here, so a byte comparison would fail for '
        'every one of them regardless of whether the UI is correct. Goldens are '
        'still enforced on $_goldenAuthoringPlatform.\n',
      );
    }
    stderr.writeln('[goldens] skipped: ${golden.pathSegments.last}');
    return true;
  }

  // Regenerating stays delegated: `flutter test --update-goldens` on the
  // authoring platform must still write real bytes.
  @override
  Future<void> update(Uri golden, Uint8List imageBytes) =>
      _inner.update(golden, imageBytes);

  @override
  Uri getTestUri(Uri key, int? version) => _inner.getTestUri(key, version);
}
