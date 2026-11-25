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
#ifdef MIST
// mgła przy ziemi oświetlona światłami punktowymi + cieniowanie zakamarków (SSAO) z bufora głębi
uniform sampler2D tDepth; uniform mat4 uInvVP; uniform vec3 uCamDir;
uniform vec3 uLP[8]; uniform vec3 uLC[8];
uniform vec4 uMist; uniform vec3 uMistCol; uniform vec2 uWind; uniform float uAO;
vec3 wpos(vec2 uv, float dd){ vec4 q = uInvVP * vec4(uv * 2.0 - 1.0, dd * 2.0 - 1.0, 1.0); return q.xyz / q.w; }
float h12(vec2 q){ vec3 p3 = fract(vec3(q.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
float vn(vec2 q){ vec2 i = floor(q), f = fract(q); f = f * f * (3.0 - 2.0 * f);
  return mix(mix(h12(i), h12(i + vec2(1, 0)), f.x), mix(h12(i + vec2(0, 1)), h12(i + vec2(1, 1)), f.x), f.y); }
vec3 atmo(vec3 c){
  float dd = texture2D(tDepth, vUv).x;
  if (dd > 0.9999) return c;
  vec2 px = 1.0 / uRes;
  vec3 P = wpos(vUv, dd);
  vec3 ddx = wpos(vUv + vec2(px.x, 0.0), texture2D(tDepth, vUv + vec2(px.x, 0.0)).x) - P;
  vec3 ddy = wpos(vUv + vec2(0.0, px.y), texture2D(tDepth, vUv + vec2(0.0, px.y)).x) - P;
  vec3 N = normalize(cross(ddx, ddy)); if (dot(N, uCamDir) > 0.0) N = -N;
  float occ = 0.0, ang = bayer4(gl_FragCoord.xy) * 6.2831853;
  for (int i = 0; i < 8; i++) {
    float fi = (float(i) + 0.5) / 8.0, a = ang + float(i) * 2.39996;
    vec2 suv = vUv + vec2(cos(a), sin(a)) * 14.0 * sqrt(fi) * px;
    vec3 V = wpos(suv, texture2D(tDepth, suv).x) - P;
    float vv = dot(V, V);
    occ += max(0.0, dot(V, N) - 0.02) / (vv + 0.03) * step(vv, 0.6);
  }
  c *= clamp(1.0 - occ * uAO * 0.11, 0.0, 1.0);
  float n = vn(P.xz * 0.35 + uWind) * 0.65 + vn(P.xz * 0.9 - uWind * 1.7) * 0.35;
  float tau = min(uMist.z * exp(-(max(P.y, -1.0) - uMist.x) / uMist.y), 1.25) * smoothstep(0.3, 0.85, n);
  float f = 1.0 - exp(-tau);
  vec3 L = uMistCol; vec3 Pm = P + vec3(0.0, 0.35, 0.0);
  for (int i = 0; i < 8; i++) { vec3 dv = uLP[i] - Pm; L += uLC[i] / (dot(dv, dv) + 1.5); }
  return mix(c, L * uMist.w, f);
}
#endif
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
  if (uGlow > 0.0) for (int i = 0; i < 8; i++) {
    float a = float(i) * 0.785398 + 0.3;
    vec3 s1 = texture2D(tColor, vUv + vec2(cos(a), sin(a)) * 3.0 / uRes).rgb;
    vec3 s2 = texture2D(tColor, vUv + vec2(cos(a), sin(a)) * 7.0 / uRes).rgb;
    g += max(s1 - 0.85, 0.0) + 0.6 * max(s2 - 0.85, 0.0);
  }
  c += g * uGlow;
#ifdef MIST
  c = atmo(c);
#endif
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
  POST.rt.depthTexture = new THREE.DepthTexture(4, 4);
  POST.rt.depthTexture.type = THREE.UnsignedIntType;
  POST.rt.texture.minFilter = THREE.LinearFilter;
  POST.rt.texture.magFilter = THREE.LinearFilter;
  POST.mat = new THREE.ShaderMaterial({
    vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }',
    fragmentShader: POST_FRAG,
    uniforms: {
      tColor: { value: POST.rt.texture }, uRes: { value: new THREE.Vector2(4, 4) }, uTime: { value: 0 },
      uFocus: { value: 0.47 }, uBand: { value: 0.1 }, uBlur: { value: 3.2 }, uExposure: { value: 1.0 },
      uVig: { value: 0.55 }, uGlow: { value: 0.16 }, uLevels: { value: 40 },
      tDepth: { value: POST.rt.depthTexture }, uInvVP: { value: new THREE.Matrix4() }, uCamDir: { value: new THREE.Vector3() },
      uLP: { value: Array.from({ length: 8 }, () => new THREE.Vector3(0, -99, 0)) }, uLC: { value: Array.from({ length: 8 }, () => new THREE.Vector3()) },
      uMist: { value: new THREE.Vector4(0, 0.35, 0.5, 1) }, uMistCol: { value: new THREE.Vector3(0.05, 0.05, 0.06) }, uWind: { value: new THREE.Vector2() }, uAO: { value: 1 },
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
  G.renderer.setPixelRatio(Math.min(dpr, QUALITY.lv().dpr));
  // mniejsza rozdzielczość wewnętrzna = wygląd makiety i lepsza wydajność (liczona w pikselach CSS)
  // rozdzielczość wewnętrzna: skala poziomu x adaptacja, z limitem liczby pikseli
  const q = QUALITY.lv();
  let s = q.scale * QUALITY.res;
  if (w * h * s * s > q.maxPix) s = Math.sqrt(q.maxPix / (w * h));
  s = Math.max(s, 160 / Math.min(w, h));
  const rw = Math.max(2, Math.round(w * s)), rh = Math.max(2, Math.round(h * s));
  POST.rt.setSize(rw, rh);
  POST.mat.uniforms.uRes.value.set(rw, rh);
  G.camera.aspect = w / h;
  G.camera.updateProjectionMatrix();
}

function renderFrame(time) {
  POST.mat.uniforms.uTime.value = time % 100;
  QUALITY.frame++;
  const q = QUALITY.lv();
  if (q.shadow && QUALITY.frame % q.shadowEvery === 0) G.renderer.shadowMap.needsUpdate = true;
  if (POST.mat.defines && POST.mat.defines.MIST !== undefined) {
    const u = POST.mat.uniforms;
    u.uInvVP.value.multiplyMatrices(G.camera.projectionMatrix, G.camera.matrixWorldInverse).invert();
    G.camera.getWorldDirection(u.uCamDir.value);
    u.uWind.value.set(time * 0.08, time * 0.03);
    G.lights.forEach((s, i) => {
      const on = s.on && s.l.intensity > 0;
      u.uLP.value[i].copy(on ? s.l.position : new THREE.Vector3(0, -99, 0));
      if (on) u.uLC.value[i].set(s.l.color.r, s.l.color.g, s.l.color.b).multiplyScalar(s.l.intensity * 0.12); else u.uLC.value[i].set(0, 0, 0);
    });
  }
  G.renderer.setRenderTarget(POST.rt);
  G.renderer.render(G.scene, G.camera);
  G.renderer.setRenderTarget(null);
  G.renderer.render(POST.scene, POST.cam);
}
