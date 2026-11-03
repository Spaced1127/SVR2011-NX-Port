//
// plume
//
// [svr2011] Direct3D 11 backend - only what a renderer written for the
// D3D12 backend's model needs on GPUs without Direct3D 12 / Vulkan (feature
// level 10_0+): one direct queue, recorded command lists replayed on one
// immediate context, descriptor sets as slot arrays (each range at fixed
// registers: t/s/b = binding + index), root constant buffers, upload and
// readback buffers emulated in CPU memory, no compute, MSAA resolves, queries,
// swap chains or ray tracing (those log once and do nothing).
//
// The immediate context is shared with its creator (the app's presenter):
// every use holds `contextMutex`, and each replay starts from ClearState.
//

#pragma once

#include "plume_render_interface.h"

#include <atomic>
#include <condition_variable>
#include <deque>
#include <mutex>
#include <thread>
#include <unordered_map>
#include <vector>

#include <d3d11_1.h>
#include <wrl/client.h>

namespace plume {
    struct D3D11Device;
    struct D3D11Texture;

    struct D3D11Buffer : RenderBuffer {
        D3D11Device *device = nullptr;
        RenderBufferDesc desc;
        // DEFAULT heap: the buffer itself.
        Microsoft::WRL::ComPtr<ID3D11Buffer> d3d;
        // UPLOAD / READBACK heaps: CPU memory (16-byte aligned).
        uint8_t *cpu = nullptr;
        // UPLOAD: the GPU copies, made at first use - vertex / index data and
        // constants (D3D11.0 forbids combining CONSTANT with other bind flags).
        Microsoft::WRL::ComPtr<ID3D11Buffer> gpuGeometry;
        Microsoft::WRL::ComPtr<ID3D11Buffer> gpuConstants;
        bool gpuGeometryDynamic = false;
        // gpuGeometry is bound as constants too (D3D11.1 runtimes allow it).
        bool combined = false;
        // Rings: bytes already on each GPU copy (geometry, constants) for the
        // list being replayed (its generation) - the next submission of the
        // same list appends.
        uint64_t uploadedEnd[2] = {};
        uint64_t uploadedGeneration[2] = {};
        bool gpuConstantsDynamic = false;
        // Mapped and not unmapped (a persistently mapped ring): uploaded at every
        // submission that uses it. Unmapped since the last upload: dirty.
        std::atomic<bool> mapped = false;
        std::atomic<bool> geometryDirty = true;
        std::atomic<bool> constantsDirty = true;
        // The GPU copies exist (set by the replay, read when recording).
        std::atomic<bool> geometryReady = false;
        std::atomic<bool> constantsReady = false;
        // READBACK: texture copies waiting to be read into `cpu` (at map).
        struct PendingReadback {
            Microsoft::WRL::ComPtr<ID3D11Resource> staging;
            uint32_t subresource = 0;
            uint64_t offset = 0;
            uint32_t rowPitch = 0;     // (the buffer's: the footprint's padded row)
            uint32_t rows = 0;
            uint32_t depth = 1;
            uint32_t rowBytes = 0;     // the staging texture's data per row (its width; the
            uint32_t stagingRows = 0;  // footprint row can be wider) and its rows
        };
        std::mutex readbackMutex;
        std::vector<PendingReadback> readbacks;

        D3D11Buffer(D3D11Device *device, const RenderBufferDesc &desc);
        ~D3D11Buffer() override;
        void *map(uint32_t subresource, const RenderRange *readRange) override;
        void unmap(uint32_t subresource, const RenderRange *writtenRange) override;
        std::unique_ptr<RenderBufferFormattedView> createBufferFormattedView(RenderFormat format) override;
        void setName(const std::string &name) override;
        uint64_t getDeviceAddress() const override { return 0; }
        // The GPU buffer to bind for `constants` or vertex / index use, uploaded
        // to `end` bytes (context lock held).
        ID3D11Buffer *gpu(bool constants, uint64_t end, uint64_t generation = 0);
    };

    struct D3D11TextureView : RenderTextureView {
        const D3D11Texture *texture = nullptr;
        RenderTextureViewDesc desc;
        Microsoft::WRL::ComPtr<ID3D11ShaderResourceView> srv;

