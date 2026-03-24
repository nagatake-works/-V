import 'package:flutter_test/flutter_test.dart';
import 'package:vtuber_chat/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const VtuberChatApp(hasConsented: true));
    expect(find.byType(VtuberChatApp), findsOneWidget);
  });
}
