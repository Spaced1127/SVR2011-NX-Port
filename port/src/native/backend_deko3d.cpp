// WWE SmackDown vs. Raw 2011 - the native renderer's deko3d backend (gpu.h).
//
// deko3d is the Switch's own GPU API. The renderer still draws through plume;
// this file creates the deko3d device through plume's deko3d back end
// (plume_deko3d.h, MIT, from banjo-nx/sa2-nx) and presents the finished frame
// on the default libnx NWindow. There is no Vulkan/NVK driver in this path.

#include "native/gpu.h"

#include <filesystem>
#include <memory>
#include <string>

#include <switch.h>

#include <plume_deko3d.h>

#include <rex/logging.h>

namespace svr2011::native::backend {

namespace {

// The frame the renderer hands over is RGBA8; the Switch NWindow takes RGBA8
// as deko3d's own examples present it, so the copy is a straight one.
constexpr plume::RenderFormat kSwapChainFormat = plume::RenderFormat::R8G8B8A8_UNORM;

class Deko3DBackend final : public Backend {
 public:
  Api api() const override { return Api::kDeko3D; }

  std::unique_ptr<plume::RenderInterface> CreateInterface(std::string* device_name) override {
    *device_name = "deko3d";
    // The renderer's shaders were built for Vulkan (-fvk-invert-y): deko3d's
    // viewport transform must flip Y to match.
    plume::Deko3DOptions options = plume::Deko3DGetOptions();
    options.vulkanY = true;
    plume::Deko3DSetOptions(options);
    // uam's compile errors and the back end's messages go to the app's log
    // (stderr on the console would be lost).
    plume::SetDeko3DLogCallback([](const char* message) { REXLOG_ERROR("deko3d: {}", message); });
    return plume::CreateDeko3DInterface();
  }

  plume::RenderShaderFormat ShaderFormat() const override {
    return plume::RenderShaderFormat::DEKO3D;
  }

  const char* ShaderExtension() const override { return ".dk"; }

  // The renderer's big descriptor tables (set 0: 2D / 3D / cube textures, set
  // 1: samplers) map directly to deko3d's image and sampler descriptor sets;
  // the shaders address them with bindless handles (dkh). The compact tables
  // are for GPUs without descriptor indexing.
  bool CompactTables() const override { return false; }

  plume::RenderFormat DepthFormat() const override {
    return plume::RenderFormat::D24_UNORM_S8_UINT;
  }

  void SetDevice(plume::RenderDevice* device) override {
    device_ = device;
    copy_pending_ = false;
    focused_ = true;
    queue_ = device_->createCommandQueue(plume::RenderCommandListType::DIRECT);
    if (!queue_) {
      REXLOG_ERROR("deko3d: could not create the presentation queue");
      return;
    }
    // One command list and fence for the per-frame copy, reused. A list per
    // frame allocates a 1 MB command block each time and its destructor calls
    // dkQueueWaitIdle: that waits for the present too, so a screenshot or a
    // paused display (which holds the window's buffers) froze the render thread
    // silently. The copy fence signs before the present; waiting for it before
    // the next frame's copy reuses the list safely even if the display is
    // paused.
    copy_list_ = queue_->createCommandList();
    copy_fence_ = device_->createCommandFence();
    if (!copy_list_ || !copy_fence_) {
      REXLOG_ERROR("deko3d: could not create the present copy list");
      copy_list_.reset();
      copy_fence_.reset();
    }
  }

