import 'package:flutter/material.dart';

import '../db/models.dart';

class CategoryIcon extends StatelessWidget {
  final Category? category;
  final double size;
  const CategoryIcon({super.key, required this.category, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final color = Color(category?.color ?? 0xFFBDBDBD);
    final icon = IconData(
      category?.icon ?? Icons.help_outline.codePoint,
      fontFamily: 'MaterialIcons',
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: color, size: size * 0.55),
    );
  }
}
