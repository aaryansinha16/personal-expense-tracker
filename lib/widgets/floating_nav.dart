import 'package:flutter/material.dart';

class FloatingNavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int? badge;

  const FloatingNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badge,
  });
}

class FloatingNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final List<FloatingNavItem> items;

  const FloatingNav({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isLight = theme.brightness == Brightness.light;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: theme.cardTheme.color,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isLight ? 0.1 : 0.4),
                blurRadius: 28,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (var i = 0; i < items.length; i++)
                _NavButton(
                  item: items[i],
                  selected: i == selectedIndex,
                  onTap: () => onSelect(i),
                  activeColor: scheme.primary,
                  inactiveColor: scheme.onSurface.withOpacity(0.55),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final FloatingNavItem item;
  final bool selected;
  final VoidCallback onTap;
  final Color activeColor;
  final Color inactiveColor;

  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? activeColor : inactiveColor;
    final icon = Icon(selected ? item.selectedIcon : item.icon, color: color, size: 22);
    final badge = item.badge ?? 0;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: selected ? activeColor.withOpacity(0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(26),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              badge > 0
                  ? Badge.count(count: badge, alignment: Alignment.topRight, child: icon)
                  : icon,
              const SizedBox(height: 2),
              Text(
                item.label,
                style: TextStyle(
                  color: color,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
