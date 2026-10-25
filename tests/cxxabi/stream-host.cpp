#include <dlfcn.h>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <stdexcept>

int main(int argc, char** argv) {
  if (argc != 3) return 2;
  // Both images instantiate streams; the plugin's locale must be destroyed by
  // its own runtime even when dyld coalesces weak C++ symbols across images.
  { std::ifstream input(argv[2]); if (!input) return 3; }
  for (int visibility : {RTLD_LOCAL, RTLD_GLOBAL}) {
    void* image = dlopen(argv[1], RTLD_NOW | visibility);
    if (!image) { std::puts(dlerror()); return 4; }
    auto read = reinterpret_cast<int (*)(const char*)>(dlsym(image, "read_with_stream"));
    auto raise = reinterpret_cast<void (*)()>(dlsym(image, "throw_from_plugin"));
    if (!read || !raise || read(argv[2]) != 0) return 5;
    bool caught = false;
    try { raise(); }
    catch (const std::runtime_error& error) {
      caught = std::strcmp(error.what(), "plugin exception") == 0;
    }
    catch (...) { return 6; }
    if (!caught || dlclose(image) != 0) return 7;
  }
  std::puts("PASS static plugin streams and exceptions");
}
