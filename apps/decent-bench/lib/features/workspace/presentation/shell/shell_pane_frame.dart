import 'package:flutter/material.dart';

import '../../../../app/theme_system/decent_bench_theme_extension.dart';

class ShellPaneFrame extends StatelessWidget {
  const ShellPaneFrame({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.leadingIcon,
    this.actions = const <Widget>[],
    this.toolbar,
    this.padding = const EdgeInsets.all(12),
  });

  final String title;
  final String? subtitle;
  final IconData? leadingIcon;
  final List<Widget> actions;
  final Widget? toolbar;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.decentBenchTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.colors.panelBg,
        border: Border.all(color: tokens.colors.border),
        borderRadius: BorderRadius.circular(tokens.metrics.borderRadius),
      ),
      child: Column(
        children: <Widget>[
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: tokens.colors.panelAltBg,
              border: Border(bottom: BorderSide(color: tokens.colors.border)),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(tokens.metrics.borderRadius),
              ),
            ),
            child: Row(
              children: <Widget>[
                if (leadingIcon != null) ...<Widget>[
                  Icon(leadingIcon, size: 18),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.0,
                          color: tokens.colors.text,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.0,
                            color: tokens.colors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                for (final action in actions) ...<Widget>[
                  action,
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          if (toolbar != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: tokens.toolbar.background,
                border: Border(bottom: BorderSide(color: tokens.colors.border)),
              ),
              child: toolbar,
            ),
          Expanded(
            child: Padding(padding: padding, child: child),
          ),
        ],
      ),
    );
  }
}
