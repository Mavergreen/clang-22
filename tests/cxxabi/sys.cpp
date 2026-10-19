// The "system" side: built against macOS's own libc++ (the 11.3 SDK's headers, 10.9 deployment) and
// linked to /usr/lib/libc++.1.dylib, so it throws and catches through /usr/lib/libc++abi.dylib.
#include <stdexcept>
#include <exception>
#include "shared.h"
int g_dtors = 0;
Guard::~Guard() { g_dtors++; }
extern "C" void sys_throw_runtime(void) { Guard g{"sys"}; throw std::runtime_error("sys"); }
extern "C" void sys_throw_custom(void) { Guard g{"sys"}; throw Custom{7}; }
extern "C" int sys_call_and_catch(void (*f)(void)) {
  try { f(); return 0; }
  catch (const std::runtime_error &) { return 1; }
  catch (const std::exception &) { return 2; }
  catch (const Custom &c) { return c.v == 9 ? 3 : 30; }
  catch (...) { return 4; }
}
extern "C" void sys_pass_through(void (*f)(void)) { Guard g{"sys"}; f(); }
static int seen = -1;
// 10.9's libc++ predates std::uncaught_exceptions(); the bool form reads the same per-thread count
struct Peek { ~Peek() { seen = std::uncaught_exception() ? 1 : 0; } };
extern "C" int sys_uncaught_in_dtor(void (*f)(void)) {
  seen = -1;
  try { Peek p; f(); } catch (...) {}
  return seen;
}
