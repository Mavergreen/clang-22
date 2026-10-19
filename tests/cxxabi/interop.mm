// Our side: built by the toolchain under test, with Foundation, whose libobjc throws and catches through
// /usr/lib/libc++abi.dylib. One case per run, named on the command line; prints "PASS case: ..." or
// "FAIL case: ..." and exits 0 or 1. The terminate-* cases are meant to abort. Adapted from swift-gg's
// two-libc++abi spike (2026-10-19), plus a case for each entry point Recaulk back-fills.
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <cstdio>
#include <cstring>
#include <exception>
#include <future>
#include <new>
#include <stdexcept>
#include "shared.h"

extern "C" void *__cxa_begin_catch(void *) noexcept;
extern "C" void __cxa_end_catch();
extern "C" void *__cxa_allocate_exception(size_t) noexcept;
extern "C" [[noreturn]] void __cxa_throw(void *, std::type_info *, void (*)(void *));
extern "C" [[noreturn]] void __cxa_throw_bad_array_new_length();

static void new_throw_runtime(void) { Guard g{"new"}; throw std::runtime_error("new"); }
static void new_throw_custom(void) { Guard g{"new"}; throw Custom{9}; }
static void objc_raise(void) { Guard g{"new"}; [NSException raise:@"Interop" format:@"objc"]; }
struct Counted : std::runtime_error { Counted() : std::runtime_error("counted") {} ~Counted() override { g_dtors++; } };
struct Peek { int *out; ~Peek() { *out = std::uncaught_exceptions(); } };
[[gnu::noinline]] static void thrower() noexcept(false) { throw 1; }
[[gnu::noinline]] static void nothrow_wrapper() noexcept { thrower(); }

static int ok(const char *c, bool pass, const char *detail) {
  std::printf("%s %s: %s (dtors=%d)\n", pass ? "PASS" : "FAIL", c, detail, g_dtors);
  return pass ? 0 : 1;
}
static const char *handler[] = {"nothing", "runtime_error&", "exception&", "Custom&", "catch(...)"};

