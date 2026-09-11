/// F-002 설정 화면 — 현재 원천자료 정보, 원천자료 update(PDF 두 개), 처음 데이터로 되돌리기.
/// 헤더 '⋮' → '설정'에서 Navigator.push로 연다(CLAUDE.md 화면 전환 구조).
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/dataset_loader.dart';
import '../data/source_update.dart';
import '../parser/models.dart';

/// 화면 문구(테스트가 같은 상수를 본다).
abstract final class SettingsText {
  static const title = '설정';
  static const sourceSection = '현재 원천자료';
  static const bundled = '앱에 들어 있는 데이터';
  static const updated = 'update한 원천자료';
  static const updateSection = '원천자료 update';
  static const updateHelp = '고시가 개정되면 두 PDF를 함께 골라 적용하세요. 이 기기에만 적용됩니다.';
  static const notPicked = '선택 안 함';
  static const pick = '선택';
  static const apply = '적용';
  static const parsing = 'PDF를 읽는 중…';
  static const reset = '처음 데이터로 되돌리기';
  static const resetConfirm = 'update한 원천자료를 지우고 앱에 들어 있던 데이터로 돌아갑니다.';
  static const resetDone = '앱에 들어 있던 데이터로 돌아갔습니다';
  static const resetting = '되돌리는 중…';
  static const cancel = '취소';
  static const keepExisting = '기존 원천자료를 그대로 씁니다.';

  static String pdfLabel(Source src) => '${src.label} PDF';
  static String count(Source src, int n, String? created) =>
      '${src.label} ${_thousands(n)}건${created == null ? '' : ' · PDF ${_date(created)}'}';
  static String appliedAt(String iso) => '적용한 날짜 ${_date(iso, local: true)}';
  static String builtAt(String iso) => '데이터 만든 날짜 ${_date(iso, local: true)}';
  static String applied(Dataset ds, int warnings) =>
      '적용했습니다: ${Source.values.map((s) => '${s.label} ${_thousands(ds.count(s))}건').join(', ')}'
      '${warnings == 0 ? '' : ' (경고 $warnings건 — 로그 참조)'}';
  static String failed(String reason) => '적용하지 않았습니다. $reason. $keepExisting';
}

