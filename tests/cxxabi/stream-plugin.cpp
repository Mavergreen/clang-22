#include <fstream>
#include <iterator>
#include <stdexcept>
#include <string>

extern "C" int read_with_stream(const char* path) {
  std::ifstream input(path);
  std::string contents{std::istreambuf_iterator<char>(input),
                       std::istreambuf_iterator<char>()};
  return contents.empty() ? 1 : 0;
}

extern "C" void throw_from_plugin() {
  throw std::runtime_error("plugin exception");
}
