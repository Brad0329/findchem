/// 실측(2026-09-12): 웹에서 표를 마우스로 긁어 Excel에 붙이는 것이 가능한가.
/// SelectionArea가 여러 위젯에 걸친 선택을 **무엇으로 이어 붙여** 클립보드에 넣는지 잰다.
/// (VM에서 재지만 이어 붙이는 규칙은 Dart 쪽 코드라 웹도 같다 — 드래그 조작 자체는 브라우저에서 따로 본다.)
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// [child]를 SelectionArea로 감싸 그리고, [from] 글자 → [to] 글자까지 마우스로 끌어 선택한 뒤
  /// 선택 내용(클립보드에 들어갈 문자열)을 돌려준다.
  Future<String?> dragSelect(
    WidgetTester tester, {
    required Widget child,
    required String from,
    required String to,
  }) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            onSelectionChanged: (content) => selected = content?.plainText,
            child: child,
          ),
        ),
      ),
    );
    // 글자 전체를 덮도록 첫 글자의 왼쪽 끝 안쪽 → 끝 글자의 오른쪽 끝 안쪽으로 끈다.
    final gesture = await tester.startGesture(
      tester.getTopLeft(find.text(from)) + const Offset(1, 4),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(tester.getBottomRight(find.text(to)) - const Offset(1, 4));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    return selected;
  }

  testWidgets('셀마다 Text 위젯이 따로면 선택 문자열에 열·행 구분자가 없다', (tester) async {
    final selected = await dragSelect(
      tester,
      from: '연번',
      to: '97-1-90',
      child: Table(
        children: const [
          TableRow(children: [Text('연번'), Text('화학물질명'), Text('고유번호')]),
          TableRow(children: [Text('1'), Text('시안화제일금칼륨'), Text('97-1-90')]),
        ],
      ),
    );
    // 실측 결과를 그대로 못박는다 — 이 값이 바뀌면(Flutter 업그레이드 등) 결론을 다시 봐야 한다.
    // 셀들이 **아무 구분자 없이** 이어 붙는다 → Excel에 붙이면 한 칸에 다 들어간다.
    expect(selected, '연번화학물질명고유번호1시안화제일금칼륨97-1-90');
    expect(selected, isNot(contains('\t')));
    expect(selected, isNot(contains('\n')));
  });

  testWidgets('한 행을 Text 하나에 탭으로 넣으면 탭·줄바꿈이 그대로 복사된다(Excel 열 분리의 조건)', (tester) async {
    final selected = await dragSelect(
      tester,
      from: '연번\t화학물질명\t고유번호',
      to: '1\t시안화제일금칼륨\t97-1-90',
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Text('연번\t화학물질명\t고유번호'), Text('1\t시안화제일금칼륨\t97-1-90')],
      ),
    );
    expect(selected, contains('연번\t화학물질명\t고유번호'));
    expect(selected, contains('1\t시안화제일금칼륨\t97-1-90'));
    // 다만 Text가 둘로 나뉘면 그 사이에는 줄바꿈이 들어가지 않는다 — 행 구분까지 살리려면 한 Text 안에 있어야 한다.
    expect(selected, contains('고유번호1'));
    expect(selected, isNot(contains('\n')));
  });
}
