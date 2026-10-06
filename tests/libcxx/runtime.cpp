// A real C++ program for libcxx22: exceptions across images, iostreams, threads, futures, a clock,
// and coexistence with the system /usr/lib/libc++.1.dylib in the same process.
#include <chrono>
#include <dlfcn.h>
#include <exception>
#include <future>
#include <iomanip>
#include <iostream>
#include <mutex>
#include <sstream>
#include <stdexcept>
#include <thread>
#include <vector>

extern "C" void mg_throw(int n);

int main() {
  try {
    mg_throw(7);
  } catch (const std::exception& e) {
    std::cout << "caught across images: " << e.what() << "\n";
  }

  {
    std::ostringstream os;
    os << std::fixed << std::setprecision(2) << 3.14159;
    std::string pi = os.str();
    os.str("");
    os << std::hex << std::showbase << 42;
    std::cout << "iostream: " << pi << " " << os.str() << "\n";
  }

  {
    std::mutex m;
    long counter = 0;
    std::vector<std::thread> ts;
    for (int i = 0; i < 4; i++)
      ts.emplace_back([&] {
        for (int j = 0; j < 100000; j++) {
          std::lock_guard<std::mutex> g(m);
          counter += 1;
        }
      });
    for (auto& t : ts) t.join();
    std::cout << "threads: " << counter << "\n";
  }

  try {
    auto f = std::async(std::launch::async,
                        []() -> int { throw std::runtime_error("from worker"); });
    (void)f.get();
  } catch (const std::exception& e) {
    std::cout << "future exception: " << e.what() << "\n";
  }

  {
    auto a = std::chrono::steady_clock::now();
    auto b = std::chrono::steady_clock::now();
    std::cout << "steady_clock: " << (b >= a ? "monotonic" : "went backwards") << "\n";
  }

  void* sys = dlopen("/usr/lib/libc++.1.dylib", RTLD_NOW);
  if (!sys) {
    std::cout << "after system libc++: dlopen failed\n";
    return 1;
  }
  try {
    mg_throw(9);
  } catch (const std::exception& e) {
    std::cout << "after system libc++: caught " << e.what() << "\n";
  }
  return 0;
}
