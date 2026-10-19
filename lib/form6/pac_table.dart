/// A-010 위험노출수준 원천 표(ERPG·AEGL·PAC·IDLH) — 형식은 원천 조사 결과로 채운다.
///
/// **Flutter를 import하지 않는다.**
library;

/// CAS → 위험노출수준 칸(있는 값 전부, D6).
abstract class PacTable {
  Map<String, Object?> fieldOf(String cas);
}
