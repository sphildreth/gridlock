import 'package:flutter/material.dart';

typedef CsvExportBrowseCallback = Future<String?> Function(String currentPath);

class CsvExportDialogResult {
  const CsvExportDialogResult({
    required this.path,
    required this.delimiter,
    required this.includeHeaders,
  });

  final String path;
  final String delimiter;
  final bool includeHeaders;
}

class CsvExportDialog extends StatefulWidget {
  const CsvExportDialog({
    super.key,
    required this.queryTitle,
    required this.initialPath,
    required this.initialDelimiter,
    required this.initialIncludeHeaders,
    required this.onBrowse,
  });

  final String queryTitle;
  final String initialPath;
  final String initialDelimiter;
  final bool initialIncludeHeaders;
  final CsvExportBrowseCallback onBrowse;

  @override
  State<CsvExportDialog> createState() => _CsvExportDialogState();
}

class _CsvExportDialogState extends State<CsvExportDialog> {
  late final TextEditingController _pathController = TextEditingController(
    text: widget.initialPath,
  );
  late final TextEditingController _delimiterController = TextEditingController(
    text: widget.initialDelimiter,
  );

  late bool _includeHeaders = widget.initialIncludeHeaders;
  String _validationMessage = '';

  @override
  void dispose() {
    _pathController.dispose();
    _delimiterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Export Results as CSV'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Export the current results for ${widget.queryTitle}.'),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _pathController,
                    decoration: const InputDecoration(
                      labelText: 'Destination',
                      hintText: '/tmp/results.csv',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _browseForPath,
                  child: const Text('Browse...'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _delimiterController,
                    decoration: const InputDecoration(labelText: 'Delimiter'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _includeHeaders,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Include header row'),
                    onChanged: (value) {
                      setState(() {
                        _includeHeaders = value ?? true;
                      });
                    },
                  ),
                ),
              ],
            ),
            if (_validationMessage.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _validationMessage,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Export')),
      ],
    );
  }

  Future<void> _browseForPath() async {
    final path = await widget.onBrowse(_pathController.text);
    if (!mounted || path == null) {
      return;
    }
    setState(() {
      _pathController.text = path;
    });
  }

  void _submit() {
    final path = _pathController.text.trim();
    final delimiter = _delimiterController.text;
    if (path.isEmpty) {
      setState(() {
        _validationMessage = 'Choose a CSV destination before exporting.';
      });
      return;
    }
    if (delimiter.isEmpty) {
      setState(() {
        _validationMessage = 'Delimiter cannot be empty.';
      });
      return;
    }

    Navigator.of(context).pop(
      CsvExportDialogResult(
        path: path,
        delimiter: delimiter,
        includeHeaders: _includeHeaders,
      ),
    );
  }
}
