import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/responsive.dart';
import '../browser/book_browser_page.dart';
import '../settings/settings_page.dart';
import '../video/video_browser_page.dart';

/// 主页骨架
/// - 手机（compact）：底部 NavigationBar 切换 漫画/视频/设置
/// - 平板/TV（medium+）：左侧 NavigationRail 常驻，内容区更大
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    BookBrowserPage(),
    VideoBrowserPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final size = windowSizeOf(context);

    if (size == WindowSize.compact) {
      return Scaffold(
        body: _buildBody(),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book),
              label: '漫画',
            ),
            NavigationDestination(
              icon: Icon(Icons.movie_outlined),
              selectedIcon: Icon(Icons.movie),
              label: '视频',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: '设置',
            ),
          ],
        ),
      );
    }

    // 平板 / TV：左侧常驻导航 Rail（横屏大屏时显示文字）
    final extended = size == WindowSize.expanded;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: extended,
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            leading: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 12),
              child: Icon(
                Icons.auto_stories,
                color: AppColors.accent,
                size: 32,
              ),
            ),
            destinations: [
              NavigationRailDestination(
                icon: const Icon(Icons.menu_book_outlined),
                selectedIcon: const Icon(Icons.menu_book),
                label: const Text('漫画'),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.movie_outlined),
                selectedIcon: const Icon(Icons.movie),
                label: const Text('视频'),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.settings_outlined),
                selectedIcon: const Icon(Icons.settings),
                label: const Text('设置'),
              ),
            ],
          ),
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: Theme.of(context).dividerColor,
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  /// IndexedStack 保留各页浏览状态
  Widget _buildBody() {
    return FocusTraversalGroup(
      child: IndexedStack(index: _currentIndex, children: _pages),
    );
  }
}
