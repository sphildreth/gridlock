#include "flutter_menu_plugin.h"

#include <flutter/encodable_value.h>

#include <cctype>
#include <cwctype>
#include <optional>
#include <string>
#include <utility>
#include <vector>

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

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

std::wstring Utf8ToWide(const std::string& input) {
  if (input.empty()) {
    return std::wstring();
  }
  const int size_needed =
      MultiByteToWideChar(CP_UTF8, 0, input.c_str(), -1, nullptr, 0);
  std::wstring output(size_needed > 0 ? size_needed - 1 : 0, L'\0');
  if (!output.empty()) {
    MultiByteToWideChar(CP_UTF8, 0, input.c_str(), -1, output.data(),
                        size_needed);
  }
  return output;
}

const EncodableValue* FindValue(const EncodableMap& map, const char* key) {
  const auto iterator = map.find(EncodableValue(std::string(key)));
  if (iterator == map.end()) {
    return nullptr;
  }
  return &iterator->second;
}

std::optional<bool> GetBool(const EncodableMap& map, const char* key) {
  const EncodableValue* value = FindValue(map, key);
  if (value == nullptr) {
    return std::nullopt;
  }
  if (const auto* bool_value = std::get_if<bool>(value)) {
    return *bool_value;
  }
  return std::nullopt;
}

std::optional<int64_t> GetInt64(const EncodableMap& map, const char* key) {
  const EncodableValue* value = FindValue(map, key);
  if (value == nullptr) {
    return std::nullopt;
  }
  if (const auto* int32_value = std::get_if<int32_t>(value)) {
    return *int32_value;
  }
  if (const auto* int64_value = std::get_if<int64_t>(value)) {
    return *int64_value;
  }
  return std::nullopt;
}

std::optional<std::string> GetString(const EncodableMap& map, const char* key) {
  const EncodableValue* value = FindValue(map, key);
  if (value == nullptr) {
    return std::nullopt;
  }
  if (const auto* string_value = std::get_if<std::string>(value)) {
    return *string_value;
  }
  return std::nullopt;
}

const EncodableList* GetList(const EncodableMap& map, const char* key) {
  const EncodableValue* value = FindValue(map, key);
  if (value == nullptr) {
    return nullptr;
  }
  return std::get_if<EncodableList>(value);
}

bool IsDivider(const EncodableMap& map) {
  return GetBool(map, kDividerKey).value_or(false);
}

std::optional<std::pair<WORD, std::wstring>> MapCharacterShortcut(
    wchar_t character) {
  if (character >= L'a' && character <= L'z') {
    return std::make_pair(
        static_cast<WORD>(std::towupper(character)),
        std::wstring(1, static_cast<wchar_t>(std::towupper(character))));
  }
  if (character >= L'A' && character <= L'Z') {
    return std::make_pair(static_cast<WORD>(character),
                          std::wstring(1, character));
  }
  if (character >= L'0' && character <= L'9') {
    return std::make_pair(static_cast<WORD>(character),
                          std::wstring(1, character));
  }
  switch (character) {
    case L'-':
      return std::make_pair(static_cast<WORD>(VK_OEM_MINUS), L"-");
    case L'=':
      return std::make_pair(static_cast<WORD>(VK_OEM_PLUS), L"=");
    default:
      return std::nullopt;
  }
}