        D3D11TextureView(const D3D11Texture *texture, const RenderTextureViewDesc &desc);
    };

    struct D3D11Texture : RenderTexture {
        D3D11Device *device = nullptr;
        RenderTextureDesc desc;
        Microsoft::WRL::ComPtr<ID3D11Resource> d3d;
        mutable std::mutex viewMutex;
        mutable Microsoft::WRL::ComPtr<ID3D11ShaderResourceView> defaultSrv;

        D3D11Texture(D3D11Device *device, const RenderTextureDesc &desc);
        std::unique_ptr<RenderTextureView> createTextureView(const RenderTextureViewDesc &desc) const override;
        void setName(const std::string &name) override;
        ID3D11ShaderResourceView *getDefaultSrv() const;
    };

    struct D3D11Shader : RenderShader {
        D3D11Device *device = nullptr;
        std::vector<uint8_t> code;  // DXBC
        bool isVertex = false;
        Microsoft::WRL::ComPtr<ID3D11VertexShader> vs;
        Microsoft::WRL::ComPtr<ID3D11PixelShader> ps;

        D3D11Shader(D3D11Device *device, const void *data, uint64_t size);
        void setName(const std::string &name) override {}
    };

    struct D3D11Sampler : RenderSampler {
        Microsoft::WRL::ComPtr<ID3D11SamplerState> d3d;
    };

    // Each descriptor's register (t#, s# or b#: the range's binding plus the
    // index in it) and what it holds.
    struct D3D11DescriptorSet : RenderDescriptorSet {
        enum class Kind : uint8_t { NONE, SRV, SAMPLER, CBV };
        struct Entry {
            Kind kind = Kind::NONE;
            uint8_t reg = 0;
        };
        std::vector<Entry> entries;
        std::vector<ID3D11ShaderResourceView *> srvs;   // (AddRef'd)
        std::vector<ID3D11SamplerState *> samplers;     // (AddRef'd)
        std::vector<RenderComponentMapping> mappings;   // the views' swizzles (D3D11 has none)
        std::vector<const D3D11Buffer *> buffers;
        uint32_t version = 0;

        D3D11DescriptorSet(const RenderDescriptorSetDesc &desc);
        ~D3D11DescriptorSet() override;
        void setBuffer(uint32_t descriptorIndex, const RenderBuffer *buffer, uint64_t bufferSize, const RenderBufferStructuredView *bufferStructuredView, const RenderBufferFormattedView *bufferFormattedView) override;
        void setTexture(uint32_t descriptorIndex, const RenderTexture *texture, RenderTextureLayout textureLayout, const RenderTextureView *textureView) override;
        void setSampler(uint32_t descriptorIndex, const RenderSampler *sampler) override;
        void setAccelerationStructure(uint32_t descriptorIndex, const RenderAccelerationStructure *accelerationStructure) override {}
    };

    struct D3D11PipelineLayout : RenderPipelineLayout {
        // Root descriptor i -> b register.
        std::vector<uint8_t> rootRegisters;
    };

    struct D3D11GraphicsPipeline : RenderPipeline {
        Microsoft::WRL::ComPtr<ID3D11VertexShader> vs;
        Microsoft::WRL::ComPtr<ID3D11PixelShader> ps;
        Microsoft::WRL::ComPtr<ID3D11InputLayout> inputLayout;
        Microsoft::WRL::ComPtr<ID3D11BlendState> blend;
        Microsoft::WRL::ComPtr<ID3D11RasterizerState> rasterizer;
        Microsoft::WRL::ComPtr<ID3D11DepthStencilState> depthStencil;
        D3D11_PRIMITIVE_TOPOLOGY topology = D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST;
        uint32_t stencilReference = 0;
        bool dynamicStencilReference = false;
        bool dynamicBlendFactor = false;
        // Vertex slot strides (from the input slots).
        uint32_t strides[D3D11_IA_VERTEX_INPUT_RESOURCE_SLOT_COUNT] = {};
        bool valid = false;

        void setName(const std::string &name) override {}
        RenderPipelineProgram getProgram(const std::string &name) const override { return {}; }
    };

