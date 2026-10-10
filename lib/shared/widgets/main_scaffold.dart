import 'package:flutter/material.dart';
import '../../core/navigation/tab_navigation_controller.dart';
import '../../features/recognition/recognition_screen.dart';
import '../../features/history/history_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/guide/guide_screen.dart';

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    RecognitionScreen(),
    HistoryScreen(),
    NotificationsScreen(),
    GuideScreen(),
  ];

  @override
  void initState() {
    super.initState();
    TabNavigationController.requestedTabIndex.addListener(_onTabRequested);
  }

  @override
  void dispose() {
    TabNavigationController.requestedTabIndex.removeListener(_onTabRequested);
    super.dispose();
  }

  // Nguồn duy nhất cập nhật _currentIndex — cả bấm tay lẫn điều hướng
  // từ overlay đều đi qua notifier này, không set _currentIndex trực
  // tiếp ở đâu khác nữa.
  void _onTabRequested() {
    final requested = TabNavigationController.requestedTabIndex.value;
    if (requested != _currentIndex) {
      setState(() => _currentIndex = requested);
    }
  }

  // Nút tròn giữa thanh dưới: đi thẳng tới tab Nhận diện.
  void _onFabPressed() {
    TabNavigationController.requestedTabIndex.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _onFabPressed,
        elevation: 4,
        tooltip: 'Nhận diện',
        child: const Icon(Icons.shield_outlined, size: 28),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _BottomNav(
        currentIndex: _currentIndex,
        onTap: (i) => TabNavigationController.requestedTabIndex.value = i,
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _BottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      elevation: 8,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavItem(
            icon: Icons.home_outlined,
            activeIcon: Icons.home,
            label: 'Nhận diện',
            selected: currentIndex == 0,
            onTap: () => onTap(0),
          ),
          _NavItem(
            icon: Icons.history_outlined,
            activeIcon: Icons.history,
            label: 'Lịch sử',
            selected: currentIndex == 1,
            onTap: () => onTap(1),
          ),
          const SizedBox(width: 48),
          _NavItem(
            icon: Icons.notifications_outlined,
            activeIcon: Icons.notifications,
            label: 'Thông báo',
            selected: currentIndex == 2,
            onTap: () => onTap(2),
          ),
          _NavItem(
            icon: Icons.menu_book_outlined,
            activeIcon: Icons.menu_book,
            label: 'Hướng dẫn',
            selected: currentIndex == 3,
            onTap: () => onTap(3),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withValues(alpha: 0.5);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? activeIcon : icon, color: color, size: 22),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}