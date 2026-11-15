import 'dart:ui';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// Primary navigation. Transactions are the core daily task, so they get a
/// tab of their own (they were only reachable from Home's "See all").
/// Budgets stay inside the Transactions screen's Overview tab.
///
/// Slots: 0 Home · 1 Transactions · 2 Loans · 3 Investments · 4 Profile
class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  static const _items = [
    (Icons.home_rounded, 'Home'),
    (Icons.receipt_long_rounded, 'Transactions'),
    (Icons.handshake_rounded, 'Loans'),
    (Icons.savings_rounded, 'Invest'),
    (Icons.person_rounded, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            height: 62,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE4E7EF), width: 0.5),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final slotWidth = constraints.maxWidth / _items.length;
                return Stack(
                  children: [
                    // One highlight pill that slides to the selected tab.
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutCubic,
                      left: currentIndex * slotWidth + 6,
                      top: 6,
                      width: slotWidth - 12,
                      height: 50,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xF0F0F2F6),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryNavy.withOpacity(0.06),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < _items.length; i++)
                          _NavItem(
                            icon: _items[i].$1,
                            label: _items[i].$2,
                            isActive: currentIndex == i,
                            onTap: () => onTap(i),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.primaryNavy : AppColors.primaryNavy.withOpacity(0.4);
    return Expanded(
      child: Semantics(
        button: true,
        selected: isActive,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // The pill behind slides; icon and label just ease their colour.
              TweenAnimationBuilder<Color?>(
                duration: const Duration(milliseconds: 250),
                tween: ColorTween(end: color),
                builder: (context, c, _) => Icon(icon, size: 22, color: c),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
