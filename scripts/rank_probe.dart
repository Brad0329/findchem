// F-008 조사 — 검색 상한을 20에서 더 내려도 되는가?
//
//   dart run scripts/rank_probe.dart
//
// "정답 물질이 결과의 몇 번째에 오는가"를 번들 데이터 전체에 직접 물어본다.
// 상한을 N으로 내리면 **자기 순위가 N을 넘는 물질은 자기 이름으로 검색해도 안 보인다.**
// 판정은 여전히 `truncated`ㆍ`total`을 받아 질의를 좁혀 다시 부를 수 있지만, 왕복이 한 번 는다.
//
// 검색ㆍ정렬은 `lib/search/`가 한다 — 여기서 재구현하지 않는다(두 번째 구현 금지).

import 'dart:convert';
import 'dart:io';

import 'package:findchem/parser/models.dart';
import 'package:findchem/search/search.dart';

const dataPath = 'assets/data/findchem_data.json';

/// 화면의 예시 질문 4개가 부르는 검색어(lib/ui/assist_page.dart) + 이 조사에서 나온 최악 사례.
const exampleQueries = ['암모니아', '톨루엔', '황산', '염화수소', '메틸알코올', '아세트산'];

void main() {
  final ds = Dataset.fromJson(
    (jsonDecode(File(dataPath).readAsStringSync()) as Map).cast<String, Object?>(),
  );
  // 순위를 보려면 자르지 않은 목록이 필요하다.
  final index = SearchIndex(ds, cap: 100000);

  stdout.writeln('── 예시 질문의 검색어 ──');
  for (final q in exampleQueries) {
    final r = index.search(q);
    final self = r.hits.indexWhere((h) => h.entry.ko == q) + 1;
    final where = self == 0 ? '이름이 정확히 같은 항목 없음' : '자기 순위 $self위';
    stdout.writeln('$q: 전체 ${r.total}건 · $where');
    for (var i = 0; i < r.hits.length && i < 12; i++) {
      final e = r.hits[i].entry;
      stdout.writeln('   ${(i + 1).toString().padLeft(2)}. [${e.src.name}] ${e.ko}');
    }
    if (r.total > 12) stdout.writeln('   … ${r.total - 12}건 더');
  }

  stdout.writeln('\n── 번들 전체: 자기 이름으로 검색했을 때의 자기 순위 ──');
  final over = <int, List<String>>{};
  var checked = 0;
  var worst = 0;
  String worstName = '';
  for (final e in ds.entries) {
    if (e.ko.trim().isEmpty || e.deleted) continue;
    checked++;
    final r = index.search(e.ko);
    final rank = r.hits.indexWhere((h) => h.entry.src == e.src && h.entry.no == e.no) + 1;
    if (rank == 0) continue; // 자기 이름으로 자기가 안 걸리면 별개 문제다 — 아래 집계에서 뺀다
    if (rank > worst) {
      worst = rank;
      worstName = e.ko;
    }
    for (final cap in const [5, 10, 20]) {
      if (rank > cap) (over[cap] ??= []).add('${e.ko}($rank위)');
    }
  }
  stdout.writeln('살아있는 항목 $checked건 검사. 가장 나쁜 순위 = $worst위($worstName)');
  for (final cap in const [5, 10, 20]) {
    final list = over[cap] ?? const [];
    stdout.writeln('상한 $cap → 자기 이름으로 검색해도 안 보이는 항목 ${list.length}건'
        '${list.isEmpty ? '' : ': ${list.take(8).join(', ')}${list.length > 8 ? ' …' : ''}'}');
  }
}
