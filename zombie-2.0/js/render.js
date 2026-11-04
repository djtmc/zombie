// =====================================================================
//  RENDERER: scena, kamera, światła, niebo, post-processing, jakość
// =====================================================================
import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { MAP, QUALITY } from './config.js';

const SKY_TOP = new THREE.Color(0x1d2346);
const SKY_HORIZON = new THREE.Color(0xc0714a);
const FOG_COLOR = new THREE.Color(0x6a5060);

// Winieta + delikatne ziarno filmowe (klimat apokalipsy)
const VignetteShader = {
  uniforms: { tDiffuse: { value: null }, uTime: { value: 0 }, uDamage: { value: 0 } },
  vertexShader: /* glsl */`
    varying vec2 vUv;
    void main() { vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`,
  fragmentShader: /* glsl */`
    uniform sampler2D tDiffuse; uniform float uTime; uniform float uDamage;
    varying vec2 vUv;
    float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
    void main() {
      vec4 c = texture2D(tDiffuse, vUv);
      vec2 d = vUv - 0.5;
      float r = dot(d, d);
      float vig = smoothstep(0.75, 0.18, r);
      c.rgb *= mix(0.72, 1.0, vig);
      // czerwony błysk przy obrażeniach bazy
      c.rgb = mix(c.rgb, vec3(0.6, 0.02, 0.02), uDamage * smoothstep(0.1, 0.5, r));
      c.rgb += (hash(vUv * 800.0 + uTime) - 0.5) * 0.025;
      gl_FragColor = c;
    }`,
};

export class Renderer {
  constructor(container) {
    this.container = container;
    this.scene = new THREE.Scene();
    this.scene.fog = new THREE.Fog(FOG_COLOR, 70, 190);

    this.camera = new THREE.PerspectiveCamera(42, innerWidth / innerHeight, 0.5, 400);

    this.renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: 'high-performance' });
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = 1.1;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    container.appendChild(this.renderer.domElement);

    this.time = 0;
    this.damageFlash = 0;
    this.quality = null;

    this._createSky();
    this._createLights();
    this._createComposer();
    this.resize();
    addEventListener('resize', () => this.resize());
  }

  _createSky() {
    const geo = new THREE.SphereGeometry(300, 32, 16);
    const mat = new THREE.ShaderMaterial({
      side: THREE.BackSide, depthWrite: false, fog: false,
      uniforms: {
        uTop: { value: SKY_TOP }, uHorizon: { value: SKY_HORIZON },
        uSunDir: { value: new THREE.Vector3(-0.6, 0.3, -0.6).normalize() },
      },
      vertexShader: /* glsl */`
        varying vec3 vDir;
        void main() {
          vDir = normalize(position);
          vec4 p = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
          gl_Position = p.xyww;
        }`,
      fragmentShader: /* glsl */`
        uniform vec3 uTop; uniform vec3 uHorizon; uniform vec3 uSunDir;
        varying vec3 vDir;
        void main() {
          float h = clamp(vDir.y, -0.2, 1.0);
          vec3 col = mix(uHorizon, uTop, smoothstep(-0.05, 0.55, h));
          float sun = max(dot(normalize(vDir), uSunDir), 0.0);
          col += vec3(1.0, 0.55, 0.25) * pow(sun, 12.0) * 0.7;
          col += vec3(1.0, 0.8, 0.5) * pow(sun, 400.0) * 3.0;
          gl_FragColor = vec4(col, 1.0);
          #include <tonemapping_fragment>
          #include <colorspace_fragment>
        }`,
    });
    this.sky = new THREE.Mesh(geo, mat);
    this.sky.renderOrder = -10;
    this.sky.frustumCulled = false;
    this.scene.add(this.sky);
  }

  _createLights() {
    this.hemi = new THREE.HemisphereLight(0xc4cce8, 0x4a4030, 1.35);
    this.scene.add(this.hemi);

    this.sun = new THREE.DirectionalLight(0xffd6ae, 3.0);
    this.sun.position.set(-48, 78, 42); // z lewej-przodu: oświetla ściany widoczne z kamery
    this.sun.target.position.set(0, 0, 0);
    this.scene.add(this.sun, this.sun.target);
    const sc = this.sun.shadow.camera;
    // światło pada pod kątem, więc ramka cieni musi objąć obróconą mapę
    sc.left = -MAP.halfW - 12; sc.right = MAP.halfW + 12;
    sc.top = MAP.halfD + 30; sc.bottom = -MAP.halfD - 30;
    sc.near = 10; sc.far = 220;
    this.sun.shadow.bias = -0.0006;
    this.sun.shadow.normalBias = 0.04;

    // Delikatne niebieskie światło wypełniające z drugiej strony
    this.fill = new THREE.DirectionalLight(0x8898d0, 0.7); // kontra z prawej-tyłu
    this.fill.position.set(50, 30, -40);
    this.scene.add(this.fill);
  }

  _createComposer() {
    this.composer = null;
    this.bloomPass = null;
    this.vignettePass = null;
  }

  _buildComposer(q) {
    if (this.composer) { this.composer.dispose(); this.composer = null; }
    if (!q.bloom) return;
    const size = this.renderer.getDrawingBufferSize(new THREE.Vector2());
    const rt = new THREE.WebGLRenderTarget(size.x, size.y, {
      type: THREE.HalfFloatType,
      samples: this.renderer.capabilities.isWebGL2 ? q.msaa : 0,
    });
    this.composer = new EffectComposer(this.renderer, rt);
    this.composer.addPass(new RenderPass(this.scene, this.camera));
    this.bloomPass = new UnrealBloomPass(new THREE.Vector2(size.x / 2, size.y / 2), 0.45, 0.45, 0.9);
    this.composer.addPass(this.bloomPass);
    this.vignettePass = new ShaderPass(VignetteShader);
    this.composer.addPass(this.vignettePass);
    this.composer.addPass(new OutputPass());
  }

  applyQuality(key) {
    const q = QUALITY[key];
    this.quality = key;
    this.renderer.setPixelRatio(Math.min(devicePixelRatio || 1, q.pixelRatio));
    this.renderer.shadowMap.enabled = q.shadows;
    this.sun.castShadow = q.shadows;
    if (q.shadows) {
      this.sun.shadow.mapSize.set(q.shadowMap, q.shadowMap);
      if (this.sun.shadow.map) { this.sun.shadow.map.dispose(); this.sun.shadow.map = null; }
    }
    // materiały muszą się przekompilować po zmianie cieni
    this.scene.traverse(o => {
      if (o.material) (Array.isArray(o.material) ? o.material : [o.material]).forEach(m => m.needsUpdate = true);
    });
    this.resize();
    this._buildComposer(q);
    this.resize();
  }

  setExposure(v) { this.renderer.toneMappingExposure = v; }

  resize() {
    const w = innerWidth, h = innerHeight;
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
    this.renderer.setSize(w, h);
    if (this.composer) {
      this.composer.setPixelRatio(this.renderer.getPixelRatio());
      this.composer.setSize(w, h);
    }
    this.onResize?.();
  }

  /** Skala rozmiaru cząsteczek (piksele na jednostkę świata przy odległości 1) */
  get pointScale() {
    return this.renderer.domElement.height * 0.5 * this.camera.projectionMatrix.elements[5];
  }

  render(dt) {
    this.time += dt;
    this.damageFlash = Math.max(0, this.damageFlash - dt * 2.5);
    this.sky.position.copy(this.camera.position);
    if (this.composer) {
      this.vignettePass.uniforms.uTime.value = this.time % 100;
      this.vignettePass.uniforms.uDamage.value = this.damageFlash;
      this.composer.render(dt);
    } else {
      this.renderer.render(this.scene, this.camera);
    }
  }
}

