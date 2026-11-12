import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/shell/quick_capture_parser.dart';

void main() {
  // Thursday, 12 Nov 2026, 10:00
  final now = DateTime(2026, 11, 12, 10);

  test('tomorrow + pm time', () {
    final r = QuickCaptureParser.parse('study graphs tomorrow 7pm', now: now);
    expect(r.title, 'Study graphs');
    expect(r.due, DateTime(2026, 11, 13, 19));
    expect(r.hasTime, isTrue);
  });

  test('time with minutes and "at"', () {
    final r = QuickCaptureParser.parse('call mom today at 6:30 pm', now: now);
    expect(r.title, 'Call mom');
    expect(r.due, DateTime(2026, 11, 12, 18, 30));
  });

  test('24h time without am/pm', () {
    final r = QuickCaptureParser.parse('gym 19:00', now: now);
    expect(r.due, DateTime(2026, 11, 12, 19));
  });

  test('weekday goes to the next occurrence', () {
    final r = QuickCaptureParser.parse('revise SQL on monday', now: now);
    expect(r.title, 'Revise SQL');
    expect(r.due, DateTime(2026, 11, 16));
    expect(r.hasTime, isFalse);
  });

  test('same weekday means next week', () {
    final r = QuickCaptureParser.parse('team sync thursday', now: now);
    expect(r.due, DateTime(2026, 11, 19));
  });

  test('plain numbers are not treated as times', () {
    final r = QuickCaptureParser.parse('solve 3 problems', now: now);
    expect(r.title, 'Solve 3 problems');
    expect(r.due, isNull);
  });

  test('12am is midnight', () {
    final r = QuickCaptureParser.parse('backup tomorrow 12am', now: now);
    expect(r.due, DateTime(2026, 11, 13, 0));
  });
}