int main(int argc, char **argv) {
  const char *c = argc > 1 ? argv[1] : "";
  @autoreleasepool {
  if (!std::strcmp(c, "one-abi")) {  // the C++ ABI this program uses is the system's
    struct { const char *name; void *p; } fns[] = {
      {"__cxa_begin_catch", reinterpret_cast<void *>(&__cxa_begin_catch)},
      {"__cxa_end_catch", reinterpret_cast<void *>(&__cxa_end_catch)},
      {"__cxa_allocate_exception", reinterpret_cast<void *>(&__cxa_allocate_exception)},
      {"__cxa_throw", reinterpret_cast<void *>(&__cxa_throw)},
    };
    for (auto &f : fns) {
      Dl_info i;
      if (!dladdr(f.p, &i) || !i.dli_fname) return ok(c, false, "dladdr failed");
      if (std::strcmp(i.dli_fname, "/usr/lib/libc++abi.dylib")) {
        char d[300]; std::snprintf(d, sizeof d, "%s is in %s", f.name, i.dli_fname); return ok(c, false, d);
      }
    }
    return ok(c, true, "__cxa_begin_catch, __cxa_end_catch, __cxa_allocate_exception and __cxa_throw are /usr/lib/libc++abi.dylib's");
  }
  if (!std::strcmp(c, "control-new-new")) {
    try { new_throw_runtime(); } catch (const std::runtime_error &e) { return ok(c, g_dtors == 1, e.what()); }
    return ok(c, false, "nothing thrown");
  }
  if (!std::strcmp(c, "control-sys-sys")) {
    int r = sys_call_and_catch(sys_throw_runtime);
    return ok(c, r == 1, handler[r >= 0 && r <= 4 ? r : 0]);
  }
  if (!std::strcmp(c, "sys-runtime-as-runtime_error")) {
    try { sys_throw_runtime(); } catch (const std::runtime_error &e) { return ok(c, !std::strcmp(e.what(), "sys"), e.what()); }
    catch (...) { return ok(c, false, "fell to catch(...)"); }
    return ok(c, false, "nothing thrown");
  }
  if (!std::strcmp(c, "sys-runtime-as-exception")) {
    try { sys_throw_runtime(); } catch (const std::exception &e) { return ok(c, true, e.what()); }
    catch (...) { return ok(c, false, "fell to catch(...)"); }
    return ok(c, false, "nothing thrown");
  }
  if (!std::strcmp(c, "sys-custom")) {
    try { sys_throw_custom(); } catch (const Custom &e) { return ok(c, e.v == 7, "caught Custom"); }
    catch (...) { return ok(c, false, "fell to catch(...)"); }
    return ok(c, false, "nothing thrown");
  }
  if (!std::strcmp(c, "sys-any")) {
    try { sys_throw_runtime(); } catch (...) { return ok(c, g_dtors == 1, "caught by catch(...)"); }
    return ok(c, false, "nothing thrown");
  }
  if (!std::strcmp(c, "new-runtime-caught-by-sys")) {
    int r = sys_call_and_catch(new_throw_runtime);
    return ok(c, r == 1, handler[r >= 0 && r <= 4 ? r : 0]);
  }
  if (!std::strcmp(c, "new-custom-caught-by-sys")) {
    int r = sys_call_and_catch(new_throw_custom);
    return ok(c, r == 3, r == 30 ? "Custom with the wrong value" : handler[r >= 0 && r <= 4 ? r : 0]);
  }
  if (!std::strcmp(c, "new-through-sys-frame")) {
    try { sys_pass_through(new_throw_runtime); } catch (const std::runtime_error &) { return ok(c, g_dtors == 2, "both Guards ran"); }
    catch (...) { return ok(c, false, "fell to catch(...)"); }
    return ok(c, false, "nothing thrown");
  }
  if (!std::strcmp(c, "uncaught-count-across")) {
    int n = sys_uncaught_in_dtor(new_throw_runtime);
    char d[80]; std::snprintf(d, sizeof d, "sys saw std::uncaught_exception() == %d during our unwind", n);
    return ok(c, n == 1, d);
  }
  if (!std::strcmp(c, "objc-catch-cxx")) {
    @try { new_throw_runtime(); } @catch (NSException *e) { return ok(c, false, "caught as NSException"); }
    @catch (...) { return ok(c, g_dtors == 1, "@catch(...) caught our C++ exception"); }
    return ok(c, false, "nothing thrown");
  }
  if (!std::strcmp(c, "objc-raise-through-cxx")) {
    @try { objc_raise(); } @catch (NSException *e) { return ok(c, g_dtors == 1 && [[e name] isEqual:@"Interop"], "@catch(NSException*) after our Guard ran"); }
    return ok(c, false, "nothing thrown");
  }
  if (!std::strcmp(c, "cxx-catch-objc-any")) {
    try { objc_raise(); } catch (...) { return ok(c, g_dtors == 1, "C++ catch(...) caught the NSException"); }
    return ok(c, false, "nothing thrown");
  }
  if (!std::strcmp(c, "cxx-catch-objc-typed")) {
    try { objc_raise(); } catch (NSException *e) { return ok(c, [[e name] isEqual:@"Interop"], "C++ catch(NSException*)"); }
    catch (...) { return ok(c, false, "fell to catch(...)"); }
    return ok(c, false, "nothing thrown");
  }
  if (!std::strcmp(c, "objc-raise-through-sys")) {
    @try { sys_pass_through(objc_raise); } @catch (NSException *e) { return ok(c, g_dtors == 2, "both Guards ran"); }
    return ok(c, false, "nothing thrown");
  }
  if (!std::strcmp(c, "exception_ptr-across")) {
    std::exception_ptr p;
    try { sys_throw_runtime(); } catch (...) { p = std::current_exception(); }
    if (!p) return ok(c, false, "current_exception() empty for a sys exception");
    try { std::rethrow_exception(p); } catch (const std::runtime_error &e) { return ok(c, !std::strcmp(e.what(), "sys"), "rethrown and caught"); }
    catch (...) { return ok(c, false, "rethrown, fell to catch(...)"); }
    return ok(c, false, "rethrow did not throw");
  }
  // Each entry point Recaulk back-fills, through the language feature that reaches it.
  if (!std::strcmp(c, "make_exception_ptr")) {
    { std::exception_ptr p = std::make_exception_ptr(Counted());
      try { std::rethrow_exception(p); } catch (const std::runtime_error &e) {
        if (std::strcmp(e.what(), "counted")) return ok(c, false, "wrong what()"); }
      catch (...) { return ok(c, false, "fell to catch(...)"); } }
    return ok(c, g_dtors == 2, "the temporary and the exception, each destroyed once");
  }
  if (!std::strcmp(c, "promise-set-exception")) {
    std::promise<int> pr; pr.set_exception(std::make_exception_ptr(std::logic_error("p")));
    try { (void)pr.get_future().get(); } catch (const std::logic_error &e) { return ok(c, !std::strcmp(e.what(), "p"), "the future rethrew it"); }
    return ok(c, false, "not rethrown");
  }
  if (!std::strcmp(c, "uncaught_exceptions")) {
    int n = -1, before = std::uncaught_exceptions();
    try { Peek p{&n}; throw 2; } catch (int) {}
    char d[80]; std::snprintf(d, sizeof d, "%d before, %d during unwind, %d after", before, n, std::uncaught_exceptions());
    return ok(c, before == 0 && n == 1 && std::uncaught_exceptions() == 0, d);
  }
  if (!std::strcmp(c, "bad_array_new_length")) {
    // Called directly: clang 22 lowers the array-new cases it covers to operator new[](SIZE_MAX).
    try { __cxa_throw_bad_array_new_length(); } catch (const std::bad_array_new_length &) { return ok(c, true, "caught std::bad_array_new_length"); }
    catch (...) { return ok(c, false, "fell to catch(...)"); }
  }
  if (!std::strcmp(c, "char8_t")) {
    try { throw static_cast<char8_t>('x'); } catch (char8_t ch) { return ok(c, ch == 'x', "caught as char8_t"); } catch (...) {}
    return ok(c, false, "not caught as char8_t");
  }
  if (!std::strcmp(c, "const-char8_t-pointer")) {
    static const char8_t s[] = u8"y";
    try { throw s; } catch (const char8_t *p) { return ok(c, p == s, "caught as const char8_t*"); } catch (...) {}
    return ok(c, false, "not caught as const char8_t*");
  }
  if (!std::strcmp(c, "terminate-ours-through-sys")) { sys_pass_through(new_throw_runtime); return 0; }
  if (!std::strcmp(c, "terminate-sys")) { sys_throw_runtime(); return 0; }
  if (!std::strcmp(c, "terminate-noexcept")) { nothrow_wrapper(); return 0; }
  }
  std::fprintf(stderr, "unknown case '%s'\n", c);
  return 2;
}
