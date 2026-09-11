/// 앱 상단 헤더 — REQUIREMENTS '화면 방향' 3(2026-09-11 사용자 요청).
/// 왼쪽: 아이콘 심볼 + "FindChem". 오른쪽: '⋮' 더보기 → 메뉴(톱니바퀴 '설정').
library;

import 'package:flutter/material.dart';

import 'brand_symbol.dart';

/// 더보기 메뉴 항목. 설정 화면은 F-002(Phase 005)에서 붙는다.
enum HeaderMenu { settings }

class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  const AppHeader({super.key, this.onMenu});

  /// 메뉴 항목을 골랐을 때. null이면 항목은 보이되 아무 일도 하지 않는다(설정 화면 미구현).
  final ValueChanged<HeaderMenu>? onMenu;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      titleSpacing: 16,
      title: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BrandSymbol(size: 28),
          SizedBox(width: 10),
          Text('FindChem'),
        ],
      ),
      actions: [
        PopupMenuButton<HeaderMenu>(
          icon: const Icon(Icons.more_vert),
          tooltip: '더보기',
          onSelected: onMenu,
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: HeaderMenu.settings,
              child: ListTile(
                leading: Icon(Icons.settings),
                title: Text('설정'),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
