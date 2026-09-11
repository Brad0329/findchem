import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:findchem/main.dart';

void main() {
  testWidgets('앱이 뜨고 이름이 FindChem이다', (tester) async {
    await tester.pumpWidget(const FindChemApp());

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, 'FindChem');
    expect(find.text('FindChem'), findsOneWidget);
  });
}
