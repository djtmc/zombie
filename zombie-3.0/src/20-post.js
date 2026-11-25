// Postprocesing "makiety": render w obniżonej rozdzielczości, tilt-shift, poświata,
// winieta, ziarno i dithering. Kolory sceny są liniowe (HDR), konwersja sRGB tutaj.
const POST = { rt: null, scene: null, cam: null, mat: null, scale: 0.6 };

const POST_FRAG = `
precision highp float;
varying vec2 vUv;
uniform sampler2D tColor;
uniform vec2 uRes;
uniform float uTime, uFocus, uBand, uBlur, uExposure, uVig, uGlow, uLevels;
uniform vec3 uLift, uTint;
float bayer2(vec2 a){ a = floor(a); return fract(a.x / 2.0 + a.y * a.y * 0.75); }
float bayer4(vec2 a){ return bayer2(0.5 * a) * 0.25 + bayer2(a); }
float bayer8(vec2 a){ return bayer4(0.5 * a) * 0.25 + bayer2(a); }
vec3 aces(vec3 x){ return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0); }
float hash(vec2 p){ return fract(sin(dot(p, vec2(12.9898, 78.233)) + uTime * 3.1) * 43758.5453); }
void main(){
  vec3 c = texture2D(tColor, vUv).rgb;
  // tilt-shift: ostry pas w środku ekranu, rozmycie rośnie ku górze i dołowi
  float d = abs(vUv.y - uFocus);
  float b = smoothstep(uBand, uBand + 0.32, d) * uBlur;
  if (b > 0.05) {
    vec3 acc = c; float w = 1.0;
    for (int i = 0; i < 12; i++) {
      float fi = float(i);
      float a = fi * 2.39996;
      float r = sqrt((fi + 0.5) / 12.0) * b;
      acc += texture2D(tColor, vUv + vec2(cos(a), sin(a)) * r / uRes).rgb; w += 1.0;
    }
    c = acc / w;
  }
  // poświata jasnych punktów (ogień, błyski, wyładowania)
  vec3 g = vec3(0.0);
  for (int i = 0; i < 8; i++) {
    float a = float(i) * 0.785398 + 0.3;
    vec3 s1 = texture2D(tColor, vUv + vec2(cos(a), sin(a)) * 3.0 / uRes).rgb;
    vec3 s2 = texture2D(tColor, vUv + vec2(cos(a), sin(a)) * 7.0 / uRes).rgb;
    g += max(s1 - 0.85, 0.0) + 0.6 * max(s2 - 0.85, 0.0);
  }
  c += g * uGlow;
  c = aces(c * uExposure);
  c = c * uTint + uLift;
  vec2 p = vUv - 0.5;
  c *= 1.0 - uVig * dot(p * vec2(1.1, 1.25), p * vec2(1.1, 1.25)) * 2.2;
  c = pow(max(c, 0.0), vec3(1.0 / 2.2));
  c += (hash(gl_FragCoord.xy) - 0.5) * 0.035;
  float t = bayer8(gl_FragCoord.xy) - 0.5;
  c = floor(c * uLevels + 0.5 + t) / uLevels;
  gl_FragColor = vec4(c, 1.0);
}`;

function initPost() {
  POST.rt = new THREE.WebGLRenderTarget(4, 4, { type: THREE.HalfFloatType, samples: 0, depthBuffer: true });
  POST.rt.texture.minFilter = THREE.LinearFilter;
  POST.rt.texture.magFilter = THREE.LinearFilter;
  POST.mat = new THREE.ShaderMaterial({
    vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }',
    fragmentShader: POST_FRAG,
    uniforms: {
      tColor: { value: POST.rt.texture }, uRes: { value: new THREE.Vector2(4, 4) }, uTime: { value: 0 },
      uFocus: { value: 0.47 }, uBand: { value: 0.1 }, uBlur: { value: 3.2 }, uExposure: { value: 1.0 },
      uVig: { value: 0.55 }, uGlow: { value: 0.16 }, uLevels: { value: 40 },
      uLift: { value: new THREE.Vector3(0.01, 0.008, 0.012) }, uTint: { value: new THREE.Vector3(1, 1, 1) }
    },
    depthTest: false, depthWrite: false, toneMapped: false
  });
  POST.scene = new THREE.Scene();
  POST.cam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
  const quad = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), POST.mat);
  quad.frustumCulled = false;
  POST.scene.add(quad);
}

function resizeGfx() {
  const w = innerWidth, h = innerHeight, dpr = Math.min(devicePixelRatio || 1, 2);
  G.W = w; G.H = h;
  G.renderer.setSize(w, h, false);
  G.renderer.domElement.style.width = w + 'px';
  G.renderer.domElement.style.height = h + 'px';
  G.renderer.setPixelRatio(dpr);
  // mniejsza rozdzielczość wewnętrzna = wygląd makiety i lepsza wydajność na telefonach
  let s = POST.scale * dpr;
  const maxW = 1400;
  if (w * s > maxW) s = maxW / w;
  const rw = Math.max(2, Math.round(w * s)), rh = Math.max(2, Math.round(h * s));
  POST.rt.setSize(rw, rh);
  POST.mat.uniforms.uRes.value.set(rw, rh);
  G.camera.aspect = w / h;
  G.camera.updateProjectionMatrix();
}

function renderFrame(time) {
  POST.mat.uniforms.uTime.value = time % 100;
  G.renderer.setRenderTarget(POST.rt);
  G.renderer.render(G.scene, G.camera);
  G.renderer.setRenderTarget(null);
  G.renderer.render(POST.scene, POST.cam);
}
