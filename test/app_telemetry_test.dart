import 'package:flutter_test/flutter_test.dart';
import 'package:hideip_vpn/core/app_telemetry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Map<String, String>> sent;
  late bool accept;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sent = [];
    accept = true;
    AppTelemetry.send = (body) async {
      sent.add(body);
      return accept;
    };
  });

  test('sends each event once and only the event and platform', () async {
    expect(await AppTelemetry.mark(AppEvent.firstOpen, enabled: true), isTrue);
    expect(await AppTelemetry.mark(AppEvent.firstOpen, enabled: true), isFalse);
    expect(sent, hasLength(1));
    expect(sent.single.keys.toSet(), {'event', 'platform'});
    expect(sent.single['event'], 'first_open');
    expect(sent.single['platform'], anyOf('android', 'ios'));
  });

  test('switched off means no request at all', () async {
    expect(await AppTelemetry.mark(AppEvent.firstConnect, enabled: false), isFalse);
    expect(sent, isEmpty);
    // Turning it on later still counts the event: nothing was burnt.
    expect(await AppTelemetry.mark(AppEvent.firstConnect, enabled: true), isTrue);
  });

  test('a failed send is retried on the next trigger', () async {
    accept = false;
    expect(await AppTelemetry.mark(AppEvent.firstProfile, enabled: true), isFalse);
    accept = true;
    expect(await AppTelemetry.mark(AppEvent.firstProfile, enabled: true), isTrue);
    expect(sent, hasLength(2));
  });
}
