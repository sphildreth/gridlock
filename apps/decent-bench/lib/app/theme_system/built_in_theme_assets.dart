import 'package:flutter/material.dart';

class BuiltInThemeAsset {
  const BuiltInThemeAsset({
    required this.id,
    required this.name,
    required this.assetPath,
    required this.brightness,
  });

  final String id;
  final String name;
  final String assetPath;
  final Brightness brightness;
}

const List<BuiltInThemeAsset> kBuiltInThemeAssets = <BuiltInThemeAsset>[
  BuiltInThemeAsset(
    id: 'classic-dark',
    name: 'Classic Dark',
    assetPath: 'assets/themes/classic-dark.toml',
    brightness: Brightness.dark,
  ),
  BuiltInThemeAsset(
    id: 'classic-light',
    name: 'Classic Light',
    assetPath: 'assets/themes/classic-light.toml',
    brightness: Brightness.light,
  ),
  BuiltInThemeAsset(
    id: 'slate-workbench',
    name: 'Slate Workbench',
    assetPath: 'assets/themes/slate-workbench.toml',
    brightness: Brightness.dark,
  ),
  BuiltInThemeAsset(
    id: 'steel-workbench',
    name: 'Steel Workbench',
    assetPath: 'assets/themes/steel-workbench.toml',
    brightness: Brightness.dark,
  ),
  BuiltInThemeAsset(
    id: 'dense-graphite',
    name: 'Dense Graphite',
    assetPath: 'assets/themes/dense-graphite.toml',
    brightness: Brightness.dark,
  ),
  BuiltInThemeAsset(
    id: 'nordic-night',
    name: 'Nordic Night',
    assetPath: 'assets/themes/nordic-night.toml',
    brightness: Brightness.dark,
  ),
  BuiltInThemeAsset(
    id: 'harbor-night',
    name: 'Harbor Night',
    assetPath: 'assets/themes/harbor-night.toml',
    brightness: Brightness.dark,
  ),
  BuiltInThemeAsset(
    id: 'midnight-indigo',
    name: 'Midnight Indigo',
    assetPath: 'assets/themes/midnight-indigo.toml',
    brightness: Brightness.dark,
  ),
  BuiltInThemeAsset(
    id: 'soft-graphite',
    name: 'Soft Graphite',
    assetPath: 'assets/themes/soft-graphite.toml',
    brightness: Brightness.dark,
  ),
  BuiltInThemeAsset(
    id: 'retro-mint',
    name: 'Retro Mint',
    assetPath: 'assets/themes/retro-mint.toml',
    brightness: Brightness.dark,
  ),
  BuiltInThemeAsset(
    id: 'dusk-orchid',
    name: 'Dusk Orchid',
    assetPath: 'assets/themes/dusk-orchid.toml',
    brightness: Brightness.dark,
  ),
  BuiltInThemeAsset(
    id: 'enterprise-light',
    name: 'Enterprise Light',
    assetPath: 'assets/themes/enterprise-light.toml',
    brightness: Brightness.light,
  ),
  BuiltInThemeAsset(
    id: 'paper-light',
    name: 'Paper Light',
    assetPath: 'assets/themes/paper-light.toml',
    brightness: Brightness.light,
  ),
  BuiltInThemeAsset(
    id: 'frost-light',
    name: 'Frost Light',
    assetPath: 'assets/themes/frost-light.toml',
    brightness: Brightness.light,
  ),
  BuiltInThemeAsset(
    id: 'mist-light',
    name: 'Mist Light',
    assetPath: 'assets/themes/mist-light.toml',
    brightness: Brightness.light,
  ),
  BuiltInThemeAsset(
    id: 'sandstone-light',
    name: 'Sandstone Light',
    assetPath: 'assets/themes/sandstone-light.toml',
    brightness: Brightness.light,
  ),
  BuiltInThemeAsset(
    id: 'high-contrast-dark',
    name: 'High Contrast Dark',
    assetPath: 'assets/themes/high-contrast-dark.toml',
    brightness: Brightness.dark,
  ),
  BuiltInThemeAsset(
    id: 'high-contrast-light',
    name: 'High Contrast Light',
    assetPath: 'assets/themes/high-contrast-light.toml',
    brightness: Brightness.light,
  ),
  BuiltInThemeAsset(
    id: 'blue-contrast-dark',
    name: 'Blue Contrast Dark',
    assetPath: 'assets/themes/blue-contrast-dark.toml',
    brightness: Brightness.dark,
  ),
  BuiltInThemeAsset(
    id: 'amber-contrast-dark',
    name: 'Amber Contrast Dark',
    assetPath: 'assets/themes/amber-contrast-dark.toml',
    brightness: Brightness.dark,
  ),
];
