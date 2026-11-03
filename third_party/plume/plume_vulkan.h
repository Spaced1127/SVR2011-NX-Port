//
// plume
//
// Copyright (c) 2024 renderbag and contributors. All rights reserved.
// Licensed under the MIT license. See LICENSE file for details.
//

#pragma once

#include "plume_render_interface.h"

#include <mutex>
#include <set>
#include <unordered_map>
#include <unordered_set>

#if defined(_WIN32)
#define VK_USE_PLATFORM_WIN32_KHR
#elif defined(__ANDROID__)
#define VK_USE_PLATFORM_ANDROID_KHR
#elif defined(__linux__) && !defined(PLUME_SDL_VULKAN_ENABLED)
#define VK_USE_PLATFORM_XLIB_KHR
#elif defined(__APPLE__)
#define VK_USE_PLATFORM_METAL_EXT
#include "plume_apple.h"
#endif

// For VK_KHR_portability_subset
#define VK_ENABLE_BETA_EXTENSIONS

#if defined(__SWITCH__)
// NVK is linked statically and exports the Vulkan entry points as functions.
// Volk's globals of the same names would collide with them and take the
// runtime's direct calls (the crash was a jump into Volk's BSS
// vkGetInstanceProcAddr). Keep plume's Volk pointers under plume_* names.
#include "plume_volk_names.h"
#endif
#include <volk.h>

#ifdef __clang__
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"
#endif

#include "plume_vma_names.h"  // [svr2011] keep plume's VMA separate from the runtime's
#include <vk_mem_alloc.h>

#ifdef __clang__
#pragma clang diagnostic pop
#endif

namespace plume {
    struct VulkanCommandQueue;
    struct VulkanDevice;
    struct VulkanInterface;
    struct VulkanPool;
    struct VulkanQueue;

    struct VulkanBuffer : RenderBuffer {
        VkBuffer vk = VK_NULL_HANDLE;
        VulkanDevice *device = nullptr;
        VulkanPool *pool = nullptr;
        VmaAllocation allocation = VK_NULL_HANDLE;
        VmaAllocationInfo allocationInfo = {};
        RenderBufferDesc desc;
        RenderBarrierStages barrierStages = RenderBarrierStage::NONE;
        mutable uint64_t deviceAddress = 0;  // [svr2011] (asked once: the driver call is per draw)

        VulkanBuffer() = default;
        VulkanBuffer(VulkanDevice *device, VulkanPool *pool, const RenderBufferDesc &desc);
        ~VulkanBuffer() override;
        void *map(uint32_t subresource, const RenderRange *readRange) override;
        void unmap(uint32_t subresource, const RenderRange *writtenRange) override;
        std::unique_ptr<RenderBufferFormattedView> createBufferFormattedView(RenderFormat format) override;
        void setName(const std::string &name) override;
        uint64_t getDeviceAddress() const override;
    };

    struct VulkanBufferFormattedView : RenderBufferFormattedView {
        VkBufferView vk = VK_NULL_HANDLE;
        VulkanBuffer *buffer = nullptr;

        VulkanBufferFormattedView(VulkanBuffer *buffer, RenderFormat format);
        ~VulkanBufferFormattedView() override;
    };

    struct VulkanTexture : RenderTexture {
        VkImage vk = VK_NULL_HANDLE;
        VkImageView imageView = VK_NULL_HANDLE;
        VkFormat imageFormat = VK_FORMAT_UNDEFINED;
        VkImageSubresourceRange imageSubresourceRange = {};
        VulkanDevice *device = nullptr;
        VulkanPool *pool = nullptr;
        VmaAllocation allocation = VK_NULL_HANDLE;
        VmaAllocationInfo allocationInfo = {};
        RenderTextureLayout textureLayout = RenderTextureLayout::UNKNOWN;
        RenderBarrierStages barrierStages = RenderBarrierStage::NONE;
        bool ownership = false;
        RenderTextureDesc desc;

