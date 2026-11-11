import 'package:flutter/material.dart';
import '../core/app_theme.dart';

/// A titled card with an icon chip — the shared "section" visual language
/// used across the app (icon + heading, content below), so a screen reads
/// as a series of considered sections rather than one long unbroken form.
class SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const SectionCard({super.key, required this.icon, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primarySoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 18, color: AppColors.primaryDark),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  softWrap: true,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
