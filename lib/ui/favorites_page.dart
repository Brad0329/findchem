/// F-005 자주보는 Chem 목록 화면 — 접힌 국문명 목록, 펼치면 F-001 카드(EntryCard 재사용) + 공유·삭제.
/// 헤더 '⋮' → '자주보는 Chem 목록'에서 Navigator.push로 연다(앱 전용).
///
/// 목록은 저장본만으로 그린다. 현재 데이터셋은 [update]와 갱신 알림 줄에만 쓴다.
library;

import 'package:flutter/material.dart';

import '../data/dataset_loader.dart';
import '../data/favorites.dart';
import '../parser/models.dart';
import '../search/search.dart';
import 'entry_card.dart';

/// 화면 문구(테스트가 같은 상수를 본다).
abstract final class FavoritesText {
  static const title = '자주보는 Chem 목록';
  static const saveTooltip = '저장';
  static const unsaveTooltip = '목록에서 빼기';
  static const deleteTooltip = '삭제';
  static const saved = '저장했습니다';
  static const removed = '목록에서 뺐습니다';
  static const deleted = '삭제했습니다';
  static const saveFailed = '저장하지 못했습니다';
  static const empty = '저장한 물질이 없습니다';
  static const update = 'update';
  static const stale = '원천자료가 바뀐 뒤 아직 갱신하지 않았습니다';
  static const notFound = '현재 원천자료에서 찾지 못했습니다';
  static const loadFailed = '저장 목록 파일을 읽지 못했습니다. 파일은 저절로 지우지 않았고, 이 상태에서는 저장·삭제·update를 하지 않습니다';
  static const discard = '깨진 저장 목록 지우기';
  static const discardConfirm = '읽지 못한 저장 목록 파일을 지웁니다. 파일 안에 있던 저장은 되살릴 수 없습니다.';
  static const cancel = '취소';
  static const discarded = '저장 목록 파일을 지웠습니다';
  static const discardFailed = '지우지 못했습니다';
  static const askUpdate = '저장 목록도 갱신할까요?';
  static const yes = '예';
  static const no = '아니오';

  static String count(int n) => '전체 $n건';
  static String summary(FavoritesUpdateSummary s) => '${s.updated}건 갱신, ${s.notFound}건은 찾지 못했습니다';
}

/// 알림을 바로 바꿔 띄운다 — 저장·빼기를 연달아 누르면 앞 알림이 사라질 때까지 기다리지 않게.
void _notify(ScaffoldMessengerState? messenger, String text) {
  messenger
    ?..removeCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// [update]를 돌리고 요약을 알린다. 목록 화면의 버튼과 F-002 적용 직후 질문이 같이 쓴다.
Future<void> runFavoritesUpdate(BuildContext context, FavoritesController favorites, Dataset ds) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final summary = await favorites.updateFrom(ds);
    _notify(messenger, FavoritesText.summary(summary));
  } catch (e, st) {
    // 쓰기 실패(또는 깨진 파일) — 목록은 그대로다. 원인은 로그에만.
    debugPrint('F-005 update 실패: $e\n$st');
    _notify(messenger, FavoritesText.saveFailed);
  }
}

/// 검색 결과 카드의 저장 아이콘(토글). 저장돼 있으면 채워진 별.
class SaveButton extends StatelessWidget {
  const SaveButton({
    super.key,
    required this.favorites,
    required this.hit,
    required this.pdf,
    required this.entries,
  });

  final FavoritesController favorites;
  final Hit hit;
  final PdfInfo pdf;

  /// 카드가 속한 현재 데이터셋의 항목들 — 저장 여부 판정에 쓴다([FavoritesController.savedOf]).
  final List<Entry> entries;