        VulkanTexture() = default;
        VulkanTexture(VulkanDevice *device, VulkanPool *pool, const RenderTextureDesc &desc);
        VulkanTexture(VulkanDevice *device, VkImage image);
        ~VulkanTexture() override;
        void createImageView(VkFormat format);
        std::unique_ptr<RenderTextureView> createTextureView(const RenderTextureViewDesc &desc) const override;
        void setName(const std::string &name) override;
        void fillSubresourceRange();
    };

    struct VulkanTextureView : RenderTextureView {
        VkImageView vk = VK_NULL_HANDLE;
        const VulkanTexture *texture = nullptr;
        RenderTextureViewDesc desc;

        VulkanTextureView(const VulkanTexture *texture, const RenderTextureViewDesc &desc);
        ~VulkanTextureView() override;
    };

    struct VulkanAccelerationStructure : RenderAccelerationStructure {
        VkAccelerationStructureKHR vk = VK_NULL_HANDLE;
        VulkanDevice *device = nullptr;
        RenderAccelerationStructureType type = RenderAccelerationStructureType::UNKNOWN;

        VulkanAccelerationStructure(VulkanDevice *device, const RenderAccelerationStructureDesc &desc);
        ~VulkanAccelerationStructure() override;
    };

    struct VulkanDescriptorSetLayout {
        VkDescriptorSetLayout vk = VK_NULL_HANDLE;
        std::vector<VkDescriptorSetLayoutBinding> setBindings;
        std::vector<uint32_t> descriptorIndexBases;
        std::vector<uint32_t> descriptorBindingIndices;
        VulkanDevice *device = nullptr;

        VulkanDescriptorSetLayout(VulkanDevice *device, const RenderDescriptorSetDesc &descriptorSetDesc);
        ~VulkanDescriptorSetLayout();
    };

    struct VulkanPipelineLayout : RenderPipelineLayout {
        VkPipelineLayout vk = VK_NULL_HANDLE;
        std::vector<VkPushConstantRange> pushConstantRanges;
        std::vector<VulkanDescriptorSetLayout *> descriptorSetLayouts;
        VulkanDevice *device = nullptr;

        VulkanPipelineLayout(VulkanDevice *device, const RenderPipelineLayoutDesc &desc);
        ~VulkanPipelineLayout() override;
    };

    struct VulkanShader : RenderShader {
        VkShaderModule vk = VK_NULL_HANDLE;
        std::string entryPointName;
        VulkanDevice *device = nullptr;
        RenderShaderFormat format = RenderShaderFormat::UNKNOWN;

        VulkanShader(VulkanDevice *device, const void *data, uint64_t size, const char *entryPointName, RenderShaderFormat format);
        ~VulkanShader() override;
        virtual void setName(const std::string &name) override;
    };

    struct VulkanSampler : RenderSampler {
        VkSampler vk = VK_NULL_HANDLE;
        VulkanDevice *device = nullptr;

        VulkanSampler(VulkanDevice *device, const RenderSamplerDesc &desc);
        ~VulkanSampler();
    };

    struct VulkanPipeline : RenderPipeline {
        enum class Type {
            Unknown,
            Compute,
            Graphics,
            Raytracing
        };

        VulkanDevice *device = nullptr;
        Type type = Type::Unknown;

        VulkanPipeline(VulkanDevice *device, Type type);
        virtual ~VulkanPipeline() override;
    };

    struct VulkanComputePipeline : VulkanPipeline {
        VkPipeline vk = VK_NULL_HANDLE;
        VkPipelineLayout pipelineLayout = VK_NULL_HANDLE;

        VulkanComputePipeline(VulkanDevice *device, const RenderComputePipelineDesc &desc);
        ~VulkanComputePipeline() override;
        void setName(const std::string &name) override;
        RenderPipelineProgram getProgram(const std::string &name) const override;
    };

    struct VulkanGraphicsPipeline : VulkanPipeline {
        VkPipeline vk = VK_NULL_HANDLE;
        VkRenderPass renderPass = VK_NULL_HANDLE;

