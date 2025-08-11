// This file is part of the FidelityFX SDK.
//
// Copyright (C) 2024 Advanced Micro Devices, Inc.
// 
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files(the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and /or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions :
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

// Converted to WGSL for Babylon.js

#define FSR3UPSCALER_BIND_SRV_INPUT_MOTION_VECTORS                      0
#define FSR3UPSCALER_BIND_SRV_INPUT_DEPTH                               1
#define FSR3UPSCALER_BIND_SRV_INPUT_COLOR                               2

#define FSR3UPSCALER_BIND_UAV_DILATED_MOTION_VECTORS                    3
#define FSR3UPSCALER_BIND_UAV_DILATED_DEPTH                             4
#define FSR3UPSCALER_BIND_UAV_RECONSTRUCTED_PREV_NEAREST_DEPTH          5
#define FSR3UPSCALER_BIND_UAV_FARTHEST_DEPTH                            6
#define FSR3UPSCALER_BIND_UAV_CURRENT_LUMA                              7

#define FSR3UPSCALER_BIND_CB_FSR3UPSCALER                               8

#include<fsr3UboDeclaration>
#include<fsr3Callbacks>

fn ReconstructPrevDepth(iPxPos: vec2i, fDepth: f32, fMotionVector: vec2f)
{
    let fNearestDepthInMeters = min(GetViewSpaceDepthInMeters(fDepth), FSR3UPSCALER_FP16_MAX);
    let fReconstructedDeptMvThreshold = ReconstructedDepthMvPxThreshold(fNearestDepthInMeters);

    // Discard small mvs
    fMotionVector *= f32(Get4KVelocity(fMotionVector) > fReconstructedDeptMvThreshold);

    let fUv = (iPxPos + f32(0.5)) / RenderSize();
    let fReprojectedUv = fUv + fMotionVector;
    let bilinearInfo = GetBilinearSamplingData(fReprojectedUv, RenderSize());

    // Project current depth into previous frame locations.
    // Push to all pixels having some contribution if reprojection is using bilinear logic.
    for (var iSampleIndex = 0; iSampleIndex < 4; iSampleIndex += 1) {
        
        let iOffset = bilinearInfo.iOffsets[iSampleIndex];
        let fWeight = bilinearInfo.fWeights[iSampleIndex];

        if (fWeight > fReconstructedDepthBilinearWeightThreshold) {

            let iStorePos = bilinearInfo.iBasePos + iOffset;
            if (IsOnScreen(iStorePos, RenderSize())) {
                StoreReconstructedDepth(iStorePos, fDepth);
            }
        }
    }
}

struct DepthExtents
{
    fNearest: f32,
    fNearestCoord: vec2i,
    fFarthest: f32,
}

fn FindDepthExtents(iPxPos: vec2i) -> DepthExtents
{
    var extents: DepthExtents;
    let iSampleCount = 9;
    let iSampleOffsets = array(
        FfxInt32x2(+0, +0),
        FfxInt32x2(+1, +0),
        FfxInt32x2(+0, +1),
        FfxInt32x2(+0, -1),
        FfxInt32x2(-1, +0),
        FfxInt32x2(-1, +1),
        FfxInt32x2(+1, +1),
        FfxInt32x2(-1, -1),
        FfxInt32x2(+1, -1),
    );

    // pull out the depth loads to allow SC to batch them
    let depth: array<f32, 9>;
    let iSampleIndex = 0;
    for (iSampleIndex = 0; iSampleIndex < iSampleCount; iSampleIndex += 1) {

        FfxInt32x2 iPos     = iPxPos + iSampleOffsets[iSampleIndex];
        depth[iSampleIndex] = LoadInputDepth(iPos);
    }

    // find closest depth
    extents.fNearestCoord   = iPxPos;
    extents.fNearest        = depth[0];
    extents.fFarthest       = depth[0];
    for (iSampleIndex = 1; iSampleIndex < iSampleCount; ++iSampleIndex) {

        let iPos = iPxPos + iSampleOffsets[iSampleIndex];
        if (IsOnScreen(iPos, RenderSize())) {

            FfxFloat32 fNdDepth = depth[iSampleIndex];
#if FFX_FSR3UPSCALER_OPTION_INVERTED_DEPTH
            if (fNdDepth > extents.fNearest) {
                extents.fFarthest       = min(extents.fFarthest, fNdDepth);
#else
            if (fNdDepth < extents.fNearest) {
                extents.fFarthest       = max(extents.fFarthest, fNdDepth);
#endif
                extents.fNearestCoord   = iPos;
                extents.fNearest        = fNdDepth;
            }
        }
    }

    return extents;
}

fn DilateMotionVector(iPxPos: vec2i, depthExtents: DepthExtents) -> vec2f
{
#if FFX_FSR3UPSCALER_OPTION_LOW_RESOLUTION_MOTION_VECTORS
    let iSamplePos       = iPxPos;
    let iMotionVectorPos = depthExtents.fNearestCoord;
#else
    // TODO
    const FfxInt32x2 iSamplePos       = ComputeHrPosFromLrPos(iPxPos);
    const FfxInt32x2 iMotionVectorPos = ComputeHrPosFromLrPos(depthExtents.fNearestCoord);
#endif

    let fDilatedMotionVector = LoadInputMotionVector(iMotionVectorPos);

    return fDilatedMotionVector;
}

FfxFloat32 GetCurrentFrameLuma(FfxInt32x2 iPxPos)
{
    //We assume linear data. if non-linear input (sRGB, ...),
    //then we should convert to linear first and back to sRGB on output.
    const FfxFloat32x3 fRgb = ffxMax(FfxFloat32x3(0, 0, 0), LoadInputColor(iPxPos));
    const FfxFloat32 fLuma  = RGBToLuma(fRgb);

    return fLuma;
}

void PrepareInputs(FfxInt32x2 iPxPos)
{
    const DepthExtents depthExtents = FindDepthExtents(iPxPos);
    const FfxFloat32x2 fDilatedMotionVector = DilateMotionVector(iPxPos, depthExtents);

    ReconstructPrevDepth(iPxPos, depthExtents.fNearest, fDilatedMotionVector);

    StoreDilatedMotionVector(iPxPos, fDilatedMotionVector);
    StoreDilatedDepth(iPxPos, depthExtents.fNearest);

    const FfxFloat32 fFarthestDepthInMeters = ffxMin(GetViewSpaceDepthInMeters(depthExtents.fFarthest), FSR3UPSCALER_FP16_MAX);
    StoreFarthestDepth(iPxPos, fFarthestDepthInMeters);

    const FfxFloat32 fLuma = GetCurrentFrameLuma(iPxPos);
    StoreCurrentLuma(iPxPos, fLuma);
}