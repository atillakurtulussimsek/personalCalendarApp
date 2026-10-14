import 'package:flutter/material.dart';

/// Design system (docs/design/mockups.html):
/// * one family (Inter), four sizes (28 / 17 / 15 / 13), two weights (400 / 600)
/// * 8-point spacing, 60/30/10 colour split, soft tinted shadows
/// * text hierarchy through ink opacity: 100 % titles, 80 % body, 60 % secondary

class Space {
  Space._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double huge = 48;
}

class Radii {
  Radii._();
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double pill = 999;
}

/// Colours that are not part of [ColorScheme].
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.ink,
    required this.bg,
    required this.surface,
    required this.accent,
    required this.success,
    required this.danger,
    required this.line,
    required this.shadow,
  });

  final Color ink;
  final Color bg;
  final Color surface;
  final Color accent;
  final Color success;
  final Color danger;
  final Color line;
  final List<BoxShadow> shadow;

  Color get body => ink.withValues(alpha: .8);
  Color get secondary => ink.withValues(alpha: .6);
  Color get faint => ink.withValues(alpha: .4);
  Color get accent5 => accent.withValues(alpha: .06);
  Color get accent12 => accent.withValues(alpha: .12);
  Color get fill => ink.withValues(alpha: .04);

  static const light = AppTokens(
    ink: Color(0xFF111827),
    bg: Color(0xFFF6F7FB),
    surface: Colors.white,
    accent: Color(0xFF4F5BD5),
    success: Color(0xFF16A34A),
    danger: Color(0xFFDC2626),
    line: Color(0x14111827),
    shadow: [
      BoxShadow(color: Color(0x144F5BD5), blurRadius: 24, offset: Offset(0, 8)),
      BoxShadow(color: Color(0x0A111827), blurRadius: 2, offset: Offset(0, 1)),
    ],
  );

  static const dark = AppTokens(
    ink: Color(0xFFF1F3F8),
    bg: Color(0xFF0E1016),
    surface: Color(0xFF171A22),
    accent: Color(0xFF8C96FF),
    success: Color(0xFF22C55E),
    danger: Color(0xFFF87171),
    line: Color(0x14F1F3F8),
    shadow: [BoxShadow(color: Color(0x59000000), blurRadius: 24, offset: Offset(0, 8))],
  );

  @override
  AppTokens copyWith() => this;

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) => t < .5 ? this : (other as AppTokens? ?? this);
}

extension AppThemeX on BuildContext {
  AppTokens get tokens => Theme.of(this).extension<AppTokens>() ?? AppTokens.light;
  TextTheme get text => Theme.of(this).textTheme;
}

/// The four type sizes. Use these, not ad-hoc font sizes.
class TypeScale {
  TypeScale._();
  static const double xl = 28;
  static const double lg = 17;
  static const double md = 15;
  static const double sm = 13;
}

