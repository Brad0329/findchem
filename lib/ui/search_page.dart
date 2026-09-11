/// F-001 검색 화면 — 검색창 + 결과 목록. 화면 방향(REQUIREMENTS): 입력 즉시 검색, 휴대폰 1열 / 폭 900 이상 2열.
library;

import 'package:flutter/material.dart';

import '../parser/models.dart';
import '../search/search.dart';
import 'app_header.dart';
import 'entry_card.dart';

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
  const SearchPage({super.key, required this.dataset, this.onMenu});

  final Dataset dataset;

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
      appBar: AppHeader(onMenu: widget.onMenu),
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
          Expanded(child: _ResultList(result: _result, dataset: widget.dataset)),
        ],
      ),
    );
  }
}

class _ResultList extends StatelessWidget {
  const _ResultList({required this.result, required this.dataset});

  final SearchResult result;
  final Dataset dataset;

  @override
  Widget build(BuildContext context) {
    final r = result;
    Widget card(Hit h) =>
        EntryCard(hit: h, pdf: h.entry.src == Source.byeolpyo3 ? dataset.byeolpyo3 : dataset.byeolpyo2);
    if (r.query.trim().isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= wideBreakpoint ? 2 : 1;
        final rowCount = (r.hits.length + columns - 1) ~/ columns;
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 24),
          // 0: 머리(건수·안내), 1..rowCount: 카드 행
          itemCount: 1 + rowCount,
          itemBuilder: (context, i) {
            if (i == 0) {
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
