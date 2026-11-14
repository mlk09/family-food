import 'package:family_food_assistant/core/theme/app_theme.dart';
import 'package:family_food_assistant/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('chat replies show *italic* without the asterisks', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(body: RichMessage('*रसोई सुरक्षा टिप:* गरम पैन **ध्यान** से')),
    ));
    final text = tester.widget<SelectableText>(find.byType(SelectableText)).textSpan!.toPlainText();
    expect(text, 'रसोई सुरक्षा टिप: गरम पैन ध्यान से');
  });
}
