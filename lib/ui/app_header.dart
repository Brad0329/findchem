/// 앱 상단 헤더 — REQUIREMENTS '화면 방향' 3(2026-09-11 사용자 요청).
/// 왼쪽: 아이콘 심볼 + "FindChem". 오른쪽: '⋮' 더보기 → 메뉴(톱니바퀴 '설정').
library;

import 'package:flutter/material.dart';

import 'brand_symbol.dart';

/// 더보기 메뉴 항목. app.dart가 각 화면(F-005 저장 목록, F-002 설정)을 push한다.
enum HeaderMenu { favorites, settings }

/// 메뉴 문구(테스트가 같은 상수를 본다).
abstract final class HeaderText {
  static const favorites = '자주보는 Chem 목록';
  static const settings = '설정';
}

class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  const AppHeader({super.key, this.onMenu, this.showFavorites = false});

  /// 메뉴 항목을 골랐을 때. null이면 항목은 보이되 아무 일도 하지 않는다(로딩·오류 화면의 헤더).
  final ValueChanged<HeaderMenu>? onMenu;

  /// '자주보는 Chem 목록'을 첫 항목으로 보인다. F-005는 앱 전용 — 웹(표 화면)에서는 false.
  final bool showFavorites;

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
          itemBuilder: (context) => [
            if (showFavorites)
              const PopupMenuItem(
                value: HeaderMenu.favorites,
                child: ListTile(
                  leading: Icon(Icons.star),
                  title: Text(HeaderText.favorites),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
            const PopupMenuItem(
              value: HeaderMenu.settings,
              child: ListTile(
                leading: Icon(Icons.settings),
                title: Text(HeaderText.settings),
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
