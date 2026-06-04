import 'package:flutter/material.dart';

import 'brand.dart';

/// Primary CTA, ported from the website's `.btn-magnetic`: electric-blue
/// gradient surface, layered inner highlights, and a soft outer glow.
/// Used for the main Connect action.
class MagneticButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;

  /// When true, renders a flat neutral surface instead of the blue gradient
  /// (used for the Disconnect state).
  final bool subdued;

  const MagneticButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.subdued = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.brand;
    final enabled = onPressed != null;

    final decoration = subdued
        ? BoxDecoration(
            color: t.secondary,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.border),
          )
        : BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Brand.hsl(220, 100, 62),
                Brand.hsl(220, 95, 50),
              ],
            ),
            boxShadow: [
              // outer glow
              BoxShadow(
                color: Brand.hsl(220, 95, 45, 0.45),
                blurRadius: 24,
                spreadRadius: -6,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Brand.hsl(220, 95, 45, 0.35),
                blurRadius: 6,
                spreadRadius: -2,
                offset: const Offset(0, 2),
              ),
            ],
          );

    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed,
          child: Ink(
            decoration: decoration,
            child: Container(
              height: 54,
              alignment: Alignment.center,
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  color: subdued ? t.foreground : Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
