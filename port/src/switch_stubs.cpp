// Nintendo Switch: platform pieces the port's PC/Android crash reporter
// provides. The SDK's Horizon layer owns the real exception handler and
// crash log (sdk/src/core/exception_handler_switch.cpp and
// sdk/src/ui/switch_crash_hooks.c); these are the game-side hooks it can call
// later. Keeping them as no-ops makes the first Switch build link and boot
// without pretending to install POSIX signal handlers that Horizon lacks.

#include "crash_report.h"
#include "guest_faults.h"

#if defined(__SWITCH__)

namespace svr2011 {

void InstallCrashReporter(const std::filesystem::path&) {}

void SetCrashHook(void (*)()) {}

void SetCrashTextHook(void (*)(FILE*)) {}

void ReclaimCrashSignals() {}

void InstallGuestFaultLog() {}

}  // namespace svr2011

#endif  // __SWITCH__
