import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

int adaptiveLines(BuildContext context, [int lines = 1]) =>
    MediaQuery.textScalerOf(context).scale(1) > 1.3 ? lines + 1 : lines;

class ResponsiveCenter extends StatelessWidget {
  const ResponsiveCenter(
      {super.key, required this.child, this.maxWidth = 1180});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        heightFactor: 1,
        child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      );
}

bool isWide(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= Breakpoints.expanded;

EdgeInsets pagePadding(BuildContext context, {double top = Space.lg}) {
  final h = switch (windowSizeOf(context)) {
    WindowSize.compact => Space.lg,
    WindowSize.medium => Space.xl,
    _ => Space.xxl,
  };
  return EdgeInsets.fromLTRB(h, top, h, Space.xxl);
}

class CivicAppBar extends StatelessWidget implements PreferredSizeWidget {
  const CivicAppBar(
      {super.key,
      required this.title,
      this.subtitle,
      this.actions,
      this.fallbackLocation});
  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final String? fallbackLocation;

  @override
  Size get preferredSize => Size.fromHeight(subtitle == null ? 60 : 68);

  @override
  Widget build(BuildContext context) {
    final civic = context.civic;
    return AppBar(
      toolbarHeight: preferredSize.height,
      backgroundColor: context.colors.surface,
      scrolledUnderElevation: 2,
      shadowColor: civic.shadow,
      shape: Border(bottom: BorderSide(color: civic.border)),
      flexibleSpace: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: 2,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              civic.heroStart,
              civic.heroEnd,
              civic.heroEnd.withValues(alpha: 0),
            ], stops: const [
              0,
              0.55,
              1
            ]),
          ),
        ),
      ),
      leading:
          fallbackLocation != null && !(ModalRoute.of(context)?.canPop ?? false)
              ? IconButton(
                  tooltip: 'Back to home',
                  icon: const BackButtonIcon(),
                  onPressed: () => context.go(fallbackLocation!),
                )
              : null,
      titleSpacing: Space.lg,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textStyles.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2)),
          if (subtitle != null)
            Text(subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textStyles.bodySmall?.copyWith(
                    color: civic.muted, fontWeight: FontWeight.w500)),
        ],
      ),
      actions: actions,
    );
  }
}

class CivicAppBarAction extends StatelessWidget {
  const CivicAppBarAction(
      {super.key,
      required this.icon,
      required this.label,
      required this.onPressed});
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 400 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return compact
        ? IconButton(tooltip: label, onPressed: onPressed, icon: Icon(icon))
        : TextButton.icon(
            onPressed: onPressed, icon: Icon(icon), label: Text(label));
  }
}

class CivicCard extends StatefulWidget {
  const CivicCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.color,
    this.borderColor,
    this.flat = false,
  });
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final Color? borderColor;

  final bool flat;

  @override
  State<CivicCard> createState() => _CivicCardState();
}

class _CivicCardState extends State<CivicCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final civic = context.civic;
    final interactive = widget.onTap != null;
    return MouseRegion(
      onEnter: interactive ? (_) => setState(() => _hover = true) : null,
      onExit: interactive ? (_) => setState(() => _hover = false) : null,
      child: AnimatedContainer(
        duration: Motion.of(context, Motion.fast),
        curve: Motion.curve,
        decoration: BoxDecoration(
          color: widget.color ?? context.colors.surface,
          borderRadius: Radii.brLg,
          border: Border.all(
              color: _hover
                  ? context.colors.primary.withValues(alpha: 0.5)
                  : (widget.borderColor ?? civic.border)),
          boxShadow: widget.flat ? null : civic.cardShadow,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: Radii.brLg,
            onTap: widget.onTap,
            child: Padding(
                padding: widget.padding ?? const EdgeInsets.all(Space.lg),
                child: widget.child),
          ),
        ),
      ),
    );
  }
}

class CivicHeroCard extends StatelessWidget {
  const CivicHeroCard({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final civic = context.civic;
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(Space.xl),
      decoration: BoxDecoration(
        borderRadius: Radii.brXl,
        gradient: LinearGradient(
          colors: [civic.heroStart, civic.heroEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: civic.cardShadow,
      ),
      child: Stack(children: [
        Positioned(
          right: -40,
          top: -40,
          child: IgnorePointer(
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06)),
            ),
          ),
        ),
        DefaultTextStyle.merge(
            style: const TextStyle(color: Colors.white), child: child),
      ]),
    );
  }
}

class CivicIconBadge extends StatelessWidget {
  const CivicIconBadge(
      {super.key, required this.icon, this.color, this.size = 40});
  final IconData icon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.civic.tone(color ?? context.colors.primary);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          color: context.civic.tint(color ?? context.colors.primary),
          borderRadius: BorderRadius.circular(size * 0.32)),
      child: Icon(icon, color: c, size: size * 0.5),
    );
  }
}

