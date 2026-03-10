#include "flutter_menu_plugin.h"

#include <gdk/gdkkeysyms.h>

#include <cstring>
#include <optional>
#include <string>

namespace {

constexpr char kChannelName[] = "flutter/menu";
constexpr char kIsPluginAvailableMethod[] = "Menu.isPluginAvailable";
constexpr char kSetMenusMethod[] = "Menu.setMenus";
constexpr char kSelectedCallbackMethod[] = "Menu.selectedCallback";

constexpr char kWindowKey[] = "0";
constexpr char kIdKey[] = "id";
constexpr char kLabelKey[] = "label";
constexpr char kEnabledKey[] = "enabled";
constexpr char kChildrenKey[] = "children";
constexpr char kDividerKey[] = "isDivider";
constexpr char kShortcutCharacterKey[] = "shortcutCharacter";
constexpr char kShortcutTriggerKey[] = "shortcutTrigger";
constexpr char kShortcutModifiersKey[] = "shortcutModifiers";

constexpr int kFlutterShortcutModifierMeta = 1 << 0;
constexpr int kFlutterShortcutModifierShift = 1 << 1;
constexpr int kFlutterShortcutModifierAlt = 1 << 2;
constexpr int kFlutterShortcutModifierControl = 1 << 3;

struct ShortcutInfo {
  guint keyval;
  GdkModifierType modifiers;
};

bool GetBool(FlValue* map, const char* key, bool fallback = false) {
  FlValue* value = fl_value_lookup_string(map, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_BOOL) {
    return fallback;
  }
  return fl_value_get_bool(value);
}

std::optional<gint64> GetInt(FlValue* map, const char* key) {
  FlValue* value = fl_value_lookup_string(map, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_INT) {
    return std::nullopt;
  }
  return fl_value_get_int(value);
}

const gchar* GetString(FlValue* map, const char* key) {
  FlValue* value = fl_value_lookup_string(map, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
    return nullptr;
  }
  return fl_value_get_string(value);
}

std::optional<guint> MapCharacterShortcut(gunichar character) {
  if (g_unichar_isalpha(character)) {
    return gdk_unicode_to_keyval(g_unichar_toupper(character));
  }
  if (g_unichar_isdigit(character)) {
    return gdk_unicode_to_keyval(character);
  }
  switch (character) {
    case '-':
      return GDK_KEY_minus;
    case '=':
      return GDK_KEY_equal;
    default:
      return std::nullopt;
  }
}

std::optional<guint> MapTriggerShortcut(gint64 key_id) {
  switch (key_id) {
    case 0x0010000000d:
      return GDK_KEY_Return;
    case 0x0010000001b:
      return GDK_KEY_Escape;
    case 0x00100000009:
      return GDK_KEY_Tab;
    case 0x00100000008:
      return GDK_KEY_BackSpace;
    case 0x0010000007f:
      return GDK_KEY_Delete;
    case 0x00100000801:
      return GDK_KEY_F1;
    case 0x00100000802:
      return GDK_KEY_F2;
    case 0x00100000803:
      return GDK_KEY_F3;
    case 0x00100000804:
      return GDK_KEY_F4;
    case 0x00100000805:
      return GDK_KEY_F5;
    case 0x00100000806:
      return GDK_KEY_F6;
    case 0x00100000807:
      return GDK_KEY_F7;
    case 0x00100000808:
      return GDK_KEY_F8;
    case 0x00100000809:
      return GDK_KEY_F9;
    case 0x0010000080a:
      return GDK_KEY_F10;
    case 0x0010000080b:
      return GDK_KEY_F11;
    case 0x0010000080c:
      return GDK_KEY_F12;
    default:
      break;
  }
  if (key_id >= 0x00000000030 && key_id <= 0x00000000039) {
    return gdk_unicode_to_keyval(static_cast<gunichar>(key_id));
  }
  if (key_id >= 0x00000000061 && key_id <= 0x0000000007a) {
    return gdk_unicode_to_keyval(g_unichar_toupper(static_cast<gunichar>(key_id)));
  }
  if (key_id == 0x0000000002d) {
    return GDK_KEY_minus;
  }
  if (key_id == 0x0000000003d) {
    return GDK_KEY_equal;
  }
  return std::nullopt;
}

std::optional<ShortcutInfo> BuildShortcutInfo(FlValue* item) {
  if (!GetBool(item, kEnabledKey, false)) {
    return std::nullopt;
  }

  std::optional<guint> keyval;
  const gchar* shortcut_character = GetString(item, kShortcutCharacterKey);
  if (shortcut_character != nullptr && strlen(shortcut_character) > 0) {
    keyval = MapCharacterShortcut(g_utf8_get_char(shortcut_character));
  } else if (const auto trigger = GetInt(item, kShortcutTriggerKey)) {
    keyval = MapTriggerShortcut(*trigger);
  }
  if (!keyval.has_value()) {
    return std::nullopt;
  }

  GdkModifierType modifiers = static_cast<GdkModifierType>(0);
  const gint64 flutter_modifiers =
      GetInt(item, kShortcutModifiersKey).value_or(0);
  if (flutter_modifiers & kFlutterShortcutModifierControl) {
    modifiers = static_cast<GdkModifierType>(modifiers | GDK_CONTROL_MASK);
  }
  if (flutter_modifiers & kFlutterShortcutModifierAlt) {
    modifiers = static_cast<GdkModifierType>(modifiers | GDK_MOD1_MASK);
  }
  if (flutter_modifiers & kFlutterShortcutModifierShift) {
    modifiers = static_cast<GdkModifierType>(modifiers | GDK_SHIFT_MASK);
  }
  if (flutter_modifiers & kFlutterShortcutModifierMeta) {
    modifiers = static_cast<GdkModifierType>(modifiers | GDK_META_MASK);
  }

  return ShortcutInfo{*keyval, modifiers};
}

}  // namespace

