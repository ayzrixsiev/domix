#include <flutter/runtime_effect.glsl>

// The rim of a sheet of glass. Runs as the outer half of a BackdropFilter whose inner half already
// blurred the page, so what arrives here is the frosted backdrop and all this adds is the bend a
// real edge puts into what you see through it.
//
// **Everything is passed as a fraction of the backdrop, never in pixels.** Impeller binds the whole
// render pass as the input texture, and its size is in physical pixels - a phone at 3x and the
// desktop at 1x would need different numbers. Normalised, the device ratio cancels out.

// **The first uniform must be a vec2 and Impeller fills it itself** with the bound texture's size -
// see ImageFilter.shader. Nothing in Dart sets it.
uniform vec2 uSize;

// the panel, as x0 y0 x1 y1 fractions of the backdrop
uniform vec4 uRect;

// corner radius and how deep the bend reaches in from the edge, as fractions of the backdrop height
uniform vec2 uShape;

// how far the rim pushes what is behind it, same fraction again
uniform float uStrength;

uniform sampler2D uBackdrop;

out vec4 fragColor;

// signed distance to a rounded rectangle: negative inside it, zero on the edge
float roundedBox(vec2 p, vec2 extent, float radius) {
  vec2 q = abs(p) - extent + radius;
  return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - radius;
}

vec2 toUv(vec2 pixel) {
  vec2 uv = pixel / uSize;
  // **Impeller's GLES backend hands the texture over upside down**, and nothing says so on screen
  // until a device without Vulkan draws the bar's reflection at the wrong end.
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return clamp(uv, 0.0, 1.0);
}

void main() {
  vec2 p = FlutterFragCoord().xy;

  vec2 low = uRect.xy * uSize;
  vec2 high = uRect.zw * uSize;
  vec2 centre = (low + high) * 0.5;
  vec2 extent = (high - low) * 0.5;

  float radius = uShape.x * uSize.y;
  float depth = uShape.y * uSize.y;

  float d = roundedBox(p - centre, extent, radius);

  vec2 offset = vec2(0.0);
  // only the band just inside the edge bends. the guard is also what keeps the normal below away
  // from the middle of the panel, where the distance field is flat and normalize() returns NaN.
  if (d < 0.0 && -d < depth) {
    float h = 1.0;
    vec2 normal = normalize(vec2(
      roundedBox(p - centre + vec2(h, 0.0), extent, radius) -
          roundedBox(p - centre - vec2(h, 0.0), extent, radius),
      roundedBox(p - centre + vec2(0.0, h), extent, radius) -
          roundedBox(p - centre - vec2(0.0, h), extent, radius)
    ));
    // squared, so the middle of the panel is untouched and the whole bend lives in the last few
    // pixels - that concentration is what reads as thickness rather than as a smear
    float rim = 1.0 - clamp(-d / depth, 0.0, 1.0);
    offset = normal * rim * rim * uStrength * uSize.y;
  }

  // the three channels bend by slightly different amounts, which is the whole difference between
  // "blurred" and "glass" - real glass splits the light at its edge
  vec4 mid = texture(uBackdrop, toUv(p + offset));
  fragColor = vec4(
    texture(uBackdrop, toUv(p + offset * 1.10)).r,
    mid.g,
    texture(uBackdrop, toUv(p + offset * 0.90)).b,
    mid.a
  );
}