    struct D3D11Framebuffer : RenderFramebuffer {
        uint32_t width = 0;
        uint32_t height = 0;
        std::vector<Microsoft::WRL::ComPtr<ID3D11RenderTargetView>> rtvs;
        Microsoft::WRL::ComPtr<ID3D11DepthStencilView> dsv;

        uint32_t getWidth() const override { return width; }
        uint32_t getHeight() const override { return height; }
    };

    struct D3D11CommandFence : RenderCommandFence {
        std::mutex mutex;
        Microsoft::WRL::ComPtr<ID3D11Query> query;  // the last signal (null: none)
        uint64_t submission = 0;  // the submission that signals it (0: none)
    };

    struct D3D11CommandList;

    // Submissions are replayed on the queue's own thread (D3D11AsyncReplay):
    // the thread recording the next frame doesn't wait for the driver calls.
    struct D3D11CommandQueue : RenderCommandQueue {
        D3D11Device *device = nullptr;
        struct Submission {
            std::vector<const RenderCommandList *> lists;
            D3D11CommandFence *fence = nullptr;
            uint64_t number = 0;
        };
        std::mutex mutex;
        std::condition_variable work, done;
        std::deque<Submission> pending;
        std::atomic<uint64_t> submitted = 0;
        std::atomic<uint64_t> replayed = 0;
        bool stop = false;
        std::thread thread;

        explicit D3D11CommandQueue(D3D11Device *device);
        ~D3D11CommandQueue() override;
        // Replays a submission on the context (lock taken here).
        void replay(const Submission &submission);
        void worker();
        // Waits until submission `number` has been replayed.
        bool waitReplayed(uint64_t number, uint32_t timeoutMs);
        std::unique_ptr<RenderCommandList> createCommandList() override;
        std::unique_ptr<RenderSwapChain> createSwapChain(const RenderSwapChainDesc &desc) override { return nullptr; }
        void executeCommandLists(const RenderCommandList **commandLists, uint32_t commandListCount, RenderCommandSemaphore **waitSemaphores, uint32_t waitSemaphoreCount, RenderCommandSemaphore **signalSemaphores, uint32_t signalSemaphoreCount, RenderCommandFence *signalFence) override;
        void waitForCommandFence(RenderCommandFence *fence) override;
        bool waitForCommandFenceTimeout(RenderCommandFence *fence, uint32_t timeoutMs) override;
    };

    struct D3D11Device : RenderDevice {
        Microsoft::WRL::ComPtr<ID3D11Device> d3d;
        ID3D11DeviceContext *context = nullptr;
        Microsoft::WRL::ComPtr<ID3D11DeviceContext1> context1;
        std::recursive_mutex *contextMutex = nullptr;
        D3D_FEATURE_LEVEL featureLevel = D3D_FEATURE_LEVEL_11_0;
        bool constantBufferOffsetting = false;
        // Dynamic constant buffers can be mapped NO_OVERWRITE (D3D11.1).
        bool mapNoOverwriteConstants = false;
        // A buffer can't be constants and vertices / indices at once here
        // (found at the first try: the runtime refuses it).
        std::atomic<bool> noCombinedBuffers = false;
        RenderDeviceCapabilities capabilities;
        RenderDeviceDescription description;
        // Stats since they were last read (exchange(0)): draws replayed, bytes
        // and time uploading upload buffers, time replaying the commands.
        std::atomic<uint64_t> statDraws = 0;
        std::atomic<uint64_t> statUploadBytes = 0;
        std::atomic<uint64_t> statUploadNs = 0;
        std::atomic<uint64_t> statReplayNs = 0;
        std::atomic<uint64_t> statLockWaitNs = 0;  // (the presenter holding the context)
        std::atomic<uint64_t> statFlushNs = 0;
        // The queue (one): what has been submitted and replayed so far.
        D3D11CommandQueue *queue = nullptr;