        VulkanGraphicsPipeline(VulkanDevice *device, const RenderGraphicsPipelineDesc &desc);
        ~VulkanGraphicsPipeline() override;
        void setName(const std::string &name) override;
        RenderPipelineProgram getProgram(const std::string &name) const override;
        static VkRenderPass createRenderPass(VulkanDevice *device, const VkFormat *renderTargetFormat, uint32_t renderTargetCount, VkFormat depthTargetFormat, VkSampleCountFlagBits sampleCount);
    };

    struct VulkanRaytracingPipeline : VulkanPipeline {
        VkPipeline vk = VK_NULL_HANDLE;
        std::unordered_map<std::string, RenderPipelineProgram> nameProgramMap;
        uint32_t groupCount = 0;
        uint32_t descriptorSetCount = 0;

        VulkanRaytracingPipeline(VulkanDevice *device, const RenderRaytracingPipelineDesc &desc, const RenderPipeline *previousPipeline);
        ~VulkanRaytracingPipeline() override;
        void setName(const std::string &name) override;
        RenderPipelineProgram getProgram(const std::string &name) const override;
    };

    struct VulkanDescriptorSet : RenderDescriptorSet {
        VkDescriptorSet vk = VK_NULL_HANDLE;
        VulkanDescriptorSetLayout *setLayout = nullptr;
        VkDescriptorPool descriptorPool = VK_NULL_HANDLE;
        VulkanDevice *device = nullptr;

        VulkanDescriptorSet(VulkanDevice *device, const RenderDescriptorSetDesc &desc);
        ~VulkanDescriptorSet() override;
        void setBuffer(uint32_t descriptorIndex, const RenderBuffer *buffer, uint64_t bufferSize, const RenderBufferStructuredView *bufferStructuredView, const RenderBufferFormattedView *bufferFormattedView) override;
        void setTexture(uint32_t descriptorIndex, const RenderTexture *texture, RenderTextureLayout textureLayout, const RenderTextureView *textureView) override;
        void setSampler(uint32_t descriptorIndex, const RenderSampler *sampler) override;
        void setAccelerationStructure(uint32_t descriptorIndex, const RenderAccelerationStructure *accelerationStructure) override;
        void setDescriptor(uint32_t descriptorIndex, const VkDescriptorBufferInfo *bufferInfo, const VkDescriptorImageInfo *imageInfo, const VkBufferView *texelBufferView, void *pNext);
        static VkDescriptorPool createDescriptorPool(VulkanDevice *device, const std::unordered_map<VkDescriptorType, uint32_t> &typeCounts, bool lastRangeIsBoundless);
    };

    struct VulkanSwapChain : RenderSwapChain {
        RenderSwapChainDesc desc;
        VkSwapchainKHR vk = VK_NULL_HANDLE;
        VulkanCommandQueue *commandQueue = nullptr;
        VkSurfaceKHR surface = VK_NULL_HANDLE;
#if defined(__APPLE__)
        std::unique_ptr<CocoaWindow> windowWrapper;
#endif
        uint64_t presentCount = 0;
        uint32_t width = 0;
        uint32_t height = 0;
        VkSwapchainCreateInfoKHR createInfo = {};
        VkSurfaceFormatKHR pickedSurfaceFormat = {};
        VkPresentModeKHR createdPresentMode = VK_PRESENT_MODE_FIFO_KHR;
        VkPresentModeKHR requiredPresentMode = VK_PRESENT_MODE_FIFO_KHR;
        VkCompositeAlphaFlagBitsKHR pickedAlphaFlag = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
        std::vector<VulkanTexture> textures;
        uint64_t currentPresentId = 0;
        bool immediatePresentModeSupported = false;
        bool mailboxPresentModeSupported = false;

