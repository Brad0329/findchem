/// 설정 저장 — F-007 data.go.kr 인증키·서비스 체크 + **F-008 판정 설정**(Anthropic 키, 모델).
/// 파일 하나를 통째로 읽고 쓴다(SCHEMA.md 'API 키·연동 선택', '판정 설정 — 모델 선택과 사용자 키').
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../assist/llm_client.dart' show AssistModel, bundledAnthropicKey;
import '../data/update_store.dart';

/// 조회 기능(CAS 누르기, 설정 카드 1·2)을 켤지. **오늘은 웹만**(2026-09-14 사용자 결정, REQUIREMENTS F-007 '단계') —
/// 앱은 개발 여부를 확인한 뒤 켠다. 켜고 끄는 분기는 이 값 한 곳이고, 테스트만 직접 넣는다.
const bool apiLookupEnabledByDefault = kIsWeb;

/// F-007 기본 키 — 웹 배포 빌드가 Actions Secret `DATA_GO_KR_KEY`를 `--dart-define=DATA_GO_KR_DEFAULT_KEY`로 넣는다
/// (`.github/workflows/deploy-web.yml`, 이름 대조 테스트 있음). 없으면 빈 문자열 = 기본 키 없음.
/// **배포된 JS에서 공개된다** — 사용자가 감수한 결정(2026-09-14, REQUIREMENTS 비기능 4). 로그·화면에 원문을 쓰지 않는다.
const String bundledDefaultServiceKey = String.fromEnvironment('DATA_GO_KR_DEFAULT_KEY');

/// 조회하는 공공데이터 서비스(화면 순서 = 선언 순서). 파일의 `services` 키는 [name].
enum ChemService {
  chem('화학물질 정보', '규제 분류·고유번호'),
  ghs('유독물 GHS 정보', '신호어·그림문자·H/P 코드'),
  safety('안전관리정보(응급 증상)', '흡입·피부·안구·경구');

  const ChemService(this.label, this.hint);

  final String label;

  /// 설정 카드 2의 체크박스 옆 짧은 설명.
  final String hint;
}

class ApiSettingsController extends ChangeNotifier {
  ApiSettingsController({required this.store, String? defaultKey})
    : defaultKey = (defaultKey ?? bundledDefaultServiceKey).trim();

  final UpdateStore store;

  /// 빌드에 들어간 기본 키(없으면 빈 문자열). 파일에 담지 않는다(SCHEMA.md).
  final String defaultKey;

  bool get hasDefaultKey => defaultKey.isNotEmpty;

  /// 사용자가 저장한 키가 없어 기본 키를 쓰는 중.
  bool get usingDefaultKey => _serviceKey == null && hasDefaultKey;

  /// 조회에 쓸 키: 사용자 키가 우선, 없으면 기본 키, 둘 다 없으면 null.
  String? get effectiveKey => _serviceKey ?? (hasDefaultKey ? defaultKey : null);

  static const formatVersion = 1;

  /// 파일을 읽지 못했을 때 설정 카드 1에 보이는 사유.
  static const unreadableMessage = 'API 설정 파일을 읽지 못했습니다. [삭제]로 지운 뒤 키를 다시 넣으세요';

  String? _serviceKey;
  Map<ChemService, bool> _services = const {};
  String? _loadError;
  Future<void>? _loading;

  // ── F-008 판정 설정(SCHEMA.md '판정 설정 — 모델 선택과 사용자 키', 확정 2026-09-16) ──
  // 같은 파일에 필드 두 개를 더했다. `version`은 1 그대로 — 필드가 없으면 기본값으로 읽으므로
  // 기존 저장본이 그대로 읽히고 마이그레이션이 없다.
  String? _anthropicKey;
  AssistModel _assistModel = AssistModel.fallback;

  /// 사용자가 저장한 Anthropic 키. 없으면 null(기본 키는 [effectiveAnthropicKey]).
  String? get anthropicKey => _anthropicKey;

  /// 판정에 쓸 모델. 저장된 값이 없거나 모르는 값이면 기본값(Opus 5)이고 그 사실은 로그에 남는다.
  AssistModel get assistModel => _assistModel;

  /// 빌드에 들어간 Anthropic 기본 키(없으면 빈 문자열).
  String get defaultAnthropicKey => bundledAnthropicKey.trim();

  bool get hasDefaultAnthropicKey => defaultAnthropicKey.isNotEmpty;

  /// 사용자가 저장한 키가 없어 기본 키를 쓰는 중.
  bool get usingDefaultAnthropicKey => _anthropicKey == null && hasDefaultAnthropicKey;

  /// 판정에 쓸 키: 사용자 키가 우선, 없으면 기본 키, 둘 다 없으면 null(질문을 보내지 않는다).
  String? get effectiveAnthropicKey =>
      _anthropicKey ?? (hasDefaultAnthropicKey ? defaultAnthropicKey : null);

  /// 사용자가 저장한 인증키. 없으면 null(기본 키는 [effectiveKey]).
  String? get serviceKey => _serviceKey;

  /// 파일이 깨졌으면 사유. 이때는 저장·체크 변경을 거부한다(덮으면 깨진 파일의 내용이 사라진다 — F-005 선례).
  String? get loadError => _loadError;

