import 'package:flutter_test/flutter_test.dart';
import 'package:duo_chat/app.dart';

void main() {
  testWidgets('ClockApp renders successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const ClockApp());
    expect(find.byType(ClockApp), findsOneWidget);
  });
}
