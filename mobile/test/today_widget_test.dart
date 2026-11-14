import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/data/widget/home_widget_service.dart';

void main() {
  testWidgets('home-screen card fits its fixed size with long titles', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 340,
          height: 160,
          child: TodayCard(
            data: TodayCardData(
              signedIn: true,
              tasks: (1, 4),
              habits: (2, 3),
              studyMinutes: 30,
              studyGoal: 60,
              top: List.filled(3, 'A very long task title that will not fit on one line at all'),
            ),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull); // no overflow
    expect(find.text('47%'), findsOneWidget); // (0.25 + 0.67 + 0.5) / 3
  });
}
