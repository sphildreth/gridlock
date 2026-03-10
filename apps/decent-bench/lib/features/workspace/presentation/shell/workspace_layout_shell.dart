import 'package:flutter/material.dart';

import '../../application/workspace_shell_controller.dart';
import '../../domain/workspace_shell_preferences.dart';

class WorkspaceLayoutShell extends StatelessWidget {
  const WorkspaceLayoutShell({
    super.key,
    required this.controller,
    required this.schemaExplorer,
    required this.propertiesPane,
    required this.sqlEditor,
    required this.resultsPane,
  });

  final WorkspaceShellController controller;
  final Widget schemaExplorer;
  final Widget propertiesPane;
  final Widget sqlEditor;
  final Widget resultsPane;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final prefs = controller.preferences;
        return _DesktopSplitPane(
          axis: Axis.horizontal,
          fraction: prefs.leftColumnFraction,
          onFractionChanged: controller.setLeftColumnFraction,
          leading: _buildLeftColumn(prefs),
          trailing: _buildRightColumn(prefs),
        );
      },
    );
  }

  Widget _buildLeftColumn(WorkspaceShellPreferences prefs) {
    final panes = <Widget>[
      if (prefs.showSchemaExplorer) schemaExplorer,
      if (prefs.showPropertiesPane) propertiesPane,
    ];
    if (panes.isEmpty) {
      return const _HiddenPanePlaceholder(
        title: 'Left panes hidden',
        message: 'Use View to show Schema Explorer or Properties again.',
      );
    }
    if (panes.length == 1) {
      return panes.single;
    }
    return _DesktopSplitPane(
      axis: Axis.vertical,
      fraction: prefs.leftTopFraction,
      onFractionChanged: controller.setLeftTopFraction,
      leading: schemaExplorer,
      trailing: propertiesPane,
    );
  }

  Widget _buildRightColumn(WorkspaceShellPreferences prefs) {
    if (!prefs.showResultsPane) {
      return sqlEditor;
    }
    return _DesktopSplitPane(
      axis: Axis.vertical,
      fraction: prefs.rightTopFraction,
      onFractionChanged: controller.setRightTopFraction,
      leading: sqlEditor,
      trailing: resultsPane,
    );
  }
}

class _DesktopSplitPane extends StatelessWidget {
  const _DesktopSplitPane({
    required this.axis,
    required this.fraction,
    required this.leading,
    required this.trailing,
    required this.onFractionChanged,
  });

  final Axis axis;
  final double fraction;
  final Widget leading;
  final Widget trailing;
  final ValueChanged<double> onFractionChanged;

  static const double _handleThickness = 8;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final total = axis == Axis.horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        final available = (total - _handleThickness).clamp(
          0.0,
          double.infinity,
        );
        final minPaneExtent = available < 360 ? available / 2 : 180.0;
        final maxPaneExtent = (available - minPaneExtent).clamp(
          minPaneExtent,
          available,
        );
        final leadingExtent = available == 0
            ? 0.0
            : (available * fraction).clamp(minPaneExtent, maxPaneExtent);
        final trailingExtent = available - leadingExtent;

        final handle = _SplitHandle(
          axis: axis,
          onDrag: (delta) {
            if (available <= 0) {
              return;
            }
            final updated = (leadingExtent + delta) / available;
            onFractionChanged(updated);
          },
        );

        if (axis == Axis.horizontal) {
          return Row(
            children: <Widget>[
              SizedBox(width: leadingExtent, child: leading),
              SizedBox(width: _handleThickness, child: handle),
              SizedBox(width: trailingExtent, child: trailing),
            ],
          );
        }
        return Column(
          children: <Widget>[
            SizedBox(height: leadingExtent, child: leading),
            SizedBox(height: _handleThickness, child: handle),
            SizedBox(height: trailingExtent, child: trailing),
          ],
        );
      },
    );
  }
}

class _SplitHandle extends StatelessWidget {
  const _SplitHandle({required this.axis, required this.onDrag});

  final Axis axis;
  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    final cursor = axis == Axis.horizontal
        ? SystemMouseCursors.resizeColumn
        : SystemMouseCursors.resizeRow;
    final dots = axis == Axis.horizontal ? '::' : '...';
    return MouseRegion(
      cursor: cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) {
          onDrag(axis == Axis.horizontal ? details.delta.dx : details.delta.dy);
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            border: Border(
              left: axis == Axis.horizontal
                  ? BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    )
                  : BorderSide.none,
              right: axis == Axis.horizontal
                  ? BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    )
                  : BorderSide.none,
              top: axis == Axis.vertical
                  ? BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    )
                  : BorderSide.none,
              bottom: axis == Axis.vertical
                  ? BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    )
                  : BorderSide.none,
            ),
          ),
          child: Center(
            child: RotatedBox(
              quarterTurns: axis == Axis.horizontal ? 1 : 0,
              child: Text(
                dots,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HiddenPanePlaceholder extends StatelessWidget {
  const _HiddenPanePlaceholder({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.visibility_off_outlined,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