        VulkanSwapChain(VulkanCommandQueue *commandQueue, const RenderSwapChainDesc &desc);
        ~VulkanSwapChain() override;
        bool present(uint32_t textureIndex, RenderCommandSemaphore **waitSemaphores, uint32_t waitSemaphoreCount) override;
        void wait() override;
        bool resize() override;
        bool needsResize() const override;
        void setVsyncEnabled(bool vsyncEnabled) override;
        bool isVsyncEnabled() const override;
        uint32_t getWidth() const override;
        uint32_t getHeight() const override;
        RenderTexture *getTexture(uint32_t textureIndex) override;
        uint32_t getTextureCount() const override;
        bool acquireTexture(RenderCommandSemaphore *signalSemaphore, uint32_t *textureIndex) override;
        RenderWindow getWindow() const override;
        bool isEmpty() const override;
        uint32_t getRefreshRate() const override;
        void getWindowSize(uint32_t &dstWidth, uint32_t &dstHeight) const;
        void releaseSwapChain();
        void releaseImageViews();
    };

    struct VulkanFramebuffer : RenderFramebuffer {
        VulkanDevice *device = nullptr;
        VkFramebuffer vk = VK_NULL_HANDLE;
        VkRenderPass renderPass = VK_NULL_HANDLE;
        std::vector<const VulkanTexture *> colorAttachments;
        const VulkanTexture *depthAttachment = nullptr;
        std::unique_ptr<VulkanTextureView> depthAttachmentView = nullptr;
        bool depthAttachmentReadOnly = false;
        uint32_t width = 0;
        uint32_t height = 0;

        VulkanFramebuffer(VulkanDevice *device, const RenderFramebufferDesc &desc);
        ~VulkanFramebuffer() override;
        uint32_t getWidth() const override;
        uint32_t getHeight() const override;
        bool contains(const VulkanTexture *attachment) const;
    };

    struct VulkanQueryPool : RenderQueryPool {
        VulkanDevice *device = nullptr;
        std::vector<uint64_t> results;
        VkQueryPool vk = VK_NULL_HANDLE;

        VulkanQueryPool(VulkanDevice *device, uint32_t queryCount);
        virtual ~VulkanQueryPool() override;
        virtual void queryResults() override;
        virtual const uint64_t *getResults() const override;
        virtual uint32_t getCount() const override;
    };

    struct VulkanCommandList : RenderCommandList {
        VkCommandBuffer vk = VK_NULL_HANDLE;
        VkCommandPool commandPool = VK_NULL_HANDLE;
        VulkanCommandQueue *queue = nullptr;
        const VulkanFramebuffer *targetFramebuffer = nullptr;
        const VulkanPipelineLayout *activeComputePipelineLayout = nullptr;
        const VulkanPipelineLayout *activeGraphicsPipelineLayout = nullptr;
        const VulkanPipelineLayout *activeRaytracingPipelineLayout = nullptr;
        VkRenderPass activeRenderPass = VK_NULL_HANDLE;

