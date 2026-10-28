
struct Input {
    float4 color    : TEXTCOORD0;
    float2 uv       : TEXTCOORD1;
};

Texture2D<float4> tex : register(t0, space2);
SamplerState smp : register(s0, space2);

float4 main(Input input): SV_Target0 {
    float4 color = tex.Sample(smp, input.uv);

    // Here, the colors are linear

    float4 finalColor = color * input.color;
    // finalColor.rgb = pow(finalColor.rgb, 1 / 2.2);

    return finalColor;
}