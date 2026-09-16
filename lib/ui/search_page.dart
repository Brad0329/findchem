/// F-001 검색 화면 — 검색창 + 결과 목록. 화면 방향(REQUIREMENTS): 입력 즉시 검색, 휴대폰 1열 / 폭 900 이상 2열.
///
/// 결과를 **카드로 그릴지 표로 그릴지는 이 파일 한 곳에서** 정한다(웹=표 F-004, 앱=카드 F-001).
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../assist/llm_client.dart' show assistEnabledByDefault;
import '../data/favorites.dart';
import '../parser/models.dart';
import '../search/search.dart';
import 'app_header.dart';
import 'cas_lookup_panel.dart';
import 'entry_card.dart';
import 'favorites_page.dart';
import 'result_table.dart';

/// 화면 문구(테스트가 같은 상수를 본다).
abstract final class SearchText {
  static const hint = '물질명(국문·영문) 또는 CAS 번호';
  static const casNoHit = '염류·화합물 묶음 항목에 해당할 수 있으니 물질명으로도 검색해 보세요';
  static const noHit = '결과 없음';
  static String header(SearchResult r) =>
      '전체 ${r.total}건 · ${Source.byeolpyo3.label} ${r.count3}건 · ${Source.byeolpyo2.label} ${r.count2}건';
  static String truncated(SearchResult r) => '앞 ${r.hits.length}건만 표시 · 더 있음';
}

/// 이 폭부터 결과를 2열로 놓는다.
const wideBreakpoint = 900.0;

class SearchPage extends StatefulWidget {
  const SearchPage({
    super.key,
    required this.dataset,
    this.onMenu,
    this.favorites,
    this.lookup,
    bool? useTable,
    bool? showAssist,
  }) : useTable = useTable ?? kIsWeb,
       showAssist = showAssist ?? assistEnabledByDefault;

  /// F-008 판정(AI) 메뉴 항목을 보일지. 기본값은 앱·웹 둘 다 — 테스트에서만 직접 넣는다.
  final bool showAssist;

  /// F-007 CAS 조회. null이면 CAS가 눌리지 않는다. 지금은 표(웹)에만 붙는다 — 앱 카드는 앱 단계(REQUIREMENTS F-007 '단계').
  final CasLookup? lookup;

  final Dataset dataset;

  /// 결과를 표(F-004)로 그린다. 기본값은 웹이면 표, 앱이면 카드 — 테스트에서만 직접 넣는다.
  /// F-005(앱 전용)도 이 분기를 따른다: 카드일 때만 저장 아이콘과 메뉴의 '자주보는 Chem 목록'이 있다.
  final bool useTable;

  /// F-005 저장 목록. null이면 저장 아이콘·메뉴 항목이 없다.
  final FavoritesController? favorites;

  bool get _favoritesEnabled => favorites != null && !useTable;

  /// 헤더 '⋮' 메뉴 항목을 골랐을 때(설정 화면 열기는 app.dart가 한다).
  final ValueChanged<HeaderMenu>? onMenu;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late SearchIndex _index = SearchIndex(widget.dataset);
  final _controller = TextEditingController();
  SearchResult _result = SearchResult.empty;

  @override
  void didUpdateWidget(SearchPage old) {
    super.didUpdateWidget(old);
    if (!identical(old.dataset, widget.dataset)) {
      _index = SearchIndex(widget.dataset);
      _result = _index.search(_controller.text);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) => setState(() => _result = _index.search(text));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader(
        onMenu: widget.onMenu,
        showFavorites: widget._favoritesEnabled,
        showAssist: widget.showAssist,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: SearchText.hint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: '지우기',
                        onPressed: () {
                          _controller.clear();
                          _onChanged('');
                        },
                      ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: _ResultList(
              result: _result,
              dataset: widget.dataset,
              useTable: widget.useTable,
              favorites: widget._favoritesEnabled ? widget.favorites : null,
              lookup: widget.lookup,
            ),
          ),
        ],
      ),
    );
  }
}

/// 결과 머리: 전체·표별 건수, 절단 안내, 0건 안내. 카드·표 양쪽이 같은 것을 쓴다.
class _ResultHeader extends StatelessWidget {
  const _ResultHeader({required this.result});

  final SearchResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = result;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(SearchText.header(r), style: theme.textTheme.bodySmall),
          if (r.truncated)
            Text(
              SearchText.truncated(r),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
          if (r.total == 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(r.casQueryNoHit ? SearchText.casNoHit : SearchText.noHit),
            ),
        ],
      ),
    );
  }
}

class _ResultList extends StatelessWidget {
  const _ResultList({
    required this.result,
    required this.dataset,
    required this.useTable,
    this.favorites,
    this.lookup,
  });

  final SearchResult result;
  final Dataset dataset;
  final bool useTable;
  final FavoritesController? favorites;
  final CasLookup? lookup;

  @override
  Widget build(BuildContext context) {
    final r = result;
    Widget card(Hit h) {
      final pdf = h.entry.src == Source.byeolpyo3 ? dataset.byeolpyo3 : dataset.byeolpyo2;
      final fav = favorites;
      return EntryCard(
        hit: h,
        pdf: pdf,
        action: fav == null ? null : SaveButton(favorites: fav, hit: h, pdf: pdf, entries: dataset.entries),
      );
    }
    if (r.query.trim().isEmpty) return const SizedBox.shrink();

    if (useTable) {
      // 표(F-004): 머리(건수·안내)는 표 위에 두고, 표만 가로로 스크롤한다.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ResultHeader(result: r),
          if (r.hits.isNotEmpty) Expanded(child: ResultTable(hits: r.hits, lookup: lookup)),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= wideBreakpoint ? 2 : 1;
        final rowCount = (r.hits.length + columns - 1) ~/ columns;
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 24),
          // 0: 머리(건수·안내), 1..rowCount: 카드 행
          itemCount: 1 + rowCount,
          itemBuilder: (context, i) {
            if (i == 0) return _ResultHeader(result: r);
            final start = (i - 1) * columns;
            final rowHits = r.hits.sublist(start, (start + columns).clamp(0, r.hits.length));
            if (columns == 1) return card(rowHits.first);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final h in rowHits) Expanded(child: card(h)),
                for (var k = rowHits.length; k < columns; k++) const Expanded(child: SizedBox()),
              ],
            );
          },
        );
      },
    );
  }
}
