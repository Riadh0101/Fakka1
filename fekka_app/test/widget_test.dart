import 'package:flutter_test/flutter_test.dart';
import 'package:fekka_app/app.dart';

void main() {
  testWidgets('App renders home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const FakkaApp());
    expect(find.text('Fekka'), findsOneWidget);
  });
}
