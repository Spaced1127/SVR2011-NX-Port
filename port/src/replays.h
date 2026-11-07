// The replay recorder's clip buffer (replays.cpp): with replays off the
// recorder's own first callback never runs, so the clips the boot attract demo
// left behind are still there when a scene change destroys the recorder. One
// of them is half-made and its destructor read guest 0xDC in the RTWM ring
// entrance (the same crash the match start had with replays on). Clearing the
// 140 pointers first leaks the old clips (small, one match's worth) and leaves
// the free loop nothing to crash on.
#pragma once

#include <cstdint>

namespace svr2011 {

// Zero the recorder's 140 clip pointers at part + [part+1496]*748. False when
// the recorder (or its part) is not made yet, or the buffer is not a guest
// heap pointer: nothing is written then.
bool ReplayClipsClearNow(uint8_t* base, const char* why);

// Once at boot, and again when the match clock restarts, with replays off.
void ReplayClipsClearIfNeeded(uint8_t* base);

}  // namespace svr2011