ThemeData _build(AppTokens t, Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: t.accent, brightness: b).copyWith(
    primary: t.accent,
    onPrimary: b == Brightness.light ? Colors.white : const Color(0xFF0E1016),
    surface: t.surface,
    onSurface: t.ink,
    error: t.danger,
    outline: t.faint,
    outlineVariant: t.line,
    surfaceContainerHighest: t.fill,
  );
  TextStyle s(double size, FontWeight w, Color c, {double? spacing, double height = 1.35}) =>
      TextStyle(fontFamily: 'Inter', fontSize: size, fontWeight: w, color: c, letterSpacing: spacing, height: height);
  final textTheme = TextTheme(
    // xl — screen titles and big numbers
    displaySmall: s(TypeScale.xl, FontWeight.w600, t.ink, spacing: -.5, height: 1.2),
    headlineSmall: s(TypeScale.xl, FontWeight.w600, t.ink, spacing: -.5, height: 1.2),
    // lg — section and card titles
    titleLarge: s(TypeScale.lg, FontWeight.w600, t.ink),
    titleMedium: s(TypeScale.lg, FontWeight.w600, t.ink),
    // md — body
    bodyLarge: s(TypeScale.md, FontWeight.w400, t.body),
    bodyMedium: s(TypeScale.md, FontWeight.w400, t.body),
    titleSmall: s(TypeScale.md, FontWeight.w600, t.ink),
    labelLarge: s(TypeScale.md, FontWeight.w600, t.ink),
    // sm — secondary
    bodySmall: s(TypeScale.sm, FontWeight.w400, t.secondary),
    labelMedium: s(TypeScale.sm, FontWeight.w600, t.secondary),
    labelSmall: s(TypeScale.sm, FontWeight.w400, t.secondary),
  );
  final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg));
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    fontFamily: 'Inter',
    colorScheme: scheme,
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.bg,
    textTheme: textTheme,
    extensions: [t],
    dividerTheme: DividerThemeData(color: t.line, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: t.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: textTheme.titleLarge,
      foregroundColor: t.ink,
    ),
    cardTheme: CardThemeData(
      color: t.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xl)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: Space.xl),
        shape: buttonShape,
        textStyle: textTheme.labelLarge,
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: t.accent,
        backgroundColor: t.accent5,
        side: BorderSide(color: t.accent12),
        shape: buttonShape,
        textStyle: textTheme.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(44, 44), shape: buttonShape, textStyle: textTheme.labelLarge),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.fill,
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.lg),
      hintStyle: textTheme.bodyLarge?.copyWith(color: t.faint),
      labelStyle: textTheme.bodySmall,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.lg), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.lg), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.lg), borderSide: BorderSide(color: t.accent, width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.lg), borderSide: BorderSide(color: t.danger)),
      prefixIconColor: t.faint,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: t.accent5,
      selectedColor: t.accent12,
      side: BorderSide(color: t.accent12),
      labelStyle: textTheme.labelMedium?.copyWith(color: t.accent),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      padding: const EdgeInsets.symmetric(horizontal: Space.xs),
      iconTheme: IconThemeData(color: t.accent, size: 16),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: t.accent12,
      height: 72,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
            color: s.contains(WidgetState.selected) ? t.accent : t.secondary,
          )),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? t.accent : t.secondary)),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: t.surface,
      indicatorColor: t.accent12,
      selectedIconTheme: IconThemeData(color: t.accent),
      unselectedIconTheme: IconThemeData(color: t.secondary),
      selectedLabelTextStyle: textTheme.labelMedium?.copyWith(color: t.accent),
      unselectedLabelTextStyle: textTheme.labelSmall,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        side: const WidgetStatePropertyAll(BorderSide.none),
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.surface : t.fill),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.ink : t.secondary),
        textStyle: WidgetStatePropertyAll(textTheme.labelMedium),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md))),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm)),
      side: BorderSide(color: t.ink.withValues(alpha: .24), width: 2),
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.success : Colors.transparent),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: t.ink.withValues(alpha: .16),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xl)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: b == Brightness.light ? const Color(0xFF111827) : const Color(0xFF262A36),
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      actionTextColor: const Color(0xFFA5ADFF),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.accent : t.ink.withValues(alpha: .12)),
    ),
    listTileTheme: ListTileThemeData(iconColor: t.secondary, titleTextStyle: textTheme.bodyLarge, subtitleTextStyle: textTheme.bodySmall),
    popupMenuTheme: PopupMenuThemeData(color: t.surface, surfaceTintColor: Colors.transparent, textStyle: textTheme.bodyMedium),
  );
}

ThemeData lightTheme() => _build(AppTokens.light, Brightness.light);
ThemeData darkTheme() => _build(AppTokens.dark, Brightness.dark);

Color colorFromHex(String hex) {
  final h = hex.replaceFirst('#', '');
  return Color(int.parse(h.length == 6 ? 'FF$h' : h, radix: 16));
}

const tabularFigures = [FontFeature.tabularFigures()];
