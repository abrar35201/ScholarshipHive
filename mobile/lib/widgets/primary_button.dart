import 'package:flutter/material.dart';
import '../core/app_theme.dart';

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Color? color;
  final Color? textColor;
  final IconData? icon;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.color,
    this.textColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final fg = textColor ?? (color != null ? AppColors.primaryDark : Colors.white);
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: color != null
            ? ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: fg,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              )
            : null,
        child: isLoading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: fg),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
                  Text(label),
                ],
              ),
      ),
    );
  }
}
