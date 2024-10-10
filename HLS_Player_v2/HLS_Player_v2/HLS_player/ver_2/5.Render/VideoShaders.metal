#include <metal_stdlib>
using namespace metal;

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
							   texture2d<float> uTexture [[texture(1)]],
							   texture2d<float> vTexture [[texture(2)]]) {
	constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
	
	float y = yTexture.sample(textureSampler, in.texCoord).r;
	float u = uTexture.sample(textureSampler, in.texCoord).r - 0.5;
	float v = vTexture.sample(textureSampler, in.texCoord).r - 0.5;
	
	// YUV to RGB conversion (BT.601 standard)
	float3 rgb;
	rgb.r = y + 1.402 * v;
	rgb.g = y - 0.344 * u - 0.714 * v;
	rgb.b = y + 1.772 * u;
	
	// Ensure values are in the correct range
	rgb = saturate(rgb);
	
	return float4(rgb, 1.0);
}
