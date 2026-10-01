import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A unified, RTL-aware action button used throughout the network-owner app.
///
/// Guarantees consistent height, radius, padding, font family (Cairo),
/// and icon/text placement for Arabic labels.
class AppButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isLoading;
  final double height;
  final double borderRadius;
  final double fontSize;
  final FontWeight fontWeight;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final EdgeInsetsGeometry padding;

  const AppButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.isLoading = false,
    this.height = 52,
    this.borderRadius = 14,
    this.fontSize = 16,
    this.fontWeight = FontWeight.bold,
    this.backgroundColor,
    this.foregroundColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
  });

  @override
  Widget build(BuildContext context) {
    final effectiveBackground = backgroundColor ?? AppColors.primary;
    final effectiveForeground = foregroundColor ?? Colors.white;

    return SizedBox(
      width: double.infinity,
      height: height,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: effectiveBackground,
          foregroundColor: effectiveForeground,
          elevation: 0,
          padding: padding,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
        ),
        child: isLoading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: effectiveForeground,
                  strokeWidth: 2.5,
                ),
              )
            : Directionality(
                textDirection: TextDirection.rtl,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 20, color: effectiveForeground),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: fontSize,
                        fontWeight: fontWeight,
                        color: effectiveForeground,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