  Future<void> _toggle(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final nowSaved = await favorites.toggle(hit, pdf, entries);
      _notify(messenger, nowSaved ? FavoritesText.saved : FavoritesText.removed);
    } catch (e, st) {
      debugPrint('F-005 저장 실패: $e\n$st');
      _notify(messenger, FavoritesText.saveFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: favorites,
      builder: (context, _) {
        final saved = favorites.savedOf(hit.entry, entries) != null;
        return IconButton(
          icon: Icon(saved ? Icons.star : Icons.star_border),
          tooltip: saved ? FavoritesText.unsaveTooltip : FavoritesText.saveTooltip,
          visualDensity: VisualDensity.compact,
          onPressed: () => _toggle(context),
        );
      },
    );
  }
}

class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key, required this.favorites, required this.data});

  final FavoritesController favorites;

  /// 현재 원천자료 — [update]와 갱신 알림 줄에만 쓴다.
  final DataController data;

  Future<void> _remove(BuildContext context, FavoriteItem item) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await favorites.remove(item);
      _notify(messenger, FavoritesText.deleted);
    } catch (e, st) {
      debugPrint('F-005 삭제 실패: $e\n$st');
      _notify(messenger, FavoritesText.saveFailed);
    }
  }

  /// 깨진 저장 파일 복구 — 되살릴 수 없는 삭제라 확인 창을 거친다.
  Future<void> _discard(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(FavoritesText.discard),
        content: const Text(FavoritesText.discardConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text(FavoritesText.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text(FavoritesText.discard)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await favorites.discardUnreadable();
      _notify(messenger, FavoritesText.discarded);
    } catch (e, st) {
      // 원인(경로가 섞일 수 있다)은 로그에만. 깨진 상태 그대로다.
      debugPrint('F-005 깨진 저장 목록 지우기 실패: $e\n$st');
      _notify(messenger, FavoritesText.discardFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(FavoritesText.title)),
      body: ListenableBuilder(
        listenable: Listenable.merge([favorites, data]),
        builder: (context, _) {
          final theme = Theme.of(context);
          final items = favorites.items;
          final ds = data.data?.dataset;
          // 같은 국문명이 2건 이상이면 접힌 행이 똑같아 보인다 — 그 행들에만 표 이름을 붙인다(REQUIREMENTS F-005 AI 기본값).
          final koCount = <String, int>{};
          for (final i in items) {
            koCount.update(i.entry.ko, (n) => n + 1, ifAbsent: () => 1);
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    Expanded(child: Text(FavoritesText.count(items.length), style: theme.textTheme.bodySmall)),
                    OutlinedButton.icon(
                      onPressed: items.isEmpty || ds == null
                          ? null
                          : () => runFavoritesUpdate(context, favorites, ds),
                      icon: const Icon(Icons.refresh),
                      label: const Text(FavoritesText.update),
                    ),
                  ],
                ),
              ),
              if (ds != null && favorites.isStale(ds))
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(FavoritesText.stale, style: TextStyle(color: theme.colorScheme.error)),
                ),
              if (favorites.loadFailed)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(FavoritesText.loadFailed, style: TextStyle(color: theme.colorScheme.error)),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => _discard(context),
                        icon: const Icon(Icons.delete_forever_outlined),
                        label: const Text(FavoritesText.discard),
                      ),
                    ],
                  ),
                )
              else if (items.isEmpty)
                const Padding(padding: EdgeInsets.all(16), child: Text(FavoritesText.empty)),
              for (final item in items)
                ExpansionTile(
                  key: ObjectKey(item),
                  title: Text(
                    (koCount[item.entry.ko] ?? 0) > 1 ? '${item.entry.ko} · ${item.entry.src.label}' : item.entry.ko,
                  ),
                  subtitle: favorites.isNotFound(item)
                      ? Text(FavoritesText.notFound, style: TextStyle(color: theme.colorScheme.error))
                      : null,
                  children: [
                    EntryCard(
                      hit: item.hit,
                      pdf: item.pdf,
                      action: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: FavoritesText.deleteTooltip,
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _remove(context, item),
                      ),
                    ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}