  void PublishFrame(const std::shared_ptr<plume::RenderTexture>& image, uint32_t width,
                    uint32_t height, plume::RenderCommandFence* fence) override {
    if (!queue_ || !image || !width || !height) return;
    if (!swapchain_) {
      NWindow* window = nwindowGetDefault();
      if (!window || !nwindowIsValid(window)) {
        REXLOG_ERROR("deko3d: no default NWindow for the swapchain");
        return;
      }
      // The swapchain is the NWindow's size (the display's); a frame of a
      // different size is scaled into it below. Three images: the screenshot
      // service and the compositor can hold one each while the app still has
      // one to acquire (two images deadlocked the render thread on capture).
      plume::RenderSwapChainDesc desc(window, kSwapChainFormat, 3);
      swapchain_ = queue_->createSwapChain(desc);
      if (!swapchain_) {
        REXLOG_ERROR("deko3d: could not create the swapchain");
        return;
      }
      REXLOG_INFO("deko3d: swapchain {}x{}, frame {}x{}", swapchain_->getWidth(), swapchain_->getHeight(), width,
                  height);
    } else if (swapchain_->needsResize()) {
      REXLOG_INFO("deko3d: the window changed size; resizing the swapchain");
      if (!swapchain_->resize()) {
        REXLOG_ERROR("deko3d: could not resize the swapchain");
        return;
      }
      REXLOG_INFO("deko3d: swapchain {}x{}, frame {}x{}", swapchain_->getWidth(), swapchain_->getHeight(), width,
                  height);
    }
    // The renderer's frame submission signals this fence; the copy must not
    // read the image before it.
    if (fence) queue_->waitForCommandFence(fence);
    // HOME, sleep and the screen capture can stop the display taking frames.
    // Queueing another one then blocks in the window's buffer queue (and with
    // it the game's logic thread): pause until the applet is in focus again.
    const bool focused = appletGetFocusState() == AppletFocusState_InFocus;
    if (focused != focused_) {
      focused_ = focused;
      REXLOG_INFO("deko3d: presenting {}", focused ? "resumed" : "paused (the applet has no focus)");
    }
    if (!focused) return;
    // The previous frame's copy must be done before its command list is begun
    // again. Its fence signs before the present, so a paused display does not
    // hold this wait.
    if (copy_pending_) {
      queue_->waitForCommandFence(copy_fence_.get());
      copy_pending_ = false;
    }
    uint32_t index = 0;
    if (!swapchain_->acquireTexture(nullptr, &index)) return;
    plume::RenderTexture* dst = swapchain_->getTexture(index);
    if (!dst) return;
    if (!copy_list_ || !copy_fence_) return;
    copy_list_->begin();
    if (swapchain_->getWidth() != width || swapchain_->getHeight() != height) {
      // The NWindow is a different size from the frame: the 2D engine scales
      // it (a plain copy would leave the rest of the swapchain undefined).
      static_cast<plume::Deko3DCommandList*>(copy_list_.get())->blitTexture(dst, image.get());
    } else {
      copy_list_->copyTexture(dst, image.get());
    }
    copy_list_->end();
    queue_->executeCommandLists(copy_list_.get(), copy_fence_.get());
    copy_pending_ = true;
    // The queue orders the copy before the present; no CPU wait for the copy.
    swapchain_->present(index, nullptr, 0);
  }

  bool GetFrame(rex::external_frame::Frame& frame) override {
    (void)frame;
    return false;
  }

  void ClearFrame() override {}

  bool DeviceLost(plume::RenderDevice* device) override {
    return plume::Deko3DDeviceLost(device);
  }

  void ReportDeviceLost(plume::RenderDevice* device) override {
    REXLOG_ERROR("deko3d: the GPU queue is in an error state ({})", device ? "device" : "no device");
  }

  void ReleaseFence(plume::RenderCommandFence* fence) override { (void)fence; }

  void DrainDebugMessages(plume::RenderDevice* device) override { (void)device; }

  void LogBuffer(plume::RenderBuffer* buffer, uint64_t size) override {
    (void)buffer;
    (void)size;
  }

  bool PipelineCreated(plume::RenderPipeline* pipeline) override {
    // (a pipeline whose shader failed to compile would draw nothing)
    return pipeline && static_cast<plume::Deko3DGraphicsPipeline*>(pipeline)->valid;
  }

  void StallQueue(plume::RenderCommandQueue* queue) override { (void)queue; }

  void LoadPipelineCache(plume::RenderDevice* device, const std::filesystem::path& file) override {
    (void)device;
    (void)file;
    // deko3d caches its DKSH variants through uam; the Vulkan/D3D12 pipeline
    // cache file is not used here.
  }

  void SavePipelineCache(plume::RenderDevice* device, const std::filesystem::path& file) override {
    (void)device;
    (void)file;
  }

 private:
  plume::RenderDevice* device_ = nullptr;
  std::unique_ptr<plume::RenderCommandQueue> queue_;
  std::unique_ptr<plume::RenderSwapChain> swapchain_;
  std::unique_ptr<plume::RenderCommandList> copy_list_;
  std::unique_ptr<plume::RenderCommandFence> copy_fence_;
  bool copy_pending_ = false;
  bool focused_ = true;
};

}  // namespace

std::unique_ptr<Backend> CreateDeko3DBackend() {
  return std::make_unique<Deko3DBackend>();
}

}  // namespace svr2011::native::backend
