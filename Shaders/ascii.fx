#pragma once

/* -----------------------------------------------------*\
||                                                      ||
||       Smart ASCII shader, inspired by Acerola        ||
||     https://github.com/GarrettGunnell/AcerolaFX      ||
|| https://www.youtube.com/watch?v=gg40RWiaHRY&t=889s   ||
||                                                      ||
|| The difference is that here the pixels inside each   ||
|| 8x8 patch are compared with a set of ASCII characters||
|| That are near it's luminance value, and the character||
|| closest overall is then substituted in place of the  ||
|| original pixels. Edge detection is thus implicit,    ||
|| when a character resembling a similar edge to the    ||
|| original render is given.                            ||
|| Luminance downscaling is also performed by averaging ||
|| instead of sampling, thus preserving slightly more   ||
|| information.                                         ||
||                                                      ||
\* -----------------------------------------------------*/

// Modification requires new texture
static const uint ASCIICharacters = 64;
static const uint ASCIIWidth = 8;
static const uint ASCIIHeight = 8;

// Modifiable, but requires recompilation
// Cannot be increased over 16 without additional considerations
// (Shader does compile with 32 alternatives, but some memory accesses seem to go wrong)
static const uint ASCIIAlternatives = 16;

// Internal constants
static const uint PatchSizeBestASCII = 2;
static const uint sharedBufferSize = ASCIIWidth * (ASCIIHeight / 2);

// Configuration
uniform uint _Metric <
    ui_category = "Color Settings";
    ui_category_closed = false;
    ui_min = 1; ui_max = 4;
    ui_label = "Pixel metric";
    ui_type = "slider";
    ui_tooltip = "Distance metric (L-norm exponent) for comparing pixel luminance values";
> = 1;

uniform float _Exposure <
    ui_category = "Color Settings";
    ui_category_closed = false;
    ui_min = 0.0f; ui_max = 5.0f;
    ui_label = "Luminance Exposure";
    ui_type = "slider";
    ui_tooltip = "Multiplication on the base luminance of the image to bring up ASCII characters.";
> = 1.0f;

uniform float _Attenuation <
    ui_category = "Color Settings";
    ui_category_closed = true;
    ui_min = 0.0f; ui_max = 5.0f;
    ui_label = "Luminance Attenuation";
    ui_type = "slider";
    ui_tooltip = "Exponent on the base luminance of the image to bring up ASCII characters.";
> = 1.0f;

uniform bool _InvertLuminance <
    ui_category = "Color Settings";
    ui_category_closed = true;
    ui_label = "Invert ASCII";
    ui_tooltip = "Invert ASCII luminance relationship.";
> = false;

uniform float _BlendWithBase <
    ui_category = "Color Settings";
    ui_category_closed = true;
    ui_min = 0.0f; ui_max = 1.0f;
    ui_label = "Base Color Blend";
    ui_type = "slider";
    ui_tooltip = "Blend ascii characters with underlying color from original render.";
> = 0.0f;

uniform float3 _ASCIIColor <
    ui_category = "Color Settings";
    ui_category_closed = true;
    ui_type = "color";
    ui_label = "ASCII Color";
    ui_spacing = 4;
> = 1.0f;

uniform float3 _BackgroundColor <
    ui_category = "Color Settings";
    ui_category_closed = true;
    ui_type = "color";
    ui_label = "Background Color";
> = 0.0f;


texture2D texColor : COLOR;
sampler2D samplerColor { Texture = texColor; AddressU = BORDER; AddressV = BORDER; };

texture2D ASCIILUT < source = "ascii64.png"; > {Width = ASCIICharacters*ASCIIWidth; Height = ASCIIHeight; };
sampler2D PixelsASCII { Texture = ASCIILUT; AddressU = BORDER; AddressV = BORDER; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT; };

texture2D texLumi{ Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format=R16F; };
sampler2D samplerLumi{ Texture = texLumi; AddressU = BORDER; AddressV = BORDER; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT; };

