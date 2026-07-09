import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('기본 위젯 렌더링 테스트', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('아파인드'))),
    );

    expect(find.text('아파인드'), findsOneWidget);
  });
}
