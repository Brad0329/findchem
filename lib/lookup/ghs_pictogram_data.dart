// 생성물: scripts/extract_ghs_pictograms.py (원본 assets/유해성 분류.xlsx) — 손으로 고치지 않는다.

/// GHS 그림문자 코드 → 유해성 분류(엑셀 한 칸의 줄들). 그림은 [ghsPictogramAsset].
const ghsPictogramLabels = <String, List<String>>{
  'GHS01': ['폭발성', '자기반응성', '유기과산화물'],
  'GHS02': ['인화성', '물반응성', '자연발화성'],
  'GHS03': ['산화성'],
  'GHS04': ['고압가스'],
  'GHS05': ['금속부식성', '피부부식성', '심한눈손상성'],
  'GHS06': ['급성독성'],
  'GHS07': ['특정표적 장기독성 1회노출'],
  'GHS08': ['호흡기,피부과민성', '발암성', '생식독성', '표적장기독성'],
  'GHS09': ['수생환경유해성'],
};

String ghsPictogramAsset(String code) => 'assets/data/ghs/$code.png';
