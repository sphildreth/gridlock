#ifndef RUNNER_FLUTTER_MENU_PLUGIN_H_
#define RUNNER_FLUTTER_MENU_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <map>
#include <memory>

class FlutterMenuPlugin {
 public:
  FlutterMenuPlugin(flutter::BinaryMessenger* messenger, HWND window_handle);
  ~FlutterMenuPlugin();

  bool HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);
  bool TranslateAcceleratorMessage(MSG* message) const;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void ClearMenuState();
  void RebuildMenu(const flutter::EncodableValue* arguments);

  HWND window_handle_;
  HMENU menu_ = nullptr;
  HACCEL accelerator_table_ = nullptr;
  WORD next_command_id_ = 1000;
  std::map<WORD, int64_t> command_id_to_flutter_id_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_FLUTTER_MENU_PLUGIN_H_
