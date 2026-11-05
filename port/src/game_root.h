// The folder the game's disc files live in.
//
// The SD layout is self-contained:
//
//   SVR2011/
//     Game_files/     default.xex, pac/, sound/, movies/, native_shaders/, ...
//     svr2011.nro
//     svr2011.toml
//
// When Game_files/ exists beside the NRO it is the game root; otherwise the
// NRO's own folder is (the PC layout, and a staging folder without Game_files).
// User data (Saves/, UserData/, logs/, svr2011.toml) stays beside the NRO.
#pragma once

#include <filesystem>

namespace svr2011 {

inline std::filesystem::path g_game_root_path;

inline const std::filesystem::path& GameRoot() { return g_game_root_path; }

}  // namespace svr2011
