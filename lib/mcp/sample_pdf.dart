/// A-001 2차 실험 — 서버가 만든 파일을 Claude(채팅·Cowork)가 받는 길을 재기 위한 시험 PDF.
///
/// 의존성 없이 손으로 조립한 한 쪽짜리 PDF(Helvetica, ASCII 문구만 — 한글 글꼴 내장은 실측 범위 밖).
/// 실측이 끝나면 `sample_pdf` 도구와 함께 지운다(REQUIREMENTS_AGENT A-001 2차).
library;

import 'dart:convert';

const samplePdfName = 'findchem-sample.pdf';
const samplePdfPath = '/files/$samplePdfName';

/// [lines]를 한 쪽에 찍은 PDF 바이트. 줄은 ASCII여야 한다(아니면 ArgumentError).
List<int> buildSamplePdf(List<String> lines) {
  for (final l in lines) {
    if (l.codeUnits.any((c) => c < 0x20 || c > 0x7e)) {
      throw ArgumentError('ASCII 인쇄 문자만 쓸 수 있습니다: $l');
    }
  }
  String esc(String s) => s.replaceAll(r'\', r'\\').replaceAll('(', r'\(').replaceAll(')', r'\)');
  final stream = StringBuffer('BT /F1 14 Tf 72 760 Td 18 TL\n');
  for (final l in lines) {
    stream.write('(${esc(l)}) Tj T*\n');
  }
  stream.write('ET');
  final content = stream.toString();

  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
  ];

  final out = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length); // ASCII만 쓰므로 문자 수 = 바이트 수
    out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = out.length;
  out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    out.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return ascii.encode(out.toString());
}
