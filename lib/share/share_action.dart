/// F-003 공유 실행 — 공유 창을 열고, 열 수 없으면 클립보드에 복사한다(REQUIREMENTS F-003).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

abstract final class ShareText {
  static const tooltip = '공유';
  static const copied = '복사했습니다';
  static const failed = '공유하지 못했습니다';

  /// F-004 행 복사(공유 창을 거치지 않는다).
  static const copyTooltip = '복사';
  static const copyFailed = '복사하지 못했습니다';
}

/// [text]를 공유 창으로 넘긴다. 웹에서 공유 창이 없으면 share_plus가 기본으로 메일(mailto)을 여는데, 그 대신
/// 예외를 받도록 끄고 클립보드 복사로 대체한다.
Future<void> shareOrCopy(BuildContext context, String text) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await SharePlus.instance.share(ShareParams(text: text, mailToFallbackEnabled: false));
    return;
  } catch (e, st) {
    // 공유 창을 못 여는 환경(공유 API 없는 브라우저 등) — 실패를 숨기지 않고 로그를 남긴 뒤 복사로 대체한다.
    debugPrint('공유 창 열기 실패, 클립보드로 대체: $e\n$st');
  }
  try {
    await Clipboard.setData(ClipboardData(text: text));
  } catch (e, st) {
    // 브라우저가 클립보드 쓰기를 막으면(권한 거부 — 2026-09-11 앱 내장 브라우저에서 실측) 둘 다 실패 — 아무 반응 없이 끝내지 않는다.
    debugPrint('클립보드 복사 실패: $e\n$st');
    messenger?.showSnackBar(const SnackBar(content: Text(ShareText.failed)));
    return;
  }
  messenger?.showSnackBar(const SnackBar(content: Text(ShareText.copied)));
}

/// F-004 행 복사: [text](TSV)를 클립보드에만 넣는다. 공유 창은 거치지 않는다 — 목적이 Excel 붙여넣기다.
Future<void> copyToClipboard(BuildContext context, String text) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await Clipboard.setData(ClipboardData(text: text));
  } catch (e, st) {
    // 브라우저가 클립보드 쓰기를 막는 경우 — 아무 반응 없이 끝내지 않는다.
    debugPrint('행 복사 실패: $e\n$st');
    messenger?.showSnackBar(const SnackBar(content: Text(ShareText.copyFailed)));
    return;
  }
  messenger?.showSnackBar(const SnackBar(content: Text(ShareText.copied)));
}
