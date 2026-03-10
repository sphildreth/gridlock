import 'package:flutter/material.dart';

import '../../../../app/theme_system/decent_bench_theme_extension.dart';

class StatusBar extends StatelessWidget {
  const StatusBar({
    super.key,
    required this.statusMessage,
    required this.workspaceLabel,
    required this.lastExecutionLabel,
    required this.rowsLabel,
    required this.editorModeLabel,
  });

  final String statusMessage;
  final String workspaceLabel;
  final String lastExecutionLabel;
  final String rowsLabel;
  final String editorModeLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.decentBenchTheme;
    return Container(
      width: double.infinity,
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: tokens.statusBar.background,
        border: Border(top: BorderSide(color: tokens.statusBar.borderTop)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              statusMessage,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: tokens.statusBar.text,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _StatusDivider(),
                  Text(
                    workspaceLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.statusBar.text,
                    ),
                  ),
                  _StatusDivider(),
                  Text(
                    lastExecutionLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.statusBar.text,
                    ),
                  ),
                  _StatusDivider(),
                  Text(
                    rowsLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.statusBar.text,
                    ),
                  ),
                  _StatusDivider(),
                  Text(
                    editorModeLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.statusBar.text,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusDivider extends StatelessWidget {
  const _StatusDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 16,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: context.decentBenchTheme.statusBar.borderTop,
    );
  }
}
