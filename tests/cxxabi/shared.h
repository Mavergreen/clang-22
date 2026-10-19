// What the two sides of tests/cxxabi-interop-test.sh share. Adapted from swift-gg's two-libc++abi
// spike (2026-10-19). Custom's type_info is emitted, weak, in each image.
#pragma once
struct Custom { int v; };
extern int g_dtors;                         // destructor counter, lives in libsys
struct Guard { const char *who; ~Guard(); };
extern "C" {
void sys_throw_runtime(void);               // throws std::runtime_error("sys") through the system's libc++
void sys_throw_custom(void);                // throws Custom{7}
int  sys_call_and_catch(void (*f)(void));   // calls f inside sys's own try; returns which handler caught
void sys_pass_through(void (*f)(void));     // calls f with a Guard on sys's frame, catching nothing
int  sys_uncaught_in_dtor(void (*f)(void)); // std::uncaught_exception() as sys sees it during f's unwind
}
