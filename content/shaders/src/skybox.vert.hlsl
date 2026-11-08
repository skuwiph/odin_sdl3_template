#include "common.hlsl"

struct Input
{
    uint vertexId: SV_VertexID;
};

struct Output
{
    float4 clipPosition : SV_Position;
    float3 texCoords : TEXCOORD0;
};

Output main(Input input)
{
    // float2 vertices[] = {
    //     float2(-1, -1),
    //     float2( 3, -1),
    //     float2(-1,  3),
    // };

    // float2 vertexPosition = vertices[input.vertexId];
    float2 vertexPosition = float2(
        -1 + float((input.vertexId & 1) << 2),
        -1 + float((input.vertexId & 2) << 1)
    );

    float4 clipSpacePosition = float4(vertexPosition, 1, 1);

    float4 viewSpacePosition = mul(invProjectionMat, clipSpacePosition);

    float4 viewDir = mul(invViewMat, float4(viewSpacePosition.xyz, 0));

    Output result;
    result.clipPosition = clipSpacePosition;
    result.texCoords = viewDir;
    return result;
}