        VulkanCommandList(VulkanCommandQueue *queue);
        ~VulkanCommandList() override;
        void begin() override;
        void end() override;
        void barriers(RenderBarrierStages stages, const RenderBufferBarrier *bufferBarriers, uint32_t bufferBarriersCount, const RenderTextureBarrier *textureBarriers, uint32_t textureBarriersCount) override;
        void dispatch(uint32_t threadGroupCountX, uint32_t threadGroupCountY, uint32_t threadGroupCountZ) override;
        void traceRays(uint32_t width, uint32_t height, uint32_t depth, RenderBufferReference shaderBindingTable, const RenderShaderBindingGroupsInfo &shaderBindingGroupsInfo) override;
        void drawInstanced(uint32_t vertexCountPerInstance, uint32_t instanceCount, uint32_t startVertexLocation, uint32_t startInstanceLocation) override;
        void drawIndexedInstanced(uint32_t indexCountPerInstance, uint32_t instanceCount, uint32_t startIndexLocation, int32_t baseVertexLocation, uint32_t startInstanceLocation) override;
        void setPipeline(const RenderPipeline *pipeline) override;
        void setComputePipelineLayout(const RenderPipelineLayout *pipelineLayout) override;
        void setComputePushConstants(uint32_t rangeIndex, const void *data, uint32_t offset = 0, uint32_t size = 0) override;
        void setComputeDescriptorSet(RenderDescriptorSet *descriptorSet, uint32_t setIndex) override;
        void setGraphicsPipelineLayout(const RenderPipelineLayout *pipelineLayout) override;
        void setGraphicsPushConstants(uint32_t rangeIndex, const void *data, uint32_t offset = 0, uint32_t size = 0) override;
        void setGraphicsDescriptorSet(RenderDescriptorSet *descriptorSet, uint32_t setIndex) override;
        void setGraphicsDescriptorSetDynamic(RenderDescriptorSet *descriptorSet, uint32_t setIndex,
                                             const uint32_t *dynamicOffsets, uint32_t dynamicOffsetCount) override;
        void setGraphicsRootDescriptor(RenderBufferReference bufferReference, uint32_t rootDescriptorIndex) override;
        void setRaytracingPipelineLayout(const RenderPipelineLayout *pipelineLayout) override;
        void setRaytracingPushConstants(uint32_t rangeIndex, const void *data, uint32_t offset = 0, uint32_t size = 0) override;
        void setRaytracingDescriptorSet(RenderDescriptorSet *descriptorSet, uint32_t setIndex) override;
        void setIndexBuffer(const RenderIndexBufferView *view) override;
        void setVertexBuffers(uint32_t startSlot, const RenderVertexBufferView *views, uint32_t viewCount, const RenderInputSlot *inputSlots) override;
        void setViewports(const RenderViewport *viewports, uint32_t count) override;
        void setScissors(const RenderRect *scissorRects, uint32_t count) override;
        void setFramebuffer(const RenderFramebuffer *framebuffer) override;
        void setDepthBias(float depthBias, float depthBiasClamp, float slopeScaledDepthBias) override;
        void setStencilReference(uint32_t stencilReference) override;
        void setBlendFactor(const float blendFactor[4]) override;
        void clearColor(uint32_t attachmentIndex, RenderColor colorValue, const RenderRect *clearRects, uint32_t clearRectsCount) override;
        void clearDepthStencil(bool clearDepth, bool clearStencil, float depthValue, uint32_t stencilValue, const RenderRect *clearRects, uint32_t clearRectsCount) override;
        void copyBufferRegion(RenderBufferReference dstBuffer, RenderBufferReference srcBuffer, uint64_t size) override;
        void copyTextureRegion(const RenderTextureCopyLocation &dstLocation, const RenderTextureCopyLocation &srcLocation, uint32_t dstX, uint32_t dstY, uint32_t dstZ, const RenderBox *srcBox) override;
        void copyBuffer(const RenderBuffer *dstBuffer, const RenderBuffer *srcBuffer) override;
        void copyTexture(const RenderTexture *dstTexture, const RenderTexture *srcTexture) override;
        void resolveTexture(const RenderTexture *dstTexture, const RenderTexture *srcTexture) override;
        void resolveTextureRegion(const RenderTexture *dstTexture, uint32_t dstX, uint32_t dstY, const RenderTexture *srcTexture, const RenderRect *srcRect, RenderResolveMode resolveMode) override;
        void buildBottomLevelAS(const RenderAccelerationStructure *dstAccelerationStructure, RenderBufferReference scratchBuffer, const RenderBottomLevelASBuildInfo &buildInfo) override;
        void buildTopLevelAS(const RenderAccelerationStructure *dstAccelerationStructure, RenderBufferReference scratchBuffer, RenderBufferReference instancesBuffer, const RenderTopLevelASBuildInfo &buildInfo) override;
        void discardTexture(const RenderTexture* texture) override;
        void resetQueryPool(const RenderQueryPool *queryPool, uint32_t queryFirstIndex, uint32_t queryCount) override;
        void writeTimestamp(const RenderQueryPool *queryPool, uint32_t queryIndex) override;
        void checkActiveRenderPass();
        void endActiveRenderPass();
        void setDescriptorSet(VkPipelineBindPoint bindPoint, const VulkanPipelineLayout *pipelineLayout, const RenderDescriptorSet *descriptorSet, uint32_t setIndex);
    };

