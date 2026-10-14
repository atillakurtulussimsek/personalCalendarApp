import 'package:flutter/material.dart';

import 'theme.dart';

/// Shared building blocks of the design system.

/// White card with soft, accent-tinted shadow.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(Space.xl), this.radius = Radii.xl, this.onTap, this.color, this.border, this.shadow = true});

  /// Tighter variant for list rows.
  const AppCard.tight({super.key, required this.child, this.onTap, this.color, this.border, this.shadow = true})
      : padding = const EdgeInsets.all(Space.lg),
        radius = Radii.lg;

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final Color? color;
  final BoxBorder? border;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final r = BorderRadius.circular(radius);
    return Container(
      decoration: BoxDecoration(color: color ?? t.surface, borderRadius: r, boxShadow: shadow ? t.shadow : null, border: border),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(borderRadius: r, onTap: onTap, child: Padding(padding: padding, child: child)),
      ),
    );
  }
}

/// Rounded label: accent (5 % fill, 12 % border) or neutral.
class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, this.icon, this.leading, this.onTap, this.neutral = false, this.color});

  final String label;
  final IconData? icon;
  final Widget? leading;
  final VoidCallback? onTap;
  final bool neutral;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fg = color ?? (neutral ? t.body : t.accent);
    final r = BorderRadius.circular(Radii.lg);
    return Material(
      color: neutral ? t.fill : (color?.withValues(alpha: .08) ?? t.accent5),
      shape: RoundedRectangleBorder(borderRadius: r, side: BorderSide(color: neutral ? Colors.transparent : (color?.withValues(alpha: .16) ?? t.accent12))),
      child: InkWell(
        borderRadius: r,
        onTap: onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: Space.md),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (leading != null) ...[leading!, const SizedBox(width: Space.sm)],
            if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: Space.sm)],
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelMedium?.copyWith(color: fg, fontFeatures: tabularFigures)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Small coloured dot (calendar colour).
class Dot extends StatelessWidget {
  const Dot(this.color, {super.key, this.size = 8});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) =>
      Container(width: size, height: size, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(size / 2)));
}

/// Vertical calendar-colour bar used at the start of event rows.
class ColorBar extends StatelessWidget {
  const ColorBar(this.color, {super.key, this.height = 36});
  final Color color;
  final double height;
  @override
  Widget build(BuildContext context) =>
      Container(width: 4, height: height, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)));
}

/// Big screen title with an optional small line above and trailing actions.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.overline, this.trailing, this.titleSuffix});
  final String title;
  final String? overline;
  final String? titleSuffix;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.sm, Space.lg),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (overline != null) Text(overline!, style: context.text.bodySmall),
            Text.rich(
              TextSpan(text: title, children: [
                if (titleSuffix != null) TextSpan(text: ' $titleSuffix', style: TextStyle(color: t.faint)),
              ]),
              style: context.text.headlineSmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ]),
        ),
        ?trailing,
      ]),
    );
  }
}

/// Section title + optional trailing value ("4 etkinlik").
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing, this.icon, this.color, this.small = false});
  final String title;
  final String? trailing;
  final IconData? icon;
  final Color? color;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final style = small ? context.text.bodySmall?.copyWith(color: color, fontWeight: color != null ? FontWeight.w600 : null) : context.text.titleLarge;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Row(children: [
        if (icon != null) ...[Icon(icon, size: 16, color: color ?? context.tokens.secondary), const SizedBox(width: Space.sm)],
        Expanded(child: Text(title, style: style)),
        if (trailing != null) Text(trailing!, style: context.text.bodySmall?.copyWith(fontFeatures: tabularFigures)),
      ]),
    );
  }
}

/// Guiding empty state: soft glowing icon tile, title, message and example chips.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.examples = const [], this.onExample});
  final IconData icon;
  final String title;
  final String message;
  final List<String> examples;
  final ValueChanged<String>? onExample;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: Space.xl, vertical: Space.huge),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: t.accent5,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [BoxShadow(color: t.accent.withValues(alpha: .12), blurRadius: 32, spreadRadius: 4)],
            ),
            child: Icon(icon, size: 40, color: t.accent),
          ),
          const SizedBox(height: Space.lg),
          Text(title, style: context.text.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: Space.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Text(message, style: context.text.bodyMedium, textAlign: TextAlign.center),
          ),
          if (examples.isNotEmpty) ...[
            const SizedBox(height: Space.lg),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [for (final e in examples) Pill(label: e, onTap: onExample == null ? null : () => onExample!(e))],
            ),
          ],
        ]),
      ),
    );
  }
}

/// The always-visible quick capture bar in the thumb zone.
class CaptureBar extends StatelessWidget {
  const CaptureBar({super.key, required this.hint, required this.onTap});
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.md),
      child: Container(
        height: 56,
        decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(28), boxShadow: t.shadow),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.only(left: Space.xl - 4, right: Space.sm),
              child: Row(children: [
                Icon(Icons.bolt_rounded, color: t.accent, size: 20),
                const SizedBox(width: Space.md),
                Expanded(child: Text(hint, style: context.text.bodyLarge?.copyWith(color: t.faint))),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(20)),
                  child: Icon(Icons.arrow_forward_rounded, color: Theme.of(context).colorScheme.onPrimary, size: 20),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Animated rounded checkbox that "pops" green when completed.
class PopCheck extends StatelessWidget {
  const PopCheck({super.key, required this.value, required this.onChanged, this.danger = false});
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      checked: value,
      button: true,
      child: InkResponse(
        radius: 24,
        onTap: () => onChanged(!value),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: TweenAnimationBuilder<double>(
              key: ValueKey(value),
              tween: Tween(begin: value ? .6 : 1, end: 1),
              duration: const Duration(milliseconds: 320),
              curve: Curves.elasticOut,
              builder: (_, s, child) => Transform.scale(scale: s, child: child),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: value ? t.success : Colors.transparent,
                  borderRadius: BorderRadius.circular(Radii.sm),
                  border: Border.all(color: value ? t.success : (danger ? t.danger : t.ink.withValues(alpha: .24)), width: 2),
                  boxShadow: value ? [BoxShadow(color: t.success.withValues(alpha: .4), blurRadius: 12)] : null,
                ),
                child: value ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Circular progress ring with a centred label ("3/5").
class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.value, required this.label, this.size = 64});
  final double value;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0, 1)),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => Stack(fit: StackFit.expand, children: [
          CircularProgressIndicator(value: 1, strokeWidth: 8, color: t.ink.withValues(alpha: .08)),
          CircularProgressIndicator(value: v, strokeWidth: 8, color: t.success, strokeCap: StrokeCap.round),
          Center(child: Text(label, style: context.text.titleSmall?.copyWith(fontFeatures: tabularFigures))),
        ]),
      ),
    );
  }
}