FlutterMenuPlugin::FlutterMenuPlugin(FlBinaryMessenger* messenger,
                                     GtkWindow* window,
                                     GtkBox* container)
    : window_(window), container_(container) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  channel_ =
      fl_method_channel_new(messenger, kChannelName, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel_, MethodCallHandler, this,
                                            nullptr);

  accel_group_ = gtk_accel_group_new();
  gtk_window_add_accel_group(window_, accel_group_);
}

FlutterMenuPlugin::~FlutterMenuPlugin() {
  ClearMenu();
  gtk_window_remove_accel_group(window_, accel_group_);
  g_object_unref(accel_group_);
  g_object_unref(channel_);
}

void FlutterMenuPlugin::MethodCallHandler(FlMethodChannel* channel,
                                          FlMethodCall* method_call,
                                          gpointer user_data) {
  auto* self = static_cast<FlutterMenuPlugin*>(user_data);
  g_autoptr(FlMethodResponse) response = self->HandleMethodCall(method_call);
  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to send menu response: %s", error->message);
  }
}

void FlutterMenuPlugin::MenuItemActivated(GtkWidget* widget, gpointer user_data) {
  auto* self = static_cast<FlutterMenuPlugin*>(user_data);
  auto* flutter_id =
      static_cast<gint64*>(g_object_get_data(G_OBJECT(widget), "flutter-menu-id"));
  if (flutter_id == nullptr) {
    return;
  }
  self->SendSelection(*flutter_id);
}

FlMethodResponse* FlutterMenuPlugin::HandleMethodCall(FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);
  if (strcmp(method, kIsPluginAvailableMethod) == 0) {
    g_autoptr(FlValue) value = fl_value_new_bool(TRUE);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(value));
  }
  if (strcmp(method, kSetMenusMethod) == 0) {
    RebuildMenu(fl_method_call_get_args(method_call));
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }
  return FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
}