std::optional<std::pair<WORD, std::wstring>> MapTriggerShortcut(int64_t key_id) {
  switch (key_id) {
    case 0x0010000000d:
      return std::make_pair(static_cast<WORD>(VK_RETURN), L"Enter");
    case 0x0010000001b:
      return std::make_pair(static_cast<WORD>(VK_ESCAPE), L"Esc");
    case 0x00100000009:
      return std::make_pair(static_cast<WORD>(VK_TAB), L"Tab");
    case 0x00100000008:
      return std::make_pair(static_cast<WORD>(VK_BACK), L"Backspace");
    case 0x0010000007f:
      return std::make_pair(static_cast<WORD>(VK_DELETE), L"Delete");
    case 0x00100000801:
      return std::make_pair(static_cast<WORD>(VK_F1), L"F1");
    case 0x00100000802:
      return std::make_pair(static_cast<WORD>(VK_F2), L"F2");
    case 0x00100000803:
      return std::make_pair(static_cast<WORD>(VK_F3), L"F3");
    case 0x00100000804:
      return std::make_pair(static_cast<WORD>(VK_F4), L"F4");
    case 0x00100000805:
      return std::make_pair(static_cast<WORD>(VK_F5), L"F5");
    case 0x00100000806:
      return std::make_pair(static_cast<WORD>(VK_F6), L"F6");
    case 0x00100000807:
      return std::make_pair(static_cast<WORD>(VK_F7), L"F7");
    case 0x00100000808:
      return std::make_pair(static_cast<WORD>(VK_F8), L"F8");
    case 0x00100000809:
      return std::make_pair(static_cast<WORD>(VK_F9), L"F9");
    case 0x0010000080a:
      return std::make_pair(static_cast<WORD>(VK_F10), L"F10");
    case 0x0010000080b:
      return std::make_pair(static_cast<WORD>(VK_F11), L"F11");
    case 0x0010000080c:
      return std::make_pair(static_cast<WORD>(VK_F12), L"F12");
    default:
      break;
  }
  if (key_id >= 0x00000000030 && key_id <= 0x00000000039) {
    return std::make_pair(static_cast<WORD>(key_id),
                          std::wstring(1, static_cast<wchar_t>(key_id)));
  }
  if (key_id >= 0x00000000061 && key_id <= 0x0000000007a) {
    const wchar_t upper = static_cast<wchar_t>(std::towupper(key_id));
    return std::make_pair(static_cast<WORD>(upper), std::wstring(1, upper));
  }
  if (key_id == 0x0000000002d) {
    return std::make_pair(static_cast<WORD>(VK_OEM_MINUS), L"-");
  }
  if (key_id == 0x0000000003d) {
    return std::make_pair(static_cast<WORD>(VK_OEM_PLUS), L"=");
  }
  return std::nullopt;
}

std::wstring BuildShortcutLabel(const EncodableMap& map) {
  std::wstring label;
  const int modifiers =
      static_cast<int>(GetInt64(map, kShortcutModifiersKey).value_or(0));
  if (modifiers & kFlutterShortcutModifierControl) {
    label += L"Ctrl+";
  }
  if (modifiers & kFlutterShortcutModifierAlt) {
    label += L"Alt+";
  }
  if (modifiers & kFlutterShortcutModifierShift) {
    label += L"Shift+";
  }
  if (modifiers & kFlutterShortcutModifierMeta) {
    label += L"Win+";
  }

  if (const auto shortcut_character = GetString(map, kShortcutCharacterKey)) {
    const std::wstring wide = Utf8ToWide(*shortcut_character);
    if (!wide.empty()) {
      const auto mapped = MapCharacterShortcut(wide[0]);
      if (mapped.has_value()) {
        label += mapped->second;
        return label;
      }
    }
  }
  if (const auto trigger = GetInt64(map, kShortcutTriggerKey)) {
    const auto mapped = MapTriggerShortcut(*trigger);
    if (mapped.has_value()) {
      label += mapped->second;
      return label;
    }
  }
  return std::wstring();
}

std::optional<ACCEL> BuildAccelerator(const EncodableMap& map, WORD command_id) {
  const auto enabled = GetBool(map, kEnabledKey).value_or(false);
  if (!enabled) {
    return std::nullopt;
  }

  std::optional<std::pair<WORD, std::wstring>> mapped_key;
  if (const auto shortcut_character = GetString(map, kShortcutCharacterKey)) {
    const std::wstring wide = Utf8ToWide(*shortcut_character);
    if (!wide.empty()) {
      mapped_key = MapCharacterShortcut(wide[0]);
    }
  } else if (const auto trigger = GetInt64(map, kShortcutTriggerKey)) {
    mapped_key = MapTriggerShortcut(*trigger);
  }
  if (!mapped_key.has_value()) {
    return std::nullopt;
  }

  BYTE modifiers = FVIRTKEY;
  const int shortcut_modifiers =
      static_cast<int>(GetInt64(map, kShortcutModifiersKey).value_or(0));
  if (shortcut_modifiers & kFlutterShortcutModifierAlt) {
    modifiers |= FALT;
  }
  if (shortcut_modifiers & kFlutterShortcutModifierControl) {
    modifiers |= FCONTROL;
  }
  if (shortcut_modifiers & kFlutterShortcutModifierShift) {
    modifiers |= FSHIFT;
  }

  ACCEL accelerator{};
  accelerator.fVirt = modifiers;
  accelerator.key = mapped_key->first;
  accelerator.cmd = command_id;
  return accelerator;
}

std::wstring BuildMenuLabel(const EncodableMap& map) {
  const auto label = GetString(map, kLabelKey).value_or("");
  std::wstring wide_label = Utf8ToWide(label);
  const std::wstring shortcut = BuildShortcutLabel(map);
  if (!shortcut.empty()) {
    wide_label += L"\t";
    wide_label += shortcut;
  }
  return wide_label;
}

