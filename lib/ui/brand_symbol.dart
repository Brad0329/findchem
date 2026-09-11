/// 앱 아이콘 심볼(docs/design/findchem_icon.svg)을 화면 안에서 그리는 위젯.
///
/// SVG 경로를 그대로 옮겼다(viewBox 200 기준). SVG 렌더 패키지를 들이지 않기 위해 CustomPainter로 그린다 —
/// 원본 SVG를 고치면 여기도 같이 고쳐야 한다(도형 5개 + 그라데이션 2색).
library;

import 'package:flutter/material.dart';

/// 아이콘 전체(둥근 그라데이션 배경 + 흰 글리프). [size]는 한 변 길이(논리 픽셀).
class BrandSymbol extends StatelessWidget {
  const BrandSymbol({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.square(size), painter: const _BrandSymbolPainter());
  }
}

class _BrandSymbolPainter extends CustomPainter {
  const _BrandSymbolPainter();

  static const _navy = Color(0xFF0B1F4F);
  static const _blue = Color(0xFF2E7FE0);
  static const _liquid = Color(0xFF5AAEF5);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 200; // SVG viewBox 200 → 실제 크기
    canvas.scale(s, s);

    // 배경: 왼쪽 위 남색 → 오른쪽 아래 파랑, 모서리 반지름 44
    const rect = Rect.fromLTWH(0, 0, 200, 200);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(44)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_navy, _blue],
        ).createShader(rect),
    );

    // 플라스크 안 액체
    final liquid = Path()
      ..moveTo(66, 144)
      ..quadraticBezierTo(83, 137, 100, 144)
      ..quadraticBezierTo(117, 151, 134, 144)
      ..lineTo(146, 163)
      ..quadraticBezierTo(150, 170, 142, 170)
      ..lineTo(58, 170)
      ..quadraticBezierTo(50, 170, 54, 163)
      ..close();
    canvas.drawPath(liquid, Paint()..color = _liquid);

    // 플라스크 윤곽(흰 선 5.5)
    final flask = Path()
      ..moveTo(89, 96)
      ..lineTo(89, 114)
      ..lineTo(54, 164)
      ..quadraticBezierTo(50, 170, 58, 170)
      ..lineTo(142, 170)
      ..quadraticBezierTo(150, 170, 146, 164)
      ..lineTo(111, 114)
      ..lineTo(111, 96);
    canvas.drawPath(
      flask,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // 물음표 줄기(흰 선 7) — 플라스크 입구로 이어진다
    final question = Path()
      ..moveTo(82, 50)
      ..quadraticBezierTo(82, 30, 100, 30)
      ..quadraticBezierTo(118, 30, 118, 47)
      ..quadraticBezierTo(118, 58, 108, 64)
      ..quadraticBezierTo(100, 69, 100, 80)
      ..lineTo(100, 96);
    canvas.drawPath(
      question,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round,
    );

    // 물음표의 점(목 안 기포) + 액체 속 기포 2개
    final dot = Paint()..color = Colors.white;
    canvas.drawCircle(const Offset(100, 112), 4.5, dot);
    canvas.drawCircle(const Offset(86, 156), 3.5, dot);
    canvas.drawCircle(const Offset(112, 152), 2.5, dot);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
