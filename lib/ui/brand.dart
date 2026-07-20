import 'package:flutter/material.dart';

/// hideip.net brand tokens, ported 1:1 from the website's `src/index.css`
/// (`:root` = light, `.dark` = dark) and `brand-kit/BRAND.md`.
///
/// Single accent: electric blue. Numbers (IPs, ports, latencies) are always
/// JetBrains Mono. Wordmark/headings use Geist; body uses Inter.
class Brand {
  Brand._();

  // Font families (registered in pubspec.yaml).
  static const String displayFont = 'Geist';

  /// The wordmark face: Onest, same as the website's .font-wordmark.
  static const String wordmarkFont = 'Onest';
  static const String bodyFont = 'Inter';
  static const String monoFont = 'JetBrainsMono';

  /// HSL helper matching CSS `hsl(h s% l%)`. h in degrees, s/l in 0..100.
  static Color hsl(double h, double s, double l, [double opacity = 1]) =>
      HSLColor.fromAHSL(opacity, h, s / 100, l / 100).toColor();

  // --- Accent (same hue both themes, slightly lighter in dark) --------------
  static const accentH = 220.0, accentS = 95.0;
  static Color blue(Brightness b) =>
      hsl(accentH, accentS, b == Brightness.dark ? 62 : 55);

  /// Mono text style for IPs/ports/latencies. tabularFigures keeps digits aligned.
  static const TextStyle mono = TextStyle(
    fontFamily: monoFont,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  // --- Token sets (mirrors index.css) ---------------------------------------
  static BrandTokenSet tokens(Brightness b) =>
      b == Brightness.dark ? _dark : _light;

  // :root  (light)
  static final _light = BrandTokenSet(
    background: hsl(0, 0, 100),
    foreground: hsl(0, 0, 7),
    card: hsl(0, 0, 100),
    cardForeground: hsl(0, 0, 7),
    primary: hsl(220, 95, 55),
    primarySoft: hsl(220, 95, 97),
    secondary: hsl(0, 0, 96),
    muted: hsl(0, 0, 96),
    mutedForeground: hsl(0, 0, 45),
    border: hsl(0, 0, 92),
    destructive: hsl(0, 75, 50),
    success: hsl(152, 60, 38),
  );

  // .dark
  static final _dark = BrandTokenSet(
    background: hsl(0, 0, 6),
    foreground: hsl(0, 0, 96),
    card: hsl(0, 0, 9),
    cardForeground: hsl(0, 0, 96),
    primary: hsl(220, 95, 62),
    primarySoft: hsl(220, 50, 14),
    secondary: hsl(0, 0, 13),
    muted: hsl(0, 0, 13),
    mutedForeground: hsl(0, 0, 62),
    border: hsl(0, 0, 18),
    destructive: hsl(0, 70, 55),
    success: hsl(152, 55, 45),
  );

  /// Build a ThemeData for the given brightness from the token set.
  static ThemeData theme(Brightness brightness) {
    final t = tokens(brightness);
    final scheme = ColorScheme(
      brightness: brightness,
      primary: t.primary,
      onPrimary: Colors.white,
      secondary: t.secondary,
      onSecondary: t.foreground,
      error: t.destructive,
      onError: Colors.white,
      surface: t.card,
      onSurface: t.foreground,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: t.background,
      fontFamily: bodyFont,
      appBarTheme: AppBarTheme(
        backgroundColor: t.background,
        foregroundColor: t.foreground,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: t.card,
        surfaceTintColor: Colors.transparent,
      ),
      textTheme: Typography.material2021(platform: TargetPlatform.android)
          .englishLike
          .apply(
            bodyColor: t.foreground,
            displayColor: t.foreground,
            fontFamily: bodyFont,
          ),
    );
  }
}

/// Resolved color tokens for one theme.
class BrandTokenSet {
  final Color background;
  final Color foreground;
  final Color card;
  final Color cardForeground;
  final Color primary;
  final Color primarySoft;
  final Color secondary;
  final Color muted;
  final Color mutedForeground;
  final Color border;
  final Color destructive;
  final Color success;

  const BrandTokenSet({
    required this.background,
    required this.foreground,
    required this.card,
    required this.cardForeground,
    required this.primary,
    required this.primarySoft,
    required this.secondary,
    required this.muted,
    required this.mutedForeground,
    required this.border,
    required this.destructive,
    required this.success,
  });
}

/// Convenience accessor: `BrandTokens.of(context)` returns the active token set,
/// so widgets can read brand colors without threading brightness manually.
extension BrandTokens on BuildContext {
  BrandTokenSet get brand => Brand.tokens(Theme.of(this).brightness);
}