void AppendMenuItems(HMENU menu,
                     const EncodableList& items,
                     WORD* next_command_id,
                     std::map<WORD, int64_t>* command_id_to_flutter_id,
                     std::vector<ACCEL>* accelerators) {
  for (const auto& item_value : items) {
    const auto* item_map = std::get_if<EncodableMap>(&item_value);
    if (item_map == nullptr) {
      continue;
    }
    if (IsDivider(*item_map)) {
      AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
      continue;
    }

    const auto* children = GetList(*item_map, kChildrenKey);
    const auto enabled = GetBool(*item_map, kEnabledKey).value_or(true);
    const auto flutter_id = GetInt64(*item_map, kIdKey).value_or(0);
    const std::wstring label = BuildMenuLabel(*item_map);

    if (children != nullptr && !children->empty()) {
      HMENU submenu = CreatePopupMenu();
      AppendMenuItems(submenu, *children, next_command_id,
                      command_id_to_flutter_id, accelerators);
      UINT flags = MF_POPUP;
      if (!enabled) {
        flags |= MF_GRAYED;
      }
      AppendMenuW(menu, flags, reinterpret_cast<UINT_PTR>(submenu),
                  label.c_str());
      continue;
    }

    const WORD command_id = (*next_command_id)++;
    (*command_id_to_flutter_id)[command_id] = flutter_id;

    UINT flags = MF_STRING;
    if (!enabled) {
      flags |= MF_GRAYED;
    }
    AppendMenuW(menu, flags, command_id, label.c_str());

    if (const auto accelerator = BuildAccelerator(*item_map, command_id)) {
      accelerators->push_back(*accelerator);
    }
  }
}

}  // namespace

FlutterMenuPlugin::FlutterMenuPlugin(flutter::BinaryMessenger* messenger,
                                     HWND window_handle)
    : window_handle_(window_handle) {
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, kChannelName, &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        HandleMethodCall(call, std::move(result));
      });
}

FlutterMenuPlugin::~FlutterMenuPlugin() {
  ClearMenuState();
}

bool FlutterMenuPlugin::HandleMessage(UINT message,
                                      WPARAM wparam,
                                      LPARAM lparam) {
  if (message != WM_COMMAND || HIWORD(wparam) != 0) {
    return false;
  }
  const WORD command_id = LOWORD(wparam);
  const auto iterator = command_id_to_flutter_id_.find(command_id);
  if (iterator == command_id_to_flutter_id_.end()) {
    return false;
  }

  channel_->InvokeMethod(
      kSelectedCallbackMethod,
      std::make_unique<EncodableValue>(EncodableValue(iterator->second)));
  return true;
}

bool FlutterMenuPlugin::TranslateAcceleratorMessage(MSG* message) const {
  if (accelerator_table_ == nullptr) {
    return false;
  }
  return TranslateAccelerator(window_handle_, accelerator_table_, message) != 0;
}

void FlutterMenuPlugin::HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  if (call.method_name() == kIsPluginAvailableMethod) {
    result->Success(EncodableValue(true));
    return;
  }
  if (call.method_name() == kSetMenusMethod) {
    RebuildMenu(call.arguments());
    result->Success();
    return;
  }
  result->NotImplemented();
}

void FlutterMenuPlugin::ClearMenuState() {
  command_id_to_flutter_id_.clear();
  next_command_id_ = 1000;
  if (accelerator_table_ != nullptr) {
    DestroyAcceleratorTable(accelerator_table_);
    accelerator_table_ = nullptr;
  }
  if (menu_ != nullptr) {
    SetMenu(window_handle_, nullptr);
    DestroyMenu(menu_);
    menu_ = nullptr;
    DrawMenuBar(window_handle_);
  }
}

void FlutterMenuPlugin::RebuildMenu(const EncodableValue* arguments) {
  ClearMenuState();
  if (arguments == nullptr) {
    return;
  }

  const auto* window_map = std::get_if<EncodableMap>(arguments);
  if (window_map == nullptr) {
    return;
  }
  const EncodableValue* menu_list_value = FindValue(*window_map, kWindowKey);
  if (menu_list_value == nullptr) {
    return;
  }
  const auto* menu_list = std::get_if<EncodableList>(menu_list_value);
  if (menu_list == nullptr) {
    return;
  }

  std::vector<ACCEL> accelerators;
  menu_ = CreateMenu();
  AppendMenuItems(menu_, *menu_list, &next_command_id_, &command_id_to_flutter_id_,
                  &accelerators);
  SetMenu(window_handle_, menu_);
  DrawMenuBar(window_handle_);

  if (!accelerators.empty()) {
    accelerator_table_ =
        CreateAcceleratorTable(accelerators.data(), accelerators.size());
  }
}