//texture2D texILumi { Width = BUFFER_WIDTH / ASCIIWidth; Height = BUFFER_HEIGHT / ASCIIHeight; Format = R16F; };
//sampler2D samplerILumi { Texture = texILumi; AddressU = BORDER; AddressV = BORDER; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT; };
// storage2D s_ILumi { Texture = texILumi; };

texture3D texDownscaleInput { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Depth = ASCIIAlternatives; Format = R16F; };
sampler3D samplerDownscaleInput { Texture = texDownscaleInput; AddressU = BORDER; AddressV = BORDER; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT;};
storage3D s_DownscaleInput { Texture = texDownscaleInput; };

texture3D texDownscaled { Width = BUFFER_WIDTH / ASCIIWidth; Height = BUFFER_HEIGHT / ASCIIHeight; Depth = ASCIIAlternatives; Format = R16F; };
sampler3D samplerDownscaled { Texture = texDownscaled; AddressU = BORDER; AddressV = BORDER; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT;};
storage3D s_Downscaled { Texture = texDownscaled; };

texture2D texDownscaledLumi { Width = BUFFER_WIDTH / ASCIIWidth; Height = BUFFER_HEIGHT / ASCIIHeight; Format = R16F; };
sampler2D samplerDownscaledLumi { Texture = texDownscaledLumi; AddressU = BORDER; AddressV = BORDER; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT;};
storage2D s_DownscaledLumi { Texture = texDownscaledLumi; };

texture2D texBestASCII { Width = BUFFER_WIDTH / ASCIIWidth; Height = BUFFER_HEIGHT / ASCIIHeight; Format = R16F; };
sampler2D samplerBestASCII { Texture = texBestASCII; AddressU = BORDER; AddressV = BORDER; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT; };
storage2D s_BestASCII { Texture = texBestASCII; };

