const String kClassicDarkThemeSource = '''
name = "Classic Dark"
id = "classic-dark"
version = "1.0.0"
author = "Decent Bench"
description = "A dense, classic dark desktop theme inspired by traditional database tools."

[compatibility]
min_decent_bench_version = "0.1.0"
max_decent_bench_version = "0.9.x"

[base]
brightness = "dark"

[colors]
window_bg = "#1E1E1E"
panel_bg = "#252526"
panel_alt_bg = "#2D2D30"
surface_bg = "#2A2A2A"
overlay_bg = "#333337"
border = "#3F3F46"
border_strong = "#5A5A66"
text = "#E5E5E5"
text_muted = "#A8A8A8"
text_disabled = "#6E6E6E"
accent = "#7C5CFF"
accent_hover = "#947BFF"
accent_active = "#6246EA"
selection = "#3A3D41"
focus_ring = "#A78BFA"
error = "#E05A5A"
warning = "#D9A441"
success = "#57B36A"
info = "#4FA3D9"

[menu]
bg = "#2D2D30"
text = "#E5E5E5"
text_muted = "#B8B8B8"
item_hover_bg = "#3A3D41"
item_active_bg = "#4A4D52"
separator = "#45454D"
icon = "#CFCFCF"
shortcut = "#9E9E9E"

[toolbar]
bg = "#2B2B2F"
button_bg = "#2F2F34"
button_hover_bg = "#3A3A40"
button_active_bg = "#45454C"
button_text = "#E5E5E5"
button_icon = "#D7D7D7"

[status_bar]
bg = "#2A2A2D"
text = "#D4D4D4"
border_top = "#3E3E44"
success = "#57B36A"
warning = "#D9A441"
error = "#E05A5A"

[sidebar]
bg = "#252526"
header_bg = "#2D2D30"
header_text = "#E5E5E5"
item_text = "#D4D4D4"
item_hover_bg = "#37373D"
item_selected_bg = "#3F3F46"
item_selected_text = "#FFFFFF"
tree_line = "#4A4A50"

[properties]
bg = "#252526"
label = "#BEBEBE"
value = "#E5E5E5"
section_header_bg = "#2F2F34"
section_header_text = "#FFFFFF"

[editor]
bg = "#1E1E1E"
text = "#DCDCDC"
gutter_bg = "#252526"
gutter_text = "#858585"
current_line_bg = "#2A2D2E"
selection_bg = "#264F78"
cursor = "#AEAFAD"
whitespace = "#404040"
indent_guide = "#3A3A3A"
tab_active_bg = "#1E1E1E"
tab_inactive_bg = "#2D2D30"
tab_hover_bg = "#37373D"
tab_active_text = "#FFFFFF"
tab_inactive_text = "#B8B8B8"

[results_grid]
bg = "#1F1F22"
header_bg = "#2D2D30"
header_text = "#F0F0F0"
row_bg = "#1F1F22"
row_alt_bg = "#252529"
row_hover_bg = "#2F2F34"
row_selected_bg = "#3A3D41"
row_selected_text = "#FFFFFF"
grid_line = "#3D3D44"
cell_text = "#E4E4E4"
null_text = "#8C8C8C"

[dialog]
bg = "#252526"
title_text = "#FFFFFF"
body_text = "#D8D8D8"
input_bg = "#1E1E1E"
input_text = "#EAEAEA"
input_border = "#4B4B52"
input_focus_border = "#8B7BFF"

[buttons]
primary_bg = "#7C5CFF"
primary_text = "#FFFFFF"
primary_hover_bg = "#8A6CFF"
secondary_bg = "#34343A"
secondary_text = "#E5E5E5"
secondary_hover_bg = "#404048"
danger_bg = "#A94444"
danger_text = "#FFFFFF"

[sql_syntax]
keyword = "#C586C0"
identifier = "#9CDCFE"
string = "#CE9178"
number = "#B5CEA8"
comment = "#6A9955"
operator = "#D4D4D4"
function = "#DCDCAA"
type = "#4EC9B0"
parameter = "#9CDCFE"
constant = "#569CD6"
error = "#F44747"

[fonts]
ui_family = "Inter"
editor_family = "JetBrains Mono"
ui_size = 13
editor_size = 13
line_height = 1.35

[metrics]
border_radius = 4
pane_padding = 6
control_height = 28
splitter_thickness = 6
icon_size = 16
''';

