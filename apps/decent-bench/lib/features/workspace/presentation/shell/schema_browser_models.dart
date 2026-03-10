enum SchemaSelectionKind {
  database,
  section,
  table,
  view,
  schemaIndex,
  column,
  constraint,
  trigger,
}

class SchemaSelectionDetails {
  const SchemaSelectionDetails({
    required this.nodeId,
    required this.kind,
    required this.label,
    required this.subtitle,
    required this.summaryRows,
    this.objectName,
    this.definition,
    this.notes = const <String>[],
  });

  final String nodeId;
  final SchemaSelectionKind kind;
  final String label;
  final String subtitle;
  final String? objectName;
  final String? definition;
  final List<MapEntry<String, String>> summaryRows;
  final List<String> notes;
}
