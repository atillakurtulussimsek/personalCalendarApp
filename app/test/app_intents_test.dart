import 'package:flutter_test/flutter_test.dart';
import 'package:personal_calendar/platform/app_intents.dart';

void main() {
  test('AppIntent.fromUri maps the personalcalendar scheme', () {
    final c = AppIntent.fromUri(Uri.parse('personalcalendar://capture?text=yar%C4%B1n%2015%3A00%20toplant%C4%B1'));
    expect(c!.type, AppIntentType.capture);
    expect(c.text, 'yarın 15:00 toplantı');
    expect(AppIntent.fromUri(Uri.parse('personalcalendar://note'))!.type, AppIntentType.newNote);
    expect(AppIntent.fromUri(Uri.parse('personalcalendar://event'))!.type, AppIntentType.newEvent);
    expect(AppIntent.fromUri(Uri.parse('personalcalendar://today'))!.type, AppIntentType.today);
    expect(AppIntent.fromUri(Uri.parse('personalcalendar:///show'))!.type, AppIntentType.show);
    expect(AppIntent.fromUri(Uri.parse('personalcalendar://nope')), isNull);
    expect(AppIntent.fromUri(null), isNull);
  });

  test('intents emitted before a listener exists are buffered and flushed', () async {
    final got = <AppIntentType>[];
    AppIntents.instance.emit(const AppIntent(AppIntentType.today));
    final sub = AppIntents.instance.stream.listen((i) => got.add(i.type));
    AppIntents.instance.flush();
    AppIntents.instance.emit(const AppIntent(AppIntentType.capture, text: 'x'));
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(got, [AppIntentType.today, AppIntentType.capture]);
  });
}