texture2D texFinal { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler2D samplerFinal{ Texture = texFinal; AddressU = BORDER; AddressV = BORDER; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT;};
storage2D s_Final{ Texture = texFinal; };

[shader("vertex")]
void FullWindow(uint id : SV_VertexID, out float4 position : SV_Position, out float2 texcoord : TEXCOORD0)
{
	texcoord.x = (id == 2) ? 2.0 : 0.0;
	texcoord.y = (id == 1) ? 2.0 : 0.0;
	position = float4(texcoord * float2(2, -2) + float2(-1, 1), 0, 1);
}

float Luminance(float3 color) {
    return (
        color.b
        + color.r + color.r + color.r
        + color.g + color.g + color.g + color.g
    ) * 0.125;
}

float TransformLuminance(float luminance) {
    float lumi = pow(luminance * _Exposure, _Attenuation);
    if (_InvertLuminance) {
        lumi = 1.0 - lumi;
    }
    return lumi;
}

float PixelLuminance(float4 position : SV_POSITION, float2 uv : TEXCOORD) : SV_TARGET {
    return TransformLuminance(Luminance(saturate(tex2D(samplerColor, uv).rgb)));
}

groupshared float reductionBuffer[sharedBufferSize];
[numthreads(ASCIIWidth, ASCIIHeight / 2, 1)]
void ComputeDownscaleLumi(uint3 gid : SV_GROUPTHREADID, uint3 id : SV_GROUPID) {
    uint sharedAddr = gid.x + gid.y*ASCIIWidth;
    uint2 inputIdx = id.xy * uint2(ASCIIWidth, ASCIIHeight) + gid.xy;
    reductionBuffer[sharedAddr] = (
        tex2Dfetch(samplerLumi, inputIdx).r
        + tex2Dfetch(samplerLumi, inputIdx + uint2(0,4)).r
    );

    // parallel reduction
	for ( int i=sharedBufferSize/2 ; i>0 ; i>>=1) {
		barrier();
		reductionBuffer[sharedAddr] += reductionBuffer[sharedAddr + i];
	}

    if (sharedAddr == 0) {
        tex2Dstore(s_DownscaledLumi, id.xy, 0.5 + reductionBuffer[0] * (ASCIICharacters - ASCIIAlternatives)/ASCIICharacters);
    }
}

// This pixel shader is the bottleneck of the pipeline
void ComputeASCIICloseness(uint3 tid : SV_DISPATCHTHREADID, uint3 gid : SV_GROUPTHREADID, uint3 id : SV_GROUPID) {

	// group thread id is the position inside the 8x8 ascii character
    uint2 ij = gid.xy;

	uint iLumi = (uint)tex2Dfetch(samplerDownscaledLumi, id.xy);

    uint comp = tid.z + iLumi;
    uint2 posASCII = uint2(comp * ASCIIWidth + gid.x, gid.y);
    float lumiASCII = tex2Dfetch(PixelsASCII, posASCII).r;
    float pixelDistance = abs(lumiASCII - tex2Dfetch(samplerLumi, tid.xy).r);
    pixelDistance = pow(pixelDistance, _Metric);
    tex3Dstore(s_DownscaleInput, tid, pixelDistance);
}

groupshared float DownscaleBuffer[sharedBufferSize];
[numthreads(ASCIIWidth, ASCIIHeight / 2, 1)]
void ComputeDownscaleWxHxN(uint3 gid : SV_GROUPTHREADID, uint3 id : SV_GROUPID) {
    uint sharedAddr = gid.x + gid.y*ASCIIWidth;
    uint3 inputIdx = uint3(id.xy * uint2(ASCIIWidth, ASCIIHeight) + gid.xy, id.z);

    // It would be slightly faster to perform one more set of additions here, but
    // that seems not worth it
    DownscaleBuffer[sharedAddr] = 0.5 * (
        tex3Dfetch(samplerDownscaleInput, inputIdx).r
        + tex3Dfetch(samplerDownscaleInput, inputIdx + uint3(0,4,0)).r
    );
    // uint firstVal = (uint)(tex3Dfetch(samplerDownscaleInput, inputIdx).r * 128);
    // uint secondVal= (uint)(tex3Dfetch(samplerDownscaleInput, inputIdx + uint3(0,4,0)).r * 128);
    // uint start = (firstVal + secondVal)>>1;
    // DownscaleBuffer[sharedAddr] = start;

    // parallel reduction, with CUDA we could warp sync but here a barrier
    // is required. (Effectively identical performance to the quantized atomicAdd version)
    [unroll]
	for ( int i=sharedBufferSize/2 ; i>0 ; i>>=1) {
		groupMemoryBarrier();
		DownscaleBuffer[sharedAddr] += DownscaleBuffer[sharedAddr + i];
		DownscaleBuffer[sharedAddr] = 0.5*DownscaleBuffer[sharedAddr];
        // DownscaleBuffer[sharedAddr] = atomicAdd(DownscaleBuffer[sharedAddr], DownscaleBuffer[sharedAddr + i])>>1;
	}

    if (sharedAddr == 0) {
        tex3Dstore(s_Downscaled, id, DownscaleBuffer[0]);
    }
}

groupshared float Closeness[PatchSizeBestASCII*PatchSizeBestASCII*ASCIIAlternatives/2];
groupshared uint IClosest[PatchSizeBestASCII*PatchSizeBestASCII*ASCIIAlternatives/2];
[numthreads(PatchSizeBestASCII,PatchSizeBestASCII,ASCIIAlternatives/2)]
void ComputeBestASCII(uint3 tid : SV_DISPATCHTHREADID, uint3 gid : SV_GROUPTHREADID) {

    float prevCloseness = tex3Dfetch(samplerDownscaled, uint3(tid.xy,tid.z)).r;
    float nextCloseness = tex3Dfetch(samplerDownscaled, uint3(tid.xy,tid.z+ASCIIAlternatives/2)).r;
    int result = nextCloseness < prevCloseness;
    uint sharedAddr = gid.x*ASCIIAlternatives/2*PatchSizeBestASCII + gid.y*ASCIIAlternatives/2 + gid.z;
    Closeness[sharedAddr] = prevCloseness*(1-result) + nextCloseness*result;
    IClosest[sharedAddr] = result*ASCIIAlternatives/2 + gid.z;
    [unroll]
    for (uint i = ASCIIAlternatives/4; i > 0; i>>=1 ) {
		groupMemoryBarrier();
        int isCloser = Closeness[sharedAddr + i] < Closeness[sharedAddr];
        // int isCloser = true;
        Closeness[sharedAddr] = Closeness[sharedAddr]*(1-isCloser) + Closeness[sharedAddr + i]*isCloser;
        IClosest[sharedAddr] = IClosest[sharedAddr]*(1-isCloser) + IClosest[sharedAddr + i]*isCloser;
        // uint3 newInd = uint3(tid.xy, i);
        // float newCloseness = tex3Dfetch(samplerDownscaled, newInd).r;
        // if (newCloseness < prevCloseness) {
        //     prevCloseness = newCloseness;
        //     result = i;
        // }
    }
	uint charIdx = IClosest[sharedAddr] + (uint)tex2Dfetch(samplerDownscaledLumi, tid.xy);
    if ( gid.z==0 ) {
        tex2Dstore(s_BestASCII, tid.xy, (float)charIdx);
    }
}

void ComputeASCIIRender(uint3 id : SV_GROUPID, uint3 gid : SV_GROUPTHREADID) {

    uint character = tex2Dfetch(samplerBestASCII, id.xy).r;
    uint2 localUV = uint2(character * ASCIIWidth,0) + gid.xy;
    float3 ascii = tex2Dfetch(PixelsASCII, localUV).r;
    tex2Dstore(s_Final, id.xy*ASCIIWidth + gid.xy, float4(ascii,1.0));
}

float4 PixelRender(float4 position : SV_POSITION, float2 uv : TEXCOORD) : SV_TARGET {
	float3 ascii = tex2D(samplerFinal, uv).rgb;
    float3 foreground = lerp(_ASCIIColor, tex2D(samplerColor, uv).rgb, _BlendWithBase);
    ascii = lerp(_BackgroundColor, foreground, ascii);
    return float4(ascii, 1.0);
}


technique ASCII_FECT < ui_label= "Fine ASCII"; ui_tooltip = "Replace image with text, without explicit quality loss."; > {

    // Grayscale conversion
    pass {
        RenderTarget = texLumi;
        VertexShader = FullWindow;
        PixelShader = PixelLuminance;
    }

	pass {
		ComputeShader = ComputeDownscaleLumi;
        DispatchSizeX = BUFFER_WIDTH / ASCIIWidth;
        DispatchSizeY = BUFFER_HEIGHT / ASCIIHeight;
    }

    // Character matching
    pass {
        ComputeShader = ComputeASCIICloseness<ASCIIWidth,ASCIIHeight,1>;
        DispatchSizeX = BUFFER_WIDTH / ASCIIWidth;
        DispatchSizeY = BUFFER_HEIGHT / ASCIIHeight;
        DispatchSizeZ = ASCIIAlternatives;
    }

    // Downscale all of the pixel closeness textures
    pass {
        ComputeShader = ComputeDownscaleWxHxN;
        DispatchSizeX = BUFFER_WIDTH / ASCIIWidth;
        DispatchSizeY = BUFFER_HEIGHT / ASCIIHeight;
        DispatchSizeZ = ASCIIAlternatives;
    }

    // scan for the best match inside each character
    pass {
        ComputeShader = ComputeBestASCII;
        DispatchSizeX = BUFFER_WIDTH / (ASCIIWidth*PatchSizeBestASCII);
        DispatchSizeY = BUFFER_HEIGHT / (ASCIIHeight*PatchSizeBestASCII);
    }

    // rendering results
    pass {
        ComputeShader = ComputeASCIIRender<ASCIIWidth,ASCIIHeight>;
        DispatchSizeX = BUFFER_WIDTH / ASCIIWidth;
        DispatchSizeY = BUFFER_HEIGHT / ASCIIHeight;
    }
    pass {
        VertexShader = FullWindow;
        PixelShader = PixelRender;
    }
}

