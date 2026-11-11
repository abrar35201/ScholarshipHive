import 'package:flutter/material.dart';

class BrandLogo extends StatelessWidget {
  final double size;
  const BrandLogo({super.key, this.size = 72});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.26),
        child: Image.asset(
          'assets/logo_square.png',
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
