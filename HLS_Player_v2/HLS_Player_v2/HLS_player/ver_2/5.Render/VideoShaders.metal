#include <metal_stdlib>
using namespace metal;

struct VertexIn {
	float3 position [[attribute(0)]];
	float2 texCoord [[attribute(1)]];
};

struct VertexOut {
	float4 position [[position]];
	float2 texCoord;
};

vertex VertexOut vertexShader(uint vertexID [[vertex_id]],
							  constant float3 *positions [[buffer(0)]],
							  constant float2 *texCoords [[buffer(1)]]) {
	VertexOut out;
	out.position = float4(positions[vertexID], 1.0);
	out.texCoord = texCoords[vertexID];
	return out;
}

fragment float4 fragmentShader(VertexOut in [[stage_in]],
							   texture2d<float> yTexture [[texture(0)]],
							   texture2d<float> cbcrTexture [[texture(1)]]) {
	constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
	
	float3 ycbcr = float3(
		yTexture.sample(textureSampler, in.texCoord).r,
		cbcrTexture.sample(textureSampler, in.texCoord).rg - float2(0.5, 0.5)
	);
	
	// BT.601 full range conversion
	const float3x3 ycbcrToRGBTransform = float3x3(
		float3(1.0, 0.0, 1.402),
		float3(1.0, -0.344136, -0.714136),
		float3(1.0, 1.772, 0.0)
	);
	
	float3 rgb = ycbcrToRGBTransform * ycbcr;
	
	return float4(rgb, 1.0);
}
