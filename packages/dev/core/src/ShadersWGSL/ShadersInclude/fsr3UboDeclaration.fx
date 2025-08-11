#ifdef FSR3UPSCALER_BIND_CB_FSR3UPSCALER
    struct cbFSR3UPSCALER_t
    {
        iRenderSize: vec2i,
        iPreviousFrameRenderSize: vec2i,

        iUpscaleSize: vec2i,
        iPreviousFrameUpscaleSize: ivec2i,

        iMaxRenderSize: vec2i,
        iMaxUpscaleSize: vec2i,

        fDeviceToViewDepth: vec4f,

        fJitter: vec2f,
        fPreviousFrameJitter: vec2f,

        fMotionVectorScale: vec2f,
        fDownscaleFactor: vec2f,

        fMotionVectorJitterCancellation: vec2f,
        fTanHalfFOV: f32,
        fJitterSequenceLength: f32,

        fDeltaTime: f32,
        fDeltaPreExposure: f32,
        fViewSpaceToMetersFactor: f32,
        fFrameIndex: f32,

        fVelocityFactor: f32,
        fReactivenessScale: f32,
        fShadingChangeScale: f32,
        fAccumulationAddedPerFrame: f32,
        fMinDisocclusionAccumulation: f32,
    }

    @group(0) @binding(FSR3UPSCALER_BIND_CB_FSR3UPSCALER)
    var<uniform> cbFSR3Upscaler: cbFSR3UPSCALER_t;
#endif

#ifdef FSR3UPSCALER_BIND_SRV_INPUT_DEPTH
    @group(0) @binding(FSR3UPSCALER_BIND_SRV_INPUT_DEPTH)
    var r_input_depth: texture_2d<f32>;
#endif

#ifdef FSR3UPSCALER_BIND_SRV_INPUT_MOTION_VECTORS
    @group(0) @binding(FSR3UPSCALER_BIND_SRV_INPUT_MOTION_VECTORS) var r_input_motion_vectors: texture_2d<f32>;
#endif

#ifdef FSR3UPSCALER_BIND_UAV_RECONSTRUCTED_PREV_NEAREST_DEPTH
    @group(0) @binding(FSR3UPSCALER_BIND_UAV_RECONSTRUCTED_PREV_NEAREST_DEPTH)
    var<storage, read_write> rw_reconstructed_previous_nearest_depth: array<atomic<u32>>;

    fn StoreReconstructedDepth(iPxSample: vec2i, fDepth: f32)
    {
        let iSampleIndex = iPxSample.y * cbFSR3Upscaler.iRenderSize.x + iPxSample.x;
        let uDepth = bitcast<u32>(fDepth);

        #if FFX_FSR3UPSCALER_OPTION_INVERTED_DEPTH
            atomicMax(&rw_reconstructed_previous_nearest_depth[iSampleIndex], uDepth);
        #else
            atomicMin(&rw_reconstructed_previous_nearest_depth[iSampleIndex], uDepth); // min for standard, max for inverted depth
        #endif
    }
#endif
