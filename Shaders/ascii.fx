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
static const uint sharedBufferSize = ASCIIWidth * (ASCIIHeight / 2);

// Modifiable, but requires recompilation
// Not intended to be increased over 16 without additional considerations
static const uint ASCIIAlternatives = 16;

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

texture3D texDownscaleInput { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Depth = 16; Format = R16F; };
sampler3D samplerDownscaleInput { Texture = texDownscaleInput; AddressU = BORDER; AddressV = BORDER; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT;};
storage3D s_DownscaleInput { Texture = texDownscaleInput; };

texture3D texDownscaled { Width = BUFFER_WIDTH / 8; Height = BUFFER_HEIGHT / 8; Depth = 16; Format = R16F; };
sampler3D samplerDownscaled { Texture = texDownscaled; AddressU = BORDER; AddressV = BORDER; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT;};
storage3D s_Downscaled { Texture = texDownscaled; };

texture2D texDownscaledLumi { Width = BUFFER_WIDTH / 8; Height = BUFFER_HEIGHT / 8; Format = R16F; };
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
	for ( int i=log2(sharedBufferSize)-1 ; i>=0 ; i-- ) {
		barrier();
		uint offset = pow(2,i);
		reductionBuffer[sharedAddr] += reductionBuffer[sharedAddr + offset];
	}

    if (sharedAddr == 0) {
        tex2Dstore(s_DownscaledLumi, id.xy, 0.5 + reductionBuffer[0] * (ASCIICharacters - ASCIIAlternatives)/ASCIICharacters);
    }
}

void ComputeASCIICloseness(uint3 tid : SV_DISPATCHTHREADID, uint3 gid : SV_GROUPTHREADID, uint3 id : SV_GROUPID) {

	// group thread id is the position inside the 8x8 ascii character
    uint2 ij = gid.xy;

    //uint iLumi = (uint)tex2Dfetch(samplerILumi, id.xy).r;
	uint iLumi = (uint)tex2Dfetch(samplerDownscaledLumi, id.xy);

    uint comp = id.z + iLumi;
    uint2 posASCII = uint2(comp * ASCIIWidth + gid.x, gid.y);
    float lumiASCII = tex2Dfetch(PixelsASCII, posASCII).r;
    float pixelDistance = abs(lumiASCII - tex2Dfetch(samplerLumi, tid.xy).r);
    pixelDistance = pow(pixelDistance, _Metric);
    tex3Dstore(s_DownscaleInput, uint3(tid.xy, id.z), pixelDistance);
}

[numthreads(ASCIIWidth, ASCIIHeight / 2, 1)]
void ComputeDownscaleWxHxN(uint3 gid : SV_GROUPTHREADID, uint3 id : SV_GROUPID) {
    uint sharedAddr = gid.x + gid.y*ASCIIWidth;
    uint3 inputIdx = uint3(id.xy * uint2(ASCIIWidth, ASCIIHeight) + gid.xy, id.z);
    reductionBuffer[sharedAddr] = 0.5 * (
        tex3Dfetch(samplerDownscaleInput, inputIdx).r
        + tex3Dfetch(samplerDownscaleInput, inputIdx + uint3(0,4,0)).r
    );

    // parallel reduction
	for ( int i=log2(sharedBufferSize)-1 ; i>=0 ; i-- ) {
		barrier();
		uint offset = pow(2,i);
		reductionBuffer[sharedAddr] += reductionBuffer[sharedAddr + offset];
		reductionBuffer[sharedAddr] = 0.5*reductionBuffer[sharedAddr];
	}

    if (sharedAddr == 0) {
        tex3Dstore(s_Downscaled, id, reductionBuffer[0]);
    }
}

void ComputeBestASCII(uint3 tid : SV_DISPATCHTHREADID) {

    uint result = 0;
    float prevCloseness = tex3Dfetch(samplerDownscaled, uint3(tid.xy,0)).r;
    for (uint i = 1; i < ASCIIAlternatives; i+=1 ) {
        uint3 newInd = uint3(tid.xy, i);
        float newCloseness = tex3Dfetch(samplerDownscaled, newInd).r;
        if (newCloseness < prevCloseness) {
            prevCloseness = newCloseness;
            result = i;
        }
    }
	uint charIdx = result + (uint)tex2Dfetch(samplerDownscaledLumi, tid.xy);
    tex2Dstore(s_BestASCII, tid.xy, (float)charIdx);
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
        ComputeShader = ComputeASCIICloseness<ASCIIWidth,ASCIIHeight>;
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
        ComputeShader = ComputeBestASCII<ASCIIWidth,ASCIIHeight>;
        DispatchSizeX = BUFFER_WIDTH / ASCIIWidth*ASCIIWidth;
        DispatchSizeY = BUFFER_HEIGHT / ASCIIHeight*ASCIIHeight;
    }

    // render
    pass {
        ComputeShader = ComputeASCIIRender<ASCIIWidth,ASCIIHeight>;
        DispatchSizeX = BUFFER_WIDTH / ASCIIWidth;
        DispatchSizeY = BUFFER_HEIGHT / ASCIIHeight;
    }
    // pass {
    //     ComputeShader = ComputeGrayscale<8,8>;
    //     DispatchSizeX = BUFFER_WIDTH / 8;
    //     DispatchSizeY = BUFFER_HEIGHT / 8;
    // }
    pass {
        VertexShader = FullWindow;
        PixelShader = PixelRender;
    }
}

