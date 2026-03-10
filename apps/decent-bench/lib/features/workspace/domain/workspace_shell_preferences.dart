enum ResultsPaneTab { results, messages, executionPlan }

class WorkspaceShellPreferences {
  static const double _minSplit = 0.18;
  static const double _maxSplit = 0.82;
  static const double _minZoom = 0.8;
  static const double _maxZoom = 1.4;

  const WorkspaceShellPreferences({
    required this.leftColumnFraction,
    required this.leftTopFraction,
    required this.rightTopFraction,
    required this.showSchemaExplorer,
    required this.showPropertiesPane,
    required this.showResultsPane,
    required this.showStatusBar,
    required this.editorZoom,
    required this.activeResultsTab,
  });

  final double leftColumnFraction;
  final double leftTopFraction;
  final double rightTopFraction;
  final bool showSchemaExplorer;
  final bool showPropertiesPane;
  final bool showResultsPane;
  final bool showStatusBar;
  final double editorZoom;
  final ResultsPaneTab activeResultsTab;

  factory WorkspaceShellPreferences.defaults() {
    return const WorkspaceShellPreferences(
      leftColumnFraction: 0.27,
      leftTopFraction: 0.62,
      rightTopFraction: 0.55,
      showSchemaExplorer: true,
      showPropertiesPane: true,
      showResultsPane: true,
      showStatusBar: true,
      editorZoom: 1.0,
      activeResultsTab: ResultsPaneTab.results,
    );
  }

  WorkspaceShellPreferences normalized() {
    return WorkspaceShellPreferences(
      leftColumnFraction: _clampSplit(leftColumnFraction),
      leftTopFraction: _clampSplit(leftTopFraction),
      rightTopFraction: _clampSplit(rightTopFraction),
      showSchemaExplorer: showSchemaExplorer,
      showPropertiesPane: showPropertiesPane,
      showResultsPane: showResultsPane,
      showStatusBar: showStatusBar,
      editorZoom: editorZoom.clamp(_minZoom, _maxZoom),
      activeResultsTab: activeResultsTab,
    );
  }

  WorkspaceShellPreferences copyWith({
    double? leftColumnFraction,
    double? leftTopFraction,
    double? rightTopFraction,
    bool? showSchemaExplorer,
    bool? showPropertiesPane,
    bool? showResultsPane,
    bool? showStatusBar,
    double? editorZoom,
    ResultsPaneTab? activeResultsTab,
  }) {
    return WorkspaceShellPreferences(
      leftColumnFraction: leftColumnFraction ?? this.leftColumnFraction,
      leftTopFraction: leftTopFraction ?? this.leftTopFraction,
      rightTopFraction: rightTopFraction ?? this.rightTopFraction,
      showSchemaExplorer: showSchemaExplorer ?? this.showSchemaExplorer,
      showPropertiesPane: showPropertiesPane ?? this.showPropertiesPane,
      showResultsPane: showResultsPane ?? this.showResultsPane,
      showStatusBar: showStatusBar ?? this.showStatusBar,
      editorZoom: editorZoom ?? this.editorZoom,
      activeResultsTab: activeResultsTab ?? this.activeResultsTab,
    ).normalized();
  }

  static double _clampSplit(double value) {
    return value.clamp(_minSplit, _maxSplit);
  }

  static ResultsPaneTab parseResultsTab(String raw) {
    return switch (raw) {
      'messages' => ResultsPaneTab.messages,
      'execution_plan' => ResultsPaneTab.executionPlan,
      _ => ResultsPaneTab.results,
    };
  }

  static String encodeResultsTab(ResultsPaneTab tab) {
    return switch (tab) {
      ResultsPaneTab.results => 'results',
      ResultsPaneTab.messages => 'messages',
      ResultsPaneTab.executionPlan => 'execution_plan',
    };
  }
}
