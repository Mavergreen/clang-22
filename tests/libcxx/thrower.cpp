// A second image that throws, so the test can prove an exception crosses an image boundary.
#include <stdexcept>
#include <string>

extern "C" void mg_throw(int n) {
  throw std::runtime_error("from thrower " + std::to_string(n));
}