void FlutterMenuPlugin::RebuildMenu(FlValue* arguments) {
  ClearMenu();
  if (arguments == nullptr || fl_value_get_type(arguments) != FL_VALUE_TYPE_MAP) {
    return;
  }

  FlValue* menu_items = fl_value_lookup_string(arguments, kWindowKey);
  if (menu_items == nullptr || fl_value_get_type(menu_items) != FL_VALUE_TYPE_LIST) {
    return;
  }

  menu_bar_ = BuildMenuBar(menu_items);
  if (menu_bar_ == nullptr) {
    return;
  }
  gtk_box_pack_start(container_, menu_bar_, FALSE, FALSE, 0);
  gtk_box_reorder_child(container_, menu_bar_, 0);
  gtk_widget_show_all(menu_bar_);
}

GtkWidget* FlutterMenuPlugin::BuildMenuBar(FlValue* menu_items) {
  GtkWidget* menu_bar = gtk_menu_bar_new();
  const size_t length = fl_value_get_length(menu_items);
  for (size_t i = 0; i < length; i++) {
    FlValue* item = fl_value_get_list_value(menu_items, i);
    GtkWidget* menu_item = BuildMenuItem(item);
    if (menu_item != nullptr) {
      gtk_menu_shell_append(GTK_MENU_SHELL(menu_bar), menu_item);
    }
  }
  return menu_bar;
}

GtkWidget* FlutterMenuPlugin::BuildMenuItem(FlValue* item) {
  if (item == nullptr || fl_value_get_type(item) != FL_VALUE_TYPE_MAP) {
    return nullptr;
  }
  if (GetBool(item, kDividerKey, false)) {
    return gtk_separator_menu_item_new();
  }

  const gchar* raw_label = GetString(item, kLabelKey);
  GtkWidget* menu_item =
      gtk_menu_item_new_with_label(raw_label == nullptr ? "" : raw_label);

  if (const auto flutter_id = GetInt(item, kIdKey)) {
    auto* flutter_id_ptr = g_new(gint64, 1);
    *flutter_id_ptr = *flutter_id;
    g_object_set_data_full(G_OBJECT(menu_item), "flutter-menu-id",
                           flutter_id_ptr, g_free);
  }

  FlValue* children = fl_value_lookup_string(item, kChildrenKey);
  if (children != nullptr && fl_value_get_type(children) == FL_VALUE_TYPE_LIST &&
      fl_value_get_length(children) > 0) {
    GtkWidget* submenu = gtk_menu_new();
    const size_t length = fl_value_get_length(children);
    for (size_t i = 0; i < length; i++) {
      GtkWidget* child = BuildMenuItem(fl_value_get_list_value(children, i));
      if (child != nullptr) {
        gtk_menu_shell_append(GTK_MENU_SHELL(submenu), child);
      }
    }
    gtk_menu_item_set_submenu(GTK_MENU_ITEM(menu_item), submenu);
  } else if (GetBool(item, kEnabledKey, false)) {
    g_signal_connect(menu_item, "activate", G_CALLBACK(MenuItemActivated), this);
    if (const auto shortcut = BuildShortcutInfo(item)) {
      gtk_widget_add_accelerator(menu_item, "activate", accel_group_,
                                 shortcut->keyval, shortcut->modifiers,
                                 GTK_ACCEL_VISIBLE);
    }
  }

  gtk_widget_set_sensitive(menu_item, GetBool(item, kEnabledKey, true));
  return menu_item;
}

void FlutterMenuPlugin::SendSelection(gint64 flutter_id) {
  g_autoptr(FlValue) arguments = fl_value_new_int(flutter_id);
  fl_method_channel_invoke_method(channel_, kSelectedCallbackMethod, arguments,
                                  nullptr, nullptr, nullptr);
}

void FlutterMenuPlugin::ClearMenu() {
  if (menu_bar_ != nullptr) {
    gtk_container_remove(GTK_CONTAINER(container_), menu_bar_);
    menu_bar_ = nullptr;
  }
}
