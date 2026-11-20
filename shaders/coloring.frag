#include <flutter/runtime_effect.glsl>

precision highp float;

// Fill shader for the coloring screen (spec §3).
//
// Float uniforms, in this order (set by `ShaderFillRenderer.paint` in
// lib/features/coloring/game/fill_renderer.dart):
//   0-1   uSize             destination rect size, px
//   2-3   uOrigin           image->screen: screen = origin + image * scale
//   4     uScale
//   5-6   uImageSize        regions image size, px (2048, 1536)
//   7     uStateWidth       state texture width = N + 1
//   8     uWaveId           region of the running wave, 0 = none
//   9-10  uWaveCenter       wave center, image px
//   11    uWaveRadius       wave radius, image px
//   12-15 uWaveOld          color outside the wave (RGBA 0..1)
//   16-19 uWaveNew          color inside the wave (RGBA 0..1)
//   20    uHighlightPalette palette index to stripe, -1 = none
//   21    uPulse            highlight pulse 0..1
//   22    uFlashId          region of the reject flash, 0 = none
//   23    uFlashAmount      flash strength 0..1
// Samplers: 0 uRegions (id = R * 256 + G, 0 = line), 1 uState (opaque
// (N + 1) x 2: row 0 display RGB, white when unfilled; row 1 R = palette
// index, G = 255 when the region holds its correct color).
//
// The highlighted number's unfinished regions get gray diagonal stripes in
// canvas space (constant width at any zoom), so they stand out against any
// color already on the picture.

uniform vec2 uSize;
uniform vec2 uOrigin;
uniform float uScale;
uniform vec2 uImageSize;
uniform float uStateWidth;
uniform float uWaveId;
uniform vec2 uWaveCenter;
uniform float uWaveRadius;
uniform vec4 uWaveOld;
uniform vec4 uWaveNew;
uniform float uHighlightPalette;
uniform float uPulse;
uniform float uFlashId;
uniform float uFlashAmount;

uniform sampler2D uRegions;
uniform sampler2D uState;

out vec4 fragColor;

const vec3 kPaper = vec3(1.0, 1.0, 1.0);
const vec3 kStripe = vec3(0.55, 0.55, 0.58);
// Stripe period along x + y and stripe width (40 %), canvas px; soft edge.
const float kStripePeriod = 10.0;
const float kStripeHalfWidth = 2.0;
const float kStripeEdge = 0.75;
const vec3 kFlash = vec3(0.78, 0.84, 0.92);

vec4 sampleState(float x, float row) {
  vec2 uv = vec2(x, row);
#if defined(IMPELLER_TARGET_OPENGLES) && !defined(IMPELLER_OPENGLES_UNFLIPPED_DEPRECATED)
  // Flutter <= 3.44 needed a y flip when sampling a texture on OpenGLES.
  // Since 3.45 the engine flips at the vertex stage instead and defines
  // IMPELLER_OPENGLES_UNFLIPPED_DEPRECATED for GLES targets, so this branch
  // is compiled out there (upstream pattern, flutter/flutter#187316).
  uv.y = 1.0 - uv.y;
#endif
  return texture(uState, uv);
}

void main() {
  vec2 local = FlutterFragCoord().xy - uOrigin;
  vec2 p = local / uScale;
  if (local.x < 0.0 || local.y < 0.0 || local.x >= uSize.x ||
      local.y >= uSize.y || p.x >= uImageSize.x || p.y >= uImageSize.y) {
    fragColor = vec4(0.0);
    return;
  }

  // Texel center, so filtering can never mix two ids.
  vec2 texel = floor(p) + 0.5;
  vec2 rg = texture(uRegions, texel / uImageSize).rg;
  float id = floor(rg.r * 255.0 + 0.5) * 256.0 + floor(rg.g * 255.0 + 0.5);
  if (id < 0.5) {
    fragColor = vec4(kPaper, 1.0);
    return;
  }

  float x = (id + 0.5) / uStateWidth;
  vec3 c = sampleState(x, 0.25).rgb;
  vec4 meta = sampleState(x, 0.75);
  float paletteIndex = floor(meta.r * 255.0 + 0.5);
  bool correct = meta.g > 0.5;

  if (abs(id - uWaveId) < 0.5) {
    float d = distance(p, uWaveCenter);
    // Soft 2 px edge; a huge radius (reduced motion) fills the whole region.
    float inside = clamp((uWaveRadius - d) * 0.5, 0.0, 1.0);
    c = mix(uWaveOld.rgb, uWaveNew.rgb, inside);
  }

  if (uHighlightPalette > -0.5 && abs(paletteIndex - uHighlightPalette) < 0.5 &&
      !correct) {
    vec2 frag = FlutterFragCoord().xy;
    // Distance from the stripe center, 0..period / 2.
    float d = abs(mod(frag.x + frag.y, kStripePeriod) - kStripePeriod * 0.5);
    float stripe = clamp((kStripeHalfWidth - d) / kStripeEdge + 0.5, 0.0, 1.0);
    c = mix(c, kStripe, stripe * (0.45 + 0.25 * uPulse));
  }

  if (abs(id - uFlashId) < 0.5) {
    c = mix(c, kFlash, uFlashAmount);
  }

  fragColor = vec4(c, 1.0);
}
