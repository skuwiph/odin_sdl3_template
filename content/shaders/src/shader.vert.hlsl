cbuffer Global : register(b0, space1)
{
    float4x4 viewProjectionMat;
}

cbuffer Local : register(b1, space1)
{
    float4x4 modelMat;
    float4x4 normalMat;
}

struct Input
{
    float3 position : TEXCOORD0;
    float2 uv : TEXCOORD1;
    float3 normal : TEXCOORD2;
    float4 color : TEXCOORD3;
};

struct Output
{
    float2 uv : TEXCOORD0;
    float3 position : TEXCOORD1;
    float3 normal : TEXCOORD2;
    float4 color : TEXCOORD3;
    float4 clipPosition : SV_Position;
};

Output main(Input input)
{
    float4 worldPosition = mul(modelMat, float4(input.position, 1));

    Output result;
    result.clipPosition = mul(viewProjectionMat, worldPosition);
    result.color = input.color;
    result.uv = input.uv;
    result.position = worldPosition.xyz;
    result.normal = normalize(mul(normalMat, float4(input.normal, 0)).xyz);

    return result;
}