const String kClassicLightThemeSource = '''
name = "Classic Light"
id = "classic-light"
version = "1.0.0"
author = "Decent Bench"
description = "A dense, classic light desktop theme for practical database work."

[compatibility]
min_decent_bench_version = "0.1.0"
max_decent_bench_version = "0.9.x"

[base]
brightness = "light"

[colors]
window_bg = "#F3F3F5"
panel_bg = "#FFFFFF"
panel_alt_bg = "#F7F7F9"
surface_bg = "#FFFFFF"
overlay_bg = "#F1F1F4"
border = "#C9CBD2"
border_strong = "#AEB3BD"
text = "#1F232A"
text_muted = "#5F6773"
text_disabled = "#9097A3"
accent = "#6B4DFF"
accent_hover = "#7B63FF"
accent_active = "#5638E6"
selection = "#D9E8FF"
focus_ring = "#8E7BFF"
error = "#C64545"
warning = "#B57C18"
success = "#2E8B57"
info = "#2E78C7"

[menu]
bg = "#F7F7F9"
text = "#1F232A"
text_muted = "#646C77"
item_hover_bg = "#E8ECF3"
item_active_bg = "#DCE4F1"
separator = "#D0D4DB"
icon = "#38414C"
shortcut = "#6A7280"

[toolbar]
bg = "#F5F5F7"
button_bg = "#FFFFFF"
button_hover_bg = "#ECEFF5"
button_active_bg = "#DEE5F0"
button_text = "#1F232A"
button_icon = "#38414C"

[status_bar]
bg = "#F1F3F6"
text = "#2B313A"
border_top = "#CCD1D9"
success = "#2E8B57"
warning = "#B57C18"
error = "#C64545"

[sidebar]
bg = "#FFFFFF"
header_bg = "#F3F5F8"
header_text = "#1F232A"
item_text = "#2D333B"
item_hover_bg = "#EEF2F7"
item_selected_bg = "#DCE7F8"
item_selected_text = "#111418"
tree_line = "#C9CED8"

[properties]
bg = "#FFFFFF"
label = "#5A6270"
value = "#1F232A"
section_header_bg = "#EEF2F7"
section_header_text = "#1B2027"

[editor]
bg = "#FFFFFF"
text = "#1F232A"
gutter_bg = "#F5F6F8"
gutter_text = "#8A909A"
current_line_bg = "#F4F8FF"
selection_bg = "#CFE3FF"
cursor = "#1F232A"
whitespace = "#D2D7DE"
indent_guide = "#D7DCE3"
tab_active_bg = "#FFFFFF"
tab_inactive_bg = "#ECEFF4"
tab_hover_bg = "#E2E8F2"
tab_active_text = "#111418"
tab_inactive_text = "#616A76"

[results_grid]
bg = "#FFFFFF"
header_bg = "#F3F5F8"
header_text = "#161B22"
row_bg = "#FFFFFF"
row_alt_bg = "#F8FAFC"
row_hover_bg = "#EEF3FA"
row_selected_bg = "#DCE7F8"
row_selected_text = "#111418"
grid_line = "#D6DAE1"
cell_text = "#1F232A"
null_text = "#8C929C"

[dialog]
bg = "#FFFFFF"
title_text = "#111418"
body_text = "#2C333C"
input_bg = "#FFFFFF"
input_text = "#1F232A"
input_border = "#BFC6D1"
input_focus_border = "#7C67FF"

[buttons]
primary_bg = "#6B4DFF"
primary_text = "#FFFFFF"
primary_hover_bg = "#7A61FF"
secondary_bg = "#EEF1F6"
secondary_text = "#1F232A"
secondary_hover_bg = "#E2E7EF"
danger_bg = "#C64545"
danger_text = "#FFFFFF"

[sql_syntax]
keyword = "#8E24AA"
identifier = "#1565C0"
string = "#A15C2F"
number = "#558B2F"
comment = "#6A737D"
operator = "#1F232A"
function = "#AD7B00"
type = "#00897B"
parameter = "#1565C0"
constant = "#3949AB"
error = "#D32F2F"

[fonts]
ui_family = "Inter"
editor_family = "JetBrains Mono"
ui_size = 13
editor_size = 13
line_height = 1.35

[metrics]
border_radius = 4
pane_padding = 6
control_height = 28
splitter_thickness = 6
icon_size = 16
''';
