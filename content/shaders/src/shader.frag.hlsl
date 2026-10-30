cbuffer Global : register(b0, space3) {
    float3 lightPosition;
    float3 lightColor;
    float lightIntensity;
    float3 viewPosition;
    float3 ambientLightColor;
}

cbuffer Local : register(b1, space3) {
    float3 materialSpecularColor;
    float materialShininess;
}
struct Input
{
    float4 clipPosition : SV_Position;
    float2 uv : TEXCOORD0;
    float3 position : TEXCOORD1;
    float3 normal : TEXCOORD2;
    float4 color : TEXCOORD3;
};

Texture2D<float4> diffuseMap : register(t0, space2);
SamplerState smp : register(s0, space2);

float3 blinnPhongBRDF(float3 dirToLight, float3 dirToView, float3 surfaceNormal, float3 materialDiffuseReflection)
{
    // Absorption/reflection by channel
    float3 halfWayDir = normalize(dirToLight + dirToView);
    float specularDot = max(0, dot(halfWayDir, surfaceNormal));
    float specularFactor = pow(specularDot, materialShininess);

    float3 specularReflection = materialSpecularColor * specularFactor;

    // TODO energy conservation/normalization
    return materialDiffuseReflection + specularReflection;
}

float4 main(Input input) : SV_Target0
{
    float3 vecToLight = lightPosition - input.position.xyz;
    float distToLight = length(vecToLight);
    float3 dirToLight = vecToLight / distToLight;

    float3 dirToView = normalize(viewPosition - input.position);

    float3 surfaceNormal = normalize(input.normal.xyz);
    float3 materialDiffuseReflection = diffuseMap.Sample(smp, input.uv).rgb;

    float3 ambientIrradiance = ambientLightColor;
    float3 reflectedRadiance = ambientIrradiance * materialDiffuseReflection;

    float incidenceAngleFactor = dot(dirToLight, surfaceNormal);
    if (incidenceAngleFactor > 0)
    {
        float attenuationFactor = 1 / (distToLight * distToLight);
        float3 incomingRadiance = lightColor * lightIntensity;
        float3 irradiance = incomingRadiance * incidenceAngleFactor * attenuationFactor;
        float3 brdf = blinnPhongBRDF(dirToLight, dirToView, surfaceNormal, materialDiffuseReflection);
        reflectedRadiance += irradiance * brdf;
    }

    float3 emittedRadiance = float3(0, 0, 0);
    float3 outRadiance = emittedRadiance + reflectedRadiance;

    return float4(outRadiance, 1);
}