class CivicAvatar extends StatelessWidget {
  const CivicAvatar({super.key, required this.name, this.radius = 18});
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: radius,
        backgroundColor: context.colors.primaryContainer,
        foregroundColor: context.colors.onPrimaryContainer,
        child: Text(
          name.trim().isEmpty ? '?' : name.trim().characters.first,
          style:
              TextStyle(fontWeight: FontWeight.w700, fontSize: radius * 0.85),
        ),
      );
}

class CivicLoadingState extends StatelessWidget {
  const CivicLoadingState({super.key, this.label = 'Loading…'});
  final String label;

  @override
  Widget build(BuildContext context) => Center(
        child: Semantics(
          liveRegion: true,
          label: label,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox.square(
                dimension: 32,
                child: CircularProgressIndicator(strokeWidth: 3)),
            Space.gapMd,
            Text(label, style: TextStyle(color: context.civic.muted)),
          ]),
        ),
      );
}

class CivicEmptyState extends StatelessWidget {
  const CivicEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.xxl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [
                    context.colors.primaryContainer,
                    context.colors.secondaryContainer,
                  ]),
                ),
                child: Icon(icon, size: 40, color: context.colors.primary),
              ),
              Space.gapLg,
              Text(title,
                  style: context.textStyles.titleMedium,
                  textAlign: TextAlign.center),
              Space.gapXs,
              Text(message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.civic.muted)),
              if (action != null) ...[Space.gapLg, action!],
            ]),
          ),
        ),
      );
}

class CivicErrorState extends StatelessWidget {
  const CivicErrorState({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => CivicEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Something went wrong',
        message: message,
        action: onRetry == null
            ? null
            : CivicButton(
                label: 'Try again',
                icon: Icons.refresh,
                variant: CivicButtonVariant.outlined,
                onPressed: onRetry),
      );
}

class CivicSectionHeader extends StatelessWidget {
  const CivicSectionHeader(this.title,
      {super.key, this.subtitle, this.trailing, this.icon});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Space.lg, bottom: Space.md),
        child: Row(children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: context.colors.primary),
            Space.gapSm,
          ],
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: context.textStyles.titleMedium),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(subtitle!,
                      style: context.textStyles.bodySmall
                          ?.copyWith(color: context.civic.muted)),
                ),
            ]),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

class CivicStatCard extends StatelessWidget {
  const CivicStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color,
    this.caption,
    this.onTap,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final String? caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hue = color ?? context.colors.primary;
    return Semantics(
      button: onTap != null,
      label: '$label: $value',
      child: CivicCard(
        onTap: onTap,
        child: Row(children: [
          CivicIconBadge(icon: icon, color: hue, size: 44),
          Space.gapMd,
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: context.textStyles.headlineSmall),
              ),
              Text(label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.textStyles.bodySmall
                      ?.copyWith(color: context.civic.muted)),
              if (caption != null)
                Text(caption!,
                    maxLines: adaptiveLines(context),
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.labelSmall
                        ?.copyWith(color: context.civic.tone(hue))),
            ]),
          ),
          if (onTap != null)
            Icon(Icons.chevron_right, color: context.civic.subtle, size: 20),
        ]),
      ),
    );
  }
}

class AdaptiveGrid extends StatelessWidget {
  const AdaptiveGrid(
      {super.key,
      required this.children,
      this.minTileWidth = 220,
      this.spacing = Space.md});
  final List<Widget> children;
  final double minTileWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        if (children.isEmpty) return const SizedBox.shrink();
        final columns =
            (c.maxWidth / minTileWidth).floor().clamp(1, children.length);
        final width = (c.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children) SizedBox(width: width, child: child)
          ],
        );
      });
}

class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.message,
    this.icon = Icons.info_outline,
    this.color,
    this.title,
  });
  final String message;
  final IconData icon;
  final Color? color;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final hue = context.civic.tone(color ?? context.colors.primary);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: Space.md + 2, vertical: Space.md),
      decoration: BoxDecoration(
        color: context.civic.tint(color ?? context.colors.primary),
        borderRadius: Radii.brMd,
        border: Border.all(color: hue.withValues(alpha: 0.25)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: hue),
        Space.gapSm,
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (title != null)
              Text(title!,
                  style: context.textStyles.labelLarge?.copyWith(color: hue)),
            Text(message,
                style: context.textStyles.bodySmall
                    ?.copyWith(color: hue, height: 1.4)),
          ]),
        ),
      ]),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, required this.color, this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = context.civic.tone(color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: context.civic.tint(color),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: Text.rich(
          TextSpan(children: [
            if (icon != null)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(icon, size: 14, color: fg),
                ),
              ),
            TextSpan(text: label),
          ]),
          maxLines: adaptiveLines(context),
          overflow: TextOverflow.ellipsis,
          style:
              TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class LabeledValue extends StatelessWidget {
  const LabeledValue(this.label, this.value, {super.key, this.icon});
  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: LayoutBuilder(builder: (context, c) {
          final labelText = Text(label,
              style: context.textStyles.bodyMedium
                  ?.copyWith(color: context.civic.muted));
          final valueText = Text(value,
              style: context.textStyles.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600));
          final iconWidget = icon == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(right: Space.sm, top: 1),
                  child: Icon(icon, size: 18, color: context.civic.muted));
          if (c.maxWidth < 300) {
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (iconWidget != null) iconWidget,
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [labelText, valueText])),
            ]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (iconWidget != null) iconWidget,
            SizedBox(width: 112, child: labelText),
            Expanded(child: valueText),
          ]);
        }),
      );
}

