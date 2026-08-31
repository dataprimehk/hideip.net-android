import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hideip_vpn/core/camera_permission.dart';
import 'package:hideip_vpn/ui/qr_scan_screen.dart';
import 'package:hideip_vpn/ui/redesign/hip.dart';
import 'package:hideip_vpn/ui/redesign/qr_popup.dart';
import 'package:hideip_vpn/ui/strings.dart';

const _controls = Key('controls');

/// Stands in for the camera preview and reproduces, without a camera, exactly
/// where the reader puts its torch and camera-flip buttons: bottom centre, at
/// [QrOverlay.controlsPadding], with no safe-area padding of its own (the real
/// reader has that stripped).
Widget _fakeReader(
  BuildContext context, {
  required ValueChanged<String> onCode,
}) {
  final inset = MediaQuery.paddingOf(context).bottom;
  return Align(
    alignment: Alignment.bottomCenter,
    child: Padding(
      padding: QrOverlay.controlsPadding(inset),
      child: const SizedBox(
        key: _controls,
        width: 114,
        height: QrOverlay.controlsHeight,
      ),
    ),
  );
}

/// One iPhone 14 screen: 390 x 844 logical, with the notch above and the home
/// indicator below.
Future<void> _pump(WidgetTester tester, {required double bottomInset}) async {
  tester.view.devicePixelRatio = 3.0;
  tester.view.physicalSize = const Size(1170, 2532);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: EdgeInsets.only(
              top: bottomInset == 0 ? 0 : 59,
              bottom: bottomInset,
            ),
          ),
          child: Stack(
            children: [
              QrPopup(
                onCode: (_) {},
                onClose: () {},
                onPasteInstead: () {},
                camStatus: () async => CamPerm.granted,
                readerBuilder: _fakeReader,
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    // The scanline repeats forever; frozen, pumpAndSettle can settle.
    Hip.reducedMotion = true;
  });
  tearDown(() => Hip.reducedMotion = false);

  testWidgets('the controls clear the caption with no safe-area inset', (
    tester,
  ) async {
    await _pump(tester, bottomInset: 0);

    final controls = tester.getRect(find.byKey(_controls));
    final caption = tester.getRect(find.text(S.e9Hint));

    expect(controls.top, greaterThanOrEqualTo(caption.bottom));
    // Design: `.cam-hint { bottom: 86px }` off the bottom of the panel, which
    // is the bottom of the screen.
    expect(caption.bottom, moreOrLessEquals(844 - 86, epsilon: 0.5));
  });

  testWidgets('the controls clear both the caption and the home indicator', (
    tester,
  ) async {
    await _pump(tester, bottomInset: 34);

    final controls = tester.getRect(find.byKey(_controls));
    final caption = tester.getRect(find.text(S.e9Hint));

    // The bug: on iOS the reader's own SafeArea lifted the buttons 34px, into
    // the caption that sat at a flat 86px.
    expect(controls.top, greaterThanOrEqualTo(caption.bottom));
    // And the buttons still stand above the home indicator.
    expect(controls.bottom, lessThanOrEqualTo(844 - 34));
    expect(caption.bottom, moreOrLessEquals(844 - 86 - 34, epsilon: 0.5));
  });
}