    struct VulkanCommandFence : RenderCommandFence {
        VkFence vk = VK_NULL_HANDLE;
        VulkanDevice *device = nullptr;

        VulkanCommandFence(VulkanDevice *device);
        ~VulkanCommandFence() override;
    };

    struct VulkanCommandSemaphore : RenderCommandSemaphore {
        VkSemaphore vk = VK_NULL_HANDLE;
        VulkanDevice *device = nullptr;

        VulkanCommandSemaphore(VulkanDevice *device);
        ~VulkanCommandSemaphore() override;
    };

    struct VulkanCommandQueue : RenderCommandQueue {
        VulkanQueue *queue = nullptr;
        VulkanDevice *device = nullptr;
        uint32_t familyIndex = 0;
        uint32_t queueIndex = 0;
        std::unordered_set<VulkanSwapChain *> swapChains;
        RenderCommandListType type = RenderCommandListType::UNKNOWN;

        VulkanCommandQueue(VulkanDevice *device, RenderCommandListType type);
        ~VulkanCommandQueue() override;
        std::unique_ptr<RenderCommandList> createCommandList() override;
        std::unique_ptr<RenderSwapChain> createSwapChain(const RenderSwapChainDesc &desc) override;
        void executeCommandLists(const RenderCommandList **commandLists, uint32_t commandListCount, RenderCommandSemaphore **waitSemaphores, uint32_t waitSemaphoreCount, RenderCommandSemaphore **signalSemaphores, uint32_t signalSemaphoreCount, RenderCommandFence *signalFence) override;
        void waitForCommandFence(RenderCommandFence *fence) override;
        bool waitForCommandFenceTimeout(RenderCommandFence *fence, uint32_t timeoutMs) override;
    };

    struct VulkanPool : RenderPool {
        VmaPool vk = VK_NULL_HANDLE;
        VulkanDevice *device = nullptr;

        VulkanPool(VulkanDevice *device, const RenderPoolDesc &desc);
        ~VulkanPool() override;
        std::unique_ptr<RenderBuffer> createBuffer(const RenderBufferDesc &desc) override;
        std::unique_ptr<RenderTexture> createTexture(const RenderTextureDesc &desc) override;
    };
    
    struct VulkanQueue {
        VkQueue vk;
        // [svr2011] recursive and possibly borrowed: an adopted device's queue is locked by its owner too.
        std::unique_ptr<std::recursive_mutex> ownedMutex;
        std::recursive_mutex *mutex = nullptr;
        std::unordered_set<const VulkanCommandQueue *> virtualQueues;
    };

    struct VulkanQueueFamily {
        std::vector<VulkanQueue> queues;

        void add(VulkanCommandQueue *virtualQueue);
        void remove(VulkanCommandQueue *virtualQueue);
    };

    struct VulkanDevice : RenderDevice {
        VkDevice vk = VK_NULL_HANDLE;
        VulkanInterface *renderInterface = nullptr;
        VkPhysicalDevice physicalDevice = VK_NULL_HANDLE;
        VkPhysicalDeviceProperties physicalDeviceProperties = {};
        VmaAllocator allocator = VK_NULL_HANDLE;
        uint32_t queueFamilyIndices[3] = {};
        std::vector<VulkanQueueFamily> queueFamilies;
        RenderDeviceCapabilities capabilities;
        RenderDeviceDescription description;
        VkPhysicalDeviceRayTracingPipelinePropertiesKHR rtPipelineProperties = {};
        VkPhysicalDeviceSampleLocationsPropertiesEXT sampleLocationProperties = {};
        std::unique_ptr<RenderBuffer> nullBuffer;
        bool loadStoreOpNoneSupported = false;
        bool nullDescriptorSupported = false;
        bool ownsDevice = true;  // [svr2011] false: adopted (VulkanExistingDevice)
        VkPipelineCache pipelineCache = VK_NULL_HANDLE;  // [svr2011] for every pipeline (setPipelineCacheData)

