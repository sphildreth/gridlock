import 'package:flutter/material.dart';

import '../domain/import_models.dart';

class ImportArchiveChooserDialog extends StatefulWidget {
  const ImportArchiveChooserDialog({
    super.key,
    required this.archivePath,
    required this.wrapperLabel,
    required this.candidates,
  });

  final String archivePath;
  final String wrapperLabel;
  final List<ImportArchiveCandidate> candidates;

  @override
  State<ImportArchiveChooserDialog> createState() =>
      _ImportArchiveChooserDialogState();
}

class _ImportArchiveChooserDialogState
    extends State<ImportArchiveChooserDialog> {
  late String? _selectedEntry = widget.candidates.isEmpty
      ? null
      : widget.candidates.first.entryPath;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.wrapperLabel} Contents'),
      content: SizedBox(
        width: 720,
        child: widget.candidates.isEmpty
            ? const Text(
                'No recognized importable files were found in this archive.',
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Choose the file to continue importing from `${widget.archivePath}`.',
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: widget.candidates.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final candidate = widget.candidates[index];
                        final selected = candidate.entryPath == _selectedEntry;
                        return ListTile(
                          selected: selected,
                          leading: Icon(
                            selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                          ),
                          title: Text(candidate.displayName),
                          subtitle: Text(
                            '${candidate.innerFormatLabel} • ${candidate.supportState.name}',
                          ),
                          onTap: () {
                            setState(() {
                              _selectedEntry = candidate.entryPath;
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: widget.candidates.isEmpty || _selectedEntry == null
              ? null
              : () {
                  final candidate = widget.candidates.firstWhere(
                    (item) => item.entryPath == _selectedEntry,
                  );
                  Navigator.of(context).pop(candidate);
                },
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
