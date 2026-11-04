// WWE SmackDown vs. Raw 2011 - the native renderer's graphics API (gpu.h):
// the backend matching the emulator's.

#include "native/gpu.h"

#include <rex/cvar.h>
#include <rex/external_frame.h>
#include <rex/logging.h>

#if defined(__SWITCH__)
// The deko3d branch draws on the console's own API by default; "auto" keeps
// the emulator's Vulkan backend for comparing.
REXCVAR_DEFINE_STRING(native_backend, "deko3d", "GPU",
                      "Native renderer backend: deko3d (the Switch's own API) or auto (the emulator's Vulkan)");
#else
REXCVAR_DEFINE_STRING(native_backend, "auto", "GPU",
                      "Native renderer backend: auto (the emulator's Vulkan/D3D12)");
#endif

namespace svr2011::native::backend {

#if !defined(_WIN32)
std::unique_ptr<Backend> CreateD3D12Backend() { return nullptr; }  // (Windows only)
#endif
#if !defined(_WIN32)
std::unique_ptr<Backend> CreateD3D11Backend() { return nullptr; }  // (Windows only)
#endif
#if !defined(__SWITCH__)
std::unique_ptr<Backend> CreateDeko3DBackend() { return nullptr; }  // (Switch only)
#endif

namespace {
std::unique_ptr<Backend> g_backend;
}  // namespace

std::unique_ptr<plume::RenderInterface> CreateInterface(std::string* device_name) {
  if (REXCVAR_GET(native_backend) == "deko3d") {
    g_backend = CreateDeko3DBackend();
  } else {
    g_backend = rex::external_frame::GetVulkanDevice()   ? CreateVulkanBackend()
                : rex::external_frame::GetD3D11Device() ? CreateD3D11Backend()
                                                        : CreateD3D12Backend();
  }
  if (!g_backend) {
    REXLOG_ERROR("native renderer: no backend for {}",
                 REXCVAR_GET(native_backend) == "deko3d" ? "deko3d" : "the emulator's graphics API");
    return nullptr;
  }
  REXLOG_INFO("native renderer: {} backend", g_backend->api() == Api::kVulkan  ? "Vulkan"
                                              : g_backend->api() == Api::kD3D11 ? "D3D11"
                                              : g_backend->api() == Api::kDeko3D ? "deko3d"
                                                                                : "D3D12");
  return g_backend->CreateInterface(device_name);
}

void SetDevice(plume::RenderDevice* device) {
  if (g_backend) g_backend->SetDevice(device);
}

Api ActiveApi() { return g_backend ? g_backend->api() : Api::kNone; }

namespace {
std::string g_fail_reason;
}  // namespace
std::string FailReason() { return g_fail_reason; }
void SetFailReason(std::string reason) { g_fail_reason = std::move(reason); }

plume::RenderShaderFormat ShaderFormat() { return g_backend->ShaderFormat(); }
const char* ShaderExtension() { return g_backend ? g_backend->ShaderExtension() : ".dxil"; }
bool CompactTables() { return g_backend && g_backend->CompactTables(); }

plume::RenderFormat DepthFormat() {
  return g_backend ? g_backend->DepthFormat() : plume::RenderFormat::D24_UNORM_S8_UINT;
}

void PublishFrame(const std::shared_ptr<plume::RenderTexture>& image, uint32_t width,
                  uint32_t height, plume::RenderCommandFence* fence) {
  g_backend->PublishFrame(image, width, height, fence);
}
bool GetFrame(rex::external_frame::Frame& frame) { return g_backend && g_backend->GetFrame(frame); }
void ClearFrame() {
  if (g_backend) g_backend->ClearFrame();
}
bool DeviceLost(plume::RenderDevice* device) { return g_backend && g_backend->DeviceLost(device); }
void ReportDeviceLost(plume::RenderDevice* device) {
  if (g_backend) g_backend->ReportDeviceLost(device);
}
void ReleaseFence(plume::RenderCommandFence* fence) {
  if (g_backend) g_backend->ReleaseFence(fence);
}
void DrainDebugMessages(plume::RenderDevice* device) {
  if (g_backend) g_backend->DrainDebugMessages(device);
}
void LogBuffer(plume::RenderBuffer* buffer, uint64_t size) {
  if (g_backend) g_backend->LogBuffer(buffer, size);
}
bool PipelineCreated(plume::RenderPipeline* pipeline) {
  return g_backend && g_backend->PipelineCreated(pipeline);
}
void LoadPipelineCache(plume::RenderDevice* device, const std::filesystem::path& file) {
  if (g_backend) g_backend->LoadPipelineCache(device, file);
}
void SavePipelineCache(plume::RenderDevice* device, const std::filesystem::path& file) {
  if (g_backend) g_backend->SavePipelineCache(device, file);
}
void StallQueue(plume::RenderCommandQueue* queue) {
  if (g_backend) g_backend->StallQueue(queue);
}

#if !defined(_WIN32)
bool DxgiVideoMemory(uint64_t*, uint64_t*) { return false; }
#endif
bool VideoMemory(uint64_t* used, uint64_t* budget) {
  switch (ActiveApi()) {
    case Api::kVulkan: return VulkanVideoMemory(used, budget);
    case Api::kD3D12:
    case Api::kD3D11: return DxgiVideoMemory(used, budget);
    case Api::kDeko3D: return false;  // (the deko3d device reports its own memory figures)
    default: return false;
  }
}

}  // namespace svr2011::native::backend
