/*
 * <pthread/qos.h> back-fill for the 10.9 target: the qos_class_* half Recaulk does not declare.
 *
 * WHY THIS EXISTS: Darwin's QoS API (qos_class_t, pthread_set_qos_class_self_np, qos_class_self)
 * arrived in macOS 10.10. The pinned 10.9 SDK has no pthread/ directory at all. LLVM's
 * llvm/lib/Support/Unix/Threading.inc includes <pthread/qos.h> under a bare `#if defined(__APPLE__)`
 * and uses the API under a bare `#elif defined(__APPLE__)` -- no availability check anywhere -- so
 * building LLVM's own host tools for 10.9 fails outright:
 *
 *   Threading.inc:25:10: fatal error: 'pthread/qos.h' file not found
 *
 * WHO OWNS WHAT. Recaulk ships include/recaulk/pthread/qos.h, which declares qos_class_t and the
 * pthread_*_qos_* functions (defined in librecaulk.a), but neither qos_class_self nor qos_class_main.
 * Both cfgs and the runtimes build search this overlay (include/mavericks-compat) BEFORE
 * include/recaulk, so the #include_next below hands off to Recaulk's header for the pthread half, and
 * this header then supplies only qos_class_self and qos_class_main. Without that tail, user code
 * calling them fails with "call to undeclared function 'qos_class_self'". Only when nothing further
 * down the path provides <pthread/qos.h> (this overlay used without Recaulk's include dir) does the
 * fallback branch declare the type and the setter itself.
 *
 * DECISION, not a mechanical fix. Unlike the aligned_alloc back-fill, which papers over a function
 * libc++ hard-requires, QoS is a real 10.10 FEATURE that 10.9 genuinely lacks. There is nothing to
 * polyfill: a 10.9 kernel has no quality-of-service classes. So qos_class_self/qos_class_main report
 * QOS_CLASS_DEFAULT. The setter is Recaulk's whenever its header is on the path (a no-op in
 * librecaulk.a that returns 0 on 10.9); the fallback setter below REPORTS FAILURE instead, which LLVM
 * maps to SetThreadPriorityResult::FAILURE, what it yields on every platform without QoS.
 * Thread-priority hints are advisory; losing them costs scheduling niceness, nothing more.
 *
 * WHY static inline for qos_class_*: it has internal linkage, so it links with or without
 * librecaulk.a on the line and cannot collide with the external _qos_class_self librecaulk.a defines.
 * A plain declaration would link only against librecaulk.a, and qos_class_main would not link at all
 * (neither librecaulk.a nor 10.9's libSystem defines it). The cost: a call never reaches Recaulk's
 * forwarding _qos_class_self, so a 10.9-built binary running on 10.10+ reads QOS_CLASS_DEFAULT rather
 * than its real class. If Recaulk ever declares these, the static inline becomes a loud
 * "static declaration follows non-static declaration" error: the signal to retire this tail.
 *
 * The consequence worth stating plainly: this header SHIPS (it lives in the overlay the toolchain
 * installs as include/mavericks-compat and references from clang.cfg), so user code targeting 10.9
 * that calls these APIs will compile and silently get a no-op setter and QOS_CLASS_DEFAULT at runtime
 * instead of a build error. That is the same bargain the rest of the polyfill makes.
 */
#ifndef MAVERICKS_COMPAT_PTHREAD_QOS_H
#define MAVERICKS_COMPAT_PTHREAD_QOS_H

#ifndef __ASSEMBLER__

#include <sys/cdefs.h>

#if defined(__has_include_next) && __has_include_next(<pthread/qos.h>)
#  include_next <pthread/qos.h>
#else

__BEGIN_DECLS

/* Values are Apple's own, so a binary built here agrees with one built against a real SDK. */
typedef enum {
  QOS_CLASS_USER_INTERACTIVE = 0x21,
  QOS_CLASS_USER_INITIATED   = 0x19,
  QOS_CLASS_DEFAULT          = 0x15,
  QOS_CLASS_UTILITY          = 0x11,
  QOS_CLASS_BACKGROUND       = 0x09,
  QOS_CLASS_UNSPECIFIED      = 0x00
} qos_class_t;

/* static inline, not an extern: 10.9's libSystem exports no such symbol, so a declaration alone
   would only move the failure from compile time to link time. */
__attribute__((unused)) static inline int
pthread_set_qos_class_self_np(qos_class_t __qos_class, int __relative_priority) {
  (void)__qos_class;
  (void)__relative_priority;
  return -1;            /* "could not set" -- see the header comment */
}

__END_DECLS

#endif /* no further <pthread/qos.h> */

/* Always: Recaulk's header declares neither (see the header comment). */
__BEGIN_DECLS

__attribute__((unused)) static inline qos_class_t qos_class_self(void) {
  return QOS_CLASS_DEFAULT;
}

__attribute__((unused)) static inline qos_class_t qos_class_main(void) {
  return QOS_CLASS_DEFAULT;
}

__END_DECLS

#endif /* __ASSEMBLER__ */

#endif /* MAVERICKS_COMPAT_PTHREAD_QOS_H */