        D3D11Device(ID3D11Device *device, ID3D11DeviceContext *context, std::recursive_mutex *contextMutex, bool constantBufferOffsetting);
        std::unique_ptr<RenderDescriptorSet> createDescriptorSet(const RenderDescriptorSetDesc &desc) override;
        std::unique_ptr<RenderShader> createShader(const void *data, uint64_t size, const char *entryPointName, RenderShaderFormat format) override;
        std::unique_ptr<RenderSampler> createSampler(const RenderSamplerDesc &desc) override;
        std::unique_ptr<RenderPipeline> createComputePipeline(const RenderComputePipelineDesc &desc) override;
        std::unique_ptr<RenderPipeline> createGraphicsPipeline(const RenderGraphicsPipelineDesc &desc) override;
        std::unique_ptr<RenderPipeline> createRaytracingPipeline(const RenderRaytracingPipelineDesc &desc, const RenderPipeline *previousPipeline) override;
        std::unique_ptr<RenderCommandQueue> createCommandQueue(RenderCommandListType type) override;
        std::unique_ptr<RenderBuffer> createBuffer(const RenderBufferDesc &desc) override;
        std::unique_ptr<RenderTexture> createTexture(const RenderTextureDesc &desc) override;
        std::unique_ptr<RenderAccelerationStructure> createAccelerationStructure(const RenderAccelerationStructureDesc &desc) override;
        std::unique_ptr<RenderPool> createPool(const RenderPoolDesc &desc) override;
        std::unique_ptr<RenderPipelineLayout> createPipelineLayout(const RenderPipelineLayoutDesc &desc) override;
        std::unique_ptr<RenderCommandFence> createCommandFence() override;
        std::unique_ptr<RenderCommandSemaphore> createCommandSemaphore() override;
        std::unique_ptr<RenderFramebuffer> createFramebuffer(const RenderFramebufferDesc &desc) override;
        std::unique_ptr<RenderQueryPool> createQueryPool(uint32_t queryCount) override;
        void setBottomLevelASBuildInfo(RenderBottomLevelASBuildInfo &buildInfo, const RenderBottomLevelASMesh *meshes, uint32_t meshCount, bool preferFastBuild, bool preferFastTrace) override {}
        void setTopLevelASBuildInfo(RenderTopLevelASBuildInfo &buildInfo, const RenderTopLevelASInstance *instances, uint32_t instanceCount, bool preferFastBuild, bool preferFastTrace) override {}
        void setShaderBindingTableInfo(RenderShaderBindingTableInfo &tableInfo, const RenderShaderBindingGroups &groups, const RenderPipeline *pipeline, RenderDescriptorSet **descriptorSets, uint32_t descriptorSetCount) override {}
        const RenderDeviceCapabilities &getCapabilities() const override { return capabilities; }
        const RenderDeviceDescription &getDescription() const override { return description; }
        RenderSampleCounts getSampleCountsSupported(RenderFormat format) const override { return RenderSampleCount::COUNT_1; }
        bool beginCapture() override { return false; }
        bool endCapture() override { return false; }
    };

    struct D3D11Interface : RenderInterface {
        Microsoft::WRL::ComPtr<ID3D11Device> device;
        ID3D11DeviceContext *context = nullptr;
        std::recursive_mutex *contextMutex = nullptr;
        bool constantBufferOffsetting = false;
        std::vector<std::string> deviceNames;
        RenderInterfaceCapabilities capabilities;

        std::unique_ptr<RenderDevice> createDevice(const std::string &preferredDeviceName) override;
        const std::vector<std::string> &getDeviceNames() const override { return deviceNames; }
        const RenderInterfaceCapabilities &getCapabilities() const override { return capabilities; }
    };

    // The renderer draws on an existing device and immediate context (the
    // presenter's), locking `contextMutex` for every use of the context.
    std::unique_ptr<RenderInterface> CreateD3D11Interface(ID3D11Device *device, ID3D11DeviceContext *context,
                                                          std::recursive_mutex *contextMutex, bool constantBufferOffsetting);

    // The DXGI format of a plume format (TYPELESS where the D3D12 backend uses it).
    DXGI_FORMAT D3D11FormatOf(RenderFormat format);

    // Where the backend's notices go (calls it doesn't support, once each);
    // null: stderr.
    extern void (*D3D11LogFunction)(const char *message);

    // Submissions with fewer draws than this are flushed at once (0: none).
    extern uint32_t D3D11FlushDrawLimit;
    // Submissions replayed on the queue's thread (false: in executeCommandLists).
    extern bool D3D11AsyncReplay;
    // Constant buffers never mapped NO_OVERWRITE, even where the driver says it can (each upload a renamed copy).
    extern bool D3D11NoOverwriteConstantsOff;
};