        // [svr2011] The pipeline cache's contents: replaced with saved data (a
        // driver ignores data from another driver or GPU) / read to save them.
        bool setPipelineCacheData(const void *data, size_t size);
        std::vector<uint8_t> getPipelineCacheData() const;

        VulkanDevice(VulkanInterface *renderInterface, const std::string &preferredDeviceName);
        VulkanDevice(VulkanInterface *renderInterface, const struct VulkanExistingDevice &existing);  // [svr2011]
        ~VulkanDevice() override;
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
        void setBottomLevelASBuildInfo(RenderBottomLevelASBuildInfo &buildInfo, const RenderBottomLevelASMesh *meshes, uint32_t meshCount, bool preferFastBuild, bool preferFastTrace) override;
        void setTopLevelASBuildInfo(RenderTopLevelASBuildInfo &buildInfo, const RenderTopLevelASInstance *instances, uint32_t instanceCount, bool preferFastBuild, bool preferFastTrace) override;
        void setShaderBindingTableInfo(RenderShaderBindingTableInfo &tableInfo, const RenderShaderBindingGroups &groups, const RenderPipeline *pipeline, RenderDescriptorSet **descriptorSets, uint32_t descriptorSetCount) override;
        const RenderDeviceCapabilities &getCapabilities() const override;
        const RenderDeviceDescription &getDescription() const override;
        RenderSampleCounts getSampleCountsSupported(RenderFormat format) const override;
        void release();
        bool isValid() const;
        bool beginCapture() override;
        bool endCapture() override;
    };

    // [svr2011] A Vulkan instance and device created by someone else (an emulator
    // presenting plume's images): plume draws on them without owning them, so
    // images and queue work are shared directly. The owner must have enabled
    // the features flagged here, and locks queueMutex around its own submissions.
    struct VulkanExistingDevice {
        VkInstance instance = VK_NULL_HANDLE;
        uint32_t apiVersion = VK_API_VERSION_1_2;
        VkPhysicalDevice physicalDevice = VK_NULL_HANDLE;
        VkDevice device = VK_NULL_HANDLE;
        uint32_t queueFamilyIndex = 0;  // graphics, compute and transfer
        VkQueue queue = VK_NULL_HANDLE;
        std::recursive_mutex *queueMutex = nullptr;
        bool descriptorIndexing = false;  // runtime arrays, partially bound, variable count, update after bind
        bool scalarBlockLayout = false;
        bool bufferDeviceAddress = false;
        bool nullDescriptor = false;
        bool samplerMirrorClampToEdge = false;
        bool geometryShader = false;
        // The loader the instance came from (null: the system's libvulkan). A
        // custom GPU driver's loader (Android: libadrenotools) differs from
        // the system's, whose functions can't be used on its objects.
        PFN_vkGetInstanceProcAddr getInstanceProcAddr = nullptr;
    };

    struct VulkanInterface : RenderInterface {
        VkInstance instance = VK_NULL_HANDLE;
        VkApplicationInfo appInfo = {};
        RenderInterfaceCapabilities capabilities;
        std::vector<std::string> deviceNames;
        std::unique_ptr<VulkanExistingDevice> existing;  // [svr2011] adopted instance and device

        VulkanInterface(const VulkanExistingDevice &existing);  // [svr2011]

#   if PLUME_SDL_VULKAN_ENABLED
        VulkanInterface(RenderWindow sdlWindow);
#   else
        VulkanInterface();
#   endif

        ~VulkanInterface() override;
        std::unique_ptr<RenderDevice> createDevice(const std::string &preferredDeviceName) override;
        const RenderInterfaceCapabilities &getCapabilities() const override;
        const std::vector<std::string> &getDeviceNames() const override;
        bool isValid() const;
    };

    // [svr2011]
    std::unique_ptr<RenderInterface> CreateVulkanInterface(const VulkanExistingDevice &existing);
};