  /// 체크 여부. 파일에 없는 서비스는 체크된 것으로 본다(기본값 — 사용자 결정 2026-09-14).
  bool enabled(ChemService s) => _services[s] ?? true;

  List<ChemService> get enabledServices => [for (final s in ChemService.values) if (enabled(s)) s];

  /// 한 번만 읽는다(여러 곳에서 불러도 같은 Future).
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final text = await store.read();
      if (text != null) _decode(text);
    } catch (e, st) {
      // 예외 문구(FormatException은 원문 일부를 담는다)에 키가 섞일 수 있어 종류만 남긴다.
      debugPrint('F-007 API 설정 파일을 읽지 못함: ${e.runtimeType}\n$st');
      _serviceKey = null;
      _services = const {};
      _anthropicKey = null;
      _assistModel = AssistModel.fallback;
      _loadError = unreadableMessage;
    }
    notifyListeners();
  }

  void _decode(String text) {
    final root = jsonDecode(text);
    if (root is! Map || root['version'] != formatVersion) {
      throw const FormatException('형식 버전이 1이 아니다');
    }
    final key = root['serviceKey'];
    if (key != null && key is! String) throw const FormatException('serviceKey가 문자열이 아니다');
    final anthropic = root['anthropicKey'];
    if (anthropic != null && anthropic is! String) throw const FormatException('anthropicKey가 문자열이 아니다');
    final services = root['services'];
    final next = <ChemService, bool>{};
    if (services is Map) {
      for (final s in ChemService.values) {
        final v = services[s.name];
        if (v is bool) next[s] = v; // 모르는 이름은 무시, 빠진 이름은 기본값(true) — SCHEMA.md
      }
    }
    _serviceKey = (key as String?)?.trim();
    if (_serviceKey?.isEmpty ?? false) _serviceKey = null;
    _anthropicKey = (anthropic as String?)?.trim();
    if (_anthropicKey?.isEmpty ?? false) _anthropicKey = null;
    // 모르는 모델 ID는 기본값으로 떨어지고 그 사실이 로그에 남는다(AssistModel.fromId).
    final model = root['assistModel'];
    _assistModel = AssistModel.fromId(model is String ? model : null);
    _services = next;
  }

  String _encode({
    required String? key,
    required Map<ChemService, bool> services,
    required String? anthropicKey,
    required AssistModel assistModel,
  }) => jsonEncode({
    'version': formatVersion,
    'serviceKey': ?key,
    'services': {for (final s in ChemService.values) s.name: services[s] ?? true},
    'anthropicKey': ?anthropicKey,
    'assistModel': assistModel.id,
  });

  /// 한 번에 파일 하나를 통째로 다시 쓴다. 넘기지 않은 값은 지금 값을 그대로 쓴다
  /// (한 필드만 바꾸려다 옆 필드를 지우는 일이 없게).
  Future<void> _write({
    String? key,
    Map<ChemService, bool>? services,
    String? anthropicKey,
    AssistModel? assistModel,
    bool clearKey = false,
    bool clearAnthropicKey = false,
  }) async {
    await load();
    if (_loadError != null) throw StateError('깨진 API 설정 파일은 덮지 않는다 — [삭제]로 먼저 지운다');
    final nextKey = clearKey ? null : (key ?? _serviceKey);
    final nextServices = services ?? {for (final s in ChemService.values) s: enabled(s)};
    final nextAnthropic = clearAnthropicKey ? null : (anthropicKey ?? _anthropicKey);
    final nextModel = assistModel ?? _assistModel;
    await store.write(
      _encode(key: nextKey, services: nextServices, anthropicKey: nextAnthropic, assistModel: nextModel),
    );
    _serviceKey = nextKey;
    _services = nextServices;
    _anthropicKey = nextAnthropic;
    _assistModel = nextModel;
    notifyListeners();
  }

  /// 키를 저장한다. 실패하면 예외 — 기존 저장은 그대로다.
  Future<void> saveKey(String key) => _write(key: key.trim());

  /// 체크를 바꿔 바로 저장한다. 실패하면 예외 — 체크는 바뀌지 않는다.
  Future<void> setService(ChemService service, bool value) => _write(
    services: {for (final s in ChemService.values) s: s == service ? value : enabled(s)},
  );

  /// F-008 Anthropic 키를 저장한다. 빈 문자열이면 필드를 비운다(파일은 지우지 않는다 — data.go.kr 키가 남아 있다).
  Future<void> saveAnthropicKey(String key) {
    final trimmed = key.trim();
    return trimmed.isEmpty ? _write(clearAnthropicKey: true) : _write(anthropicKey: trimmed);
  }

  /// F-008 Anthropic 키만 지운다. 기본 키가 있으면 기본 키로 돌아간다.
  Future<void> deleteAnthropicKey() => _write(clearAnthropicKey: true);

  /// F-008 판정 모델을 바꿔 바로 저장한다.
  Future<void> setAssistModel(AssistModel model) => _write(assistModel: model);

  /// [삭제]: 파일을 지운다(깨진 파일의 복구 경로이기도 하다). 체크도 기본값으로 돌아가고, 기본 키가 있으면 기본 키를 쓴다.
  Future<void> delete() async {
    await load();
    await store.delete();
    _serviceKey = null;
    _services = const {};
    _anthropicKey = null;
    _assistModel = AssistModel.fallback;
    _loadError = null;
    notifyListeners();
  }
}