String _thousands(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');

/// ISO 8601에서 날짜(YYYY-MM-DD)만. [local]이면 기기 시간대로 바꾼 날짜. 형식이 다르면 원문 그대로.
String _date(String iso, {bool local = false}) {
  final t = DateTime.tryParse(iso);
  if (t == null) return iso;
  if (!local) return iso.substring(0, 10); // PDF 생성일은 원문 시간대의 날짜(공유 텍스트와 같은 기준)
  final d = t.toLocal();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// PDF 하나를 고른다. 취소하면 null.
typedef PdfPicker = Future<PickedPdf?> Function();

/// 기본 고르기: 시스템 파일 선택 창(Android: 문서 선택기, 웹: 파일 입력). 권한이 필요 없다.
Future<PickedPdf?> pickPdfWithFilePicker() async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
    withData: true,
  );
  final file = result?.files.single;
  if (file == null) return null;
  final bytes = file.bytes;
  if (bytes == null) throw StateError('"${file.name}"의 내용을 받지 못했습니다');
  return PickedPdf(name: file.name, bytes: bytes);
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller, this.pickPdf = pickPdfWithFilePicker});

  final DataController controller;
  final PdfPicker pickPdf;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final Map<Source, PickedPdf?> _picked = {for (final s in Source.values) s: null};
  /// 작업 중이면 그 표시 문구(적용: 'PDF를 읽는 중…', 되돌리기: '되돌리는 중…'). null이면 한가하다.
  String? _busyText;
  bool get _busy => _busyText != null;

  /// 마지막 적용·되돌리기 결과. [_failed]면 오류색.
  String? _message;
  bool _failed = false;

  void _report(String message, {required bool failed}) {
    if (!mounted) {
      // 결과가 나기 전에 사용자가 화면을 떠났다 — 보여줄 곳이 없으니 로그에 남긴다.
      debugPrint('F-002 결과(설정 화면을 떠나 표시하지 못함): $message');
      return;
    }
    setState(() {
      _message = message;
      _failed = failed;
    });
  }

  Future<void> _pick(Source src) async {
    try {
      final pdf = await widget.pickPdf();
      if (pdf == null) return; // 사용자가 선택 창을 닫았다 — 고른 것 없음, 알릴 것 없음
      if (!mounted) return; // 고르는 사이 화면을 떠났다 — 고른 파일을 쓸 곳이 없다
      setState(() {
        _picked[src] = pdf;
        _message = null;
      });
    } catch (e, st) {
      debugPrint('F-002 PDF 선택 실패: $e\n$st');
      _report('PDF를 가져오지 못했습니다', failed: true);
    }
  }

  Future<void> _apply() async {
    setState(() {
      _busyText = SettingsText.parsing;
      _message = null;
    });
    // 파싱은 동기 계산이라(웹은 수 초) 그동안 화면이 멈춘다 — '읽는 중' 표시가 먼저 그려지게 한 프레임 넘긴다
    // (REQUIREMENTS 비기능 3: 멈춤 허용).
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    try {
      final parsed = parseSourcePdfs(_picked);
      await widget.controller.apply(parsed.dataset);
      _picked.updateAll((_, _) => null);
      _report(SettingsText.applied(parsed.dataset, parsed.warnings.length), failed: false);
    } on UpdateFailure catch (e) {
      _report(SettingsText.failed(e.message), failed: true);
    } catch (e, st) {
      // 저장 실패(용량 한도 등) — 저장본·현재 데이터는 바뀌지 않았다. 원인(경로가 섞일 수 있다)은 로그에만.
      debugPrint('F-002 적용 실패: $e\n$st');
      _report(SettingsText.failed('저장하지 못했습니다'), failed: true);
    } finally {
      if (mounted) setState(() => _busyText = null);
    }
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(SettingsText.reset),
        content: const Text(SettingsText.resetConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text(SettingsText.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text(SettingsText.reset)),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busyText = SettingsText.resetting);
    try {
      await widget.controller.reset();
      _report(SettingsText.resetDone, failed: false);
    } catch (e, st) {
      debugPrint('F-002 되돌리기 실패: $e\n$st');
      _report('되돌리지 못했습니다', failed: true);
    } finally {
      if (mounted) setState(() => _busyText = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(SettingsText.title)),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final data = widget.controller.data;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(SettingsText.sourceSection, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              if (data != null) _SourceInfo(data: data),
              const SizedBox(height: 24),
              Text(SettingsText.updateSection, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(SettingsText.updateHelp, style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              for (final src in Source.values)
                ListTile(
                  key: ValueKey('pick-${src.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.picture_as_pdf_outlined),
                  title: Text(SettingsText.pdfLabel(src)),
                  subtitle: Text(_picked[src]?.name ?? SettingsText.notPicked),
                  trailing: OutlinedButton(
                    onPressed: _busy ? null : () => _pick(src),
                    child: const Text(SettingsText.pick),
                  ),
                ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _apply,
                  icon: const Icon(Icons.upload_file),
                  label: const Text(SettingsText.apply),
                ),
              ),
              if (_busy) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 12),
                    Text(_busyText!),
                  ],
                ),
              ],
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(
                  _message!,
                  style: TextStyle(color: _failed ? theme.colorScheme.error : theme.colorScheme.primary),
                ),
              ],
              const SizedBox(height: 32),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  // 깨진 저장본도 지울 수 있어야 한다(hasStored) — 못 지우면 새 PDF를 올리는 것 말고 빠져나갈 길이 없다
                  onPressed: _busy || !(data?.hasStored ?? false) ? null : _reset,
                  icon: const Icon(Icons.restore),
                  label: const Text(SettingsText.reset),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 번들 / update 중 무엇인지, 표별 건수·PDF 생성일, 적용한 날짜.
class _SourceInfo extends StatelessWidget {
  const _SourceInfo({required this.data});

  final LoadedData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ds = data.dataset;
    final updated = data.origin == DataOrigin.updated;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(updated ? SettingsText.updated : SettingsText.bundled, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            for (final (src, pdf) in [(Source.byeolpyo2, ds.byeolpyo2), (Source.byeolpyo3, ds.byeolpyo3)]) ...[
              Text(SettingsText.count(src, ds.count(src), pdf.created)),
              Text(pdf.file, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 4),
            Text(updated ? SettingsText.appliedAt(ds.extractedAt) : SettingsText.builtAt(ds.extractedAt)),
            if (data.storedError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(data.storedError!, style: TextStyle(color: theme.colorScheme.error)),
              ),
          ],
        ),
      ),
    );
  }
}