enum CivicButtonVariant { filled, tonal, outlined, text, danger }

class CivicButton extends StatelessWidget {
  const CivicButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = CivicButtonVariant.filled,
    this.loading = false,
    this.expand = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final CivicButtonVariant variant;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final onTap = loading ? null : onPressed;
    final iconWidget = loading
        ? const SizedBox.square(
            dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
        : (icon == null ? null : Icon(icon, size: 20));
    final text = Text(label,
        maxLines: adaptiveLines(context),
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center);
    Widget button = switch (variant) {
      CivicButtonVariant.filled => iconWidget == null
          ? FilledButton(onPressed: onTap, child: text)
          : FilledButton.icon(onPressed: onTap, icon: iconWidget, label: text),
      CivicButtonVariant.tonal => iconWidget == null
          ? FilledButton.tonal(onPressed: onTap, child: text)
          : FilledButton.tonalIcon(
              onPressed: onTap, icon: iconWidget, label: text),
      CivicButtonVariant.outlined => iconWidget == null
          ? OutlinedButton(onPressed: onTap, child: text)
          : OutlinedButton.icon(
              onPressed: onTap, icon: iconWidget, label: text),
      CivicButtonVariant.text => iconWidget == null
          ? TextButton(onPressed: onTap, child: text)
          : TextButton.icon(onPressed: onTap, icon: iconWidget, label: text),
      CivicButtonVariant.danger => iconWidget == null
          ? OutlinedButton(
              style: OutlinedButton.styleFrom(
                  foregroundColor: context.colors.error,
                  side: BorderSide(color: context.colors.error)),
              onPressed: onTap,
              child: text)
          : OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  foregroundColor: context.colors.error,
                  side: BorderSide(color: context.colors.error)),
              onPressed: onTap,
              icon: iconWidget,
              label: text),
    };
    if (expand) button = SizedBox(width: double.infinity, child: button);
    return button;
  }
}

class CivicTextField extends StatelessWidget {
  const CivicTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.helper,
    this.error,
    this.icon,
    this.minLines,
    this.maxLines = 1,
    this.maxLength,
    this.onChanged,
    this.keyboardType,
    this.textInputAction,
    this.fieldKey,
  });
  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? helper;
  final String? error;
  final IconData? icon;
  final int? minLines;
  final int maxLines;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) => TextField(
        key: fieldKey,
        controller: controller,
        minLines: minLines,
        maxLines: maxLines,
        maxLength: maxLength,
        onChanged: onChanged,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        scrollPadding: const EdgeInsets.only(bottom: 140),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: error == null ? helper : null,
          errorText: error,
          alignLabelWithHint: maxLines > 1,
          prefixIcon: icon == null ? null : Icon(icon),
        ),
      );
}

void showMessage(BuildContext context, String message, {bool error = false}) {
  final colors = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(children: [
        Icon(error ? Icons.error_outline : Icons.check_circle_outline,
            color: error ? colors.onError : null, size: 20),
        Space.gapSm,
        Expanded(
            child: Text(message,
                style: error ? TextStyle(color: colors.onError) : null)),
      ]),
      backgroundColor: error ? colors.error : null,
    ));
}

Future<String?> promptForText(
  BuildContext context, {
  required String title,
  required String label,
  required String confirmLabel,
  String? hint,
  String initial = '',
  int minLength = 0,
  bool obscure = false,
}) {
  final controller = TextEditingController(text: initial);
  final formKey = GlobalKey<FormState>();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            maxLines: obscure ? 1 : 3,
            obscureText: obscure,
            decoration: InputDecoration(labelText: label, hintText: hint),
            validator: (v) => (v ?? '').trim().length < minLength
                ? 'Please enter at least $minLength characters.'
                : null,
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.pop(
                  context, obscure ? controller.text : controller.text.trim());
            }
          },
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}
