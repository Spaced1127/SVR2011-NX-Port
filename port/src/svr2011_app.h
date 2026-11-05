// WWE SmackDown vs. Raw 2011 - ReXGlue recompiled PC port
//
// The SD layout is self-contained:
//   SVR2011/Game_files/   default.xex, pac\, sound\, movies\, native_shaders\ ...
//   SVR2011/svr2011.nro
//   SVR2011/svr2011.toml
// GameRoot() (game_root.h) is Game_files when that folder exists, else the
// NRO's own folder (the PC layout). Saves, UserData and logs go beside the
// NRO. Settings come from svr2011.toml, written by the launcher.

#pragma once

#include <rex/rex_app.h>

class Svr2011App : public rex::ReXApp {
 public:
  using rex::ReXApp::ReXApp;

  static std::unique_ptr<rex::ui::WindowedApp> Create(
      rex::ui::WindowedAppContext& ctx) {
    return std::unique_ptr<Svr2011App>(new Svr2011App(ctx, "svr2011",
        PPCImageConfig));
  }

  void OnConfigurePaths(rex::PathConfig& paths) override;
  void OnPreSetup(rex::RuntimeConfig& config) override;
  void OnCreateDialogs(rex::ui::ImGuiDrawer* drawer) override;
  void OnConfigureFonts(ImFontAtlas* atlas) override;
  void OnPostLoadXexImage() override;
  bool OnWindowCloseRequested() override;  // (the router's port mapping removed: port_map.h)
};
