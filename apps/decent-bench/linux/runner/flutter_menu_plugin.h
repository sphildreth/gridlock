#ifndef RUNNER_FLUTTER_MENU_PLUGIN_H_
#define RUNNER_FLUTTER_MENU_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

class FlutterMenuPlugin {
 public:
  FlutterMenuPlugin(FlBinaryMessenger* messenger,
                    GtkWindow* window,
                    GtkBox* container);
  ~FlutterMenuPlugin();

 private:
  static void MethodCallHandler(FlMethodChannel* channel,
                                FlMethodCall* method_call,
                                gpointer user_data);
  static void MenuItemActivated(GtkWidget* widget, gpointer user_data);

  FlMethodResponse* HandleMethodCall(FlMethodCall* method_call);
  void RebuildMenu(FlValue* arguments);
  GtkWidget* BuildMenuBar(FlValue* menu_items);
  GtkWidget* BuildMenuItem(FlValue* item);
  void SendSelection(gint64 flutter_id);
  void ClearMenu();

  FlMethodChannel* channel_;
  GtkWindow* window_;
  GtkBox* container_;
  GtkAccelGroup* accel_group_;
  GtkWidget* menu_bar_ = nullptr;
};

#endif  // RUNNER_FLUTTER_MENU_PLUGIN_H_
