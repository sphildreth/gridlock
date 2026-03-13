#include <cstring>
#include <iostream>

#include "my_application.h"

namespace {

constexpr const char* kHelpText =
    "Decent Bench 0.1.0\n"
    "\n"
    "Usage:\n"
    "  dbench [options]\n"
    "\n"
    "Options:\n"
    "  -h, --help\n"
    "      Show this help text and exit.\n"
    "  -v, --version\n"
    "      Show the application version and exit.\n"
    "  --import <path>\n"
    "      Open the import flow for <path> at startup.\n"
    "  --import=<path>\n"
    "      Same as above, using the inline form.\n"
    "\n"
    "Examples:\n"
    "  dbench\n"
    "  dbench /path/to/workspace.ddb\n"
    "  dbench --import /path/to/source.sqlite\n"
    "  dbench --import=/path/to/report.xlsx\n"
    "\n"
    "Notes:\n"
    "  Passing a .ddb path opens that database in the desktop UI.\n"
    "  If <path> is a .ddb database, Decent Bench opens it directly.\n"
    "  Otherwise Decent Bench starts the import workflow for the detected "
    "source format.\n";

bool HasArg(int argc, char** argv, const char* short_name,
            const char* long_name) {
  for (int i = 1; i < argc; ++i) {
    if (std::strcmp(argv[i], short_name) == 0 ||
        std::strcmp(argv[i], long_name) == 0) {
      return true;
    }
  }
  return false;
}

}  // namespace

int main(int argc, char** argv) {
  if (HasArg(argc, argv, "-h", "--help")) {
    std::cout << kHelpText;
    return 0;
  }
  if (HasArg(argc, argv, "-v", "--version")) {
    std::cout << "Decent Bench 0.1.0" << std::endl;
    return 0;
  }

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