// =====================================================================
//  KAMERA: przesuwanie w osi X, zoom, wstrząsy
// =====================================================================
export class CameraRig {
  constructor(camera) {
    this.camera = camera;
    this.targetX = MAP.baseX - 30;
    this.x = this.targetX;
    this.zoom = 1;
    this.targetZoom = 1;
    this.shake = 0;
    this.minX = MAP.spawnX + 12;
    this.maxX = MAP.baseX - 4;
  }
  pan(dx) { this.targetX = THREE.MathUtils.clamp(this.targetX + dx, this.minX, this.maxX); }
  setZoom(z) { this.targetZoom = THREE.MathUtils.clamp(z, 0.55, 1.35); }
  addShake(v) { this.shake = Math.min(1.5, this.shake + v); }

  /** Ile jednostek świata przypada na piksel ekranu (do przeciągania) */
  unitsPerPixel() {
    const dist = this._distance();
    const visibleH = 2 * Math.tan(THREE.MathUtils.degToRad(this.camera.fov / 2)) * dist;
    return visibleH / innerHeight;
  }

  _distance() {
    // na wąskich ekranach (telefon w pionie) odsuń kamerę, żeby zmieściła się głębokość mapy
    const aspectFix = Math.max(1, 1.5 / this.camera.aspect);
    return 64 * this.zoom * aspectFix;
  }

  update(dt) {
    const k = 1 - Math.exp(-dt * 10);
    this.x += (this.targetX - this.x) * k;
    this.zoom += (this.targetZoom - this.zoom) * k;
    this.shake = Math.max(0, this.shake - dt * 2.2);

    const dist = this._distance();
    const pitch = THREE.MathUtils.degToRad(46);
    const sx = (Math.random() - 0.5) * this.shake * 0.8;
    const sy = (Math.random() - 0.5) * this.shake * 0.8;
    this.camera.position.set(this.x + sx, Math.sin(pitch) * dist + sy, Math.cos(pitch) * dist + 2);
    this.camera.lookAt(this.x + sx * 0.5, 0, 2);
  }
}
