import * as THREE from "three";

/**
 * The hero centrepiece.
 *
 * A drifting constellation of transaction nodes that resolves into an ordered
 * ledger grid, standing in rippling water with its reflection beneath. This is
 * the SpendSense translation of the reference's particle-tree-in-water: same
 * rendering discipline (one Points cloud, a custom shader, a mirrored reflection,
 * cursor repulsion), original geometry and meaning.
 *
 * The form carries the product's own argument: scattered payments resolving
 * into an ordered record. It is not decoration with a finance skin on it.
 *
 * Cost control:
 *  - one BufferGeometry for the cloud, one draw call, no per-frame allocation
 *  - the loop stops when the canvas is offscreen or the tab is hidden
 *  - density and pixel ratio scale down on small screens
 */

/** Deterministic PRNG so the layout is identical on every load. */
function mulberry32(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const vertexShader = /* glsl */ `
  attribute vec3 aScatter;
  attribute vec3 aGrid;
  attribute float aSeed;
  attribute float aTier;

  uniform float uTime;
  uniform float uResolve;
  uniform float uPixelRatio;
  uniform vec3 uPointer;

  varying float vAlpha;
  varying float vTier;

  void main() {
    // Two states: the scatter (a loose cloud) and the grid (an ordered ledger).
    vec3 pos = mix(aScatter, aGrid, uResolve);

    // Idle drift, stronger in the scatter so the cloud breathes.
    float drift = 1.0 - uResolve * 0.65;
    pos.x += sin(uTime * 0.32 + aSeed * 6.2831) * 0.09 * drift;
    pos.y += cos(uTime * 0.27 + aSeed * 6.2831) * 0.11 * drift;
    pos.z += sin(uTime * 0.21 + aSeed * 4.0) * 0.07 * drift;

    vec4 mv = modelViewMatrix * vec4(pos, 1.0);
    vec3 world = (modelMatrix * vec4(pos, 1.0)).xyz;

    // Cursor repulsion in world space, falling off with distance.
    vec3 d = world - uPointer;
    float dist = length(d.xy);
    float push = smoothstep(3.4, 0.0, dist) * 0.85;
    mv.xy += normalize(d.xy + 0.0001) * push;

    gl_Position = projectionMatrix * mv;

    // Points nearer the camera are brighter, which gives the cloud its depth.
    float depth = 1.0 - smoothstep(1.5, 15.0, -mv.z);
    vAlpha = (0.55 + depth * 0.85) * (0.55 + aTier * 0.75);
    gl_PointSize = uPixelRatio * (1.9 + aTier * 3.6) * (10.5 / max(-mv.z, 0.6));
    vTier = aTier;
  }
`;

const fragmentShader = /* glsl */ `
  uniform vec3 uColorA;
  uniform vec3 uColorB;
  uniform float uFade;
  varying float vAlpha;
  varying float vTier;

  void main() {
    // Round point, soft edge, no texture read.
    vec2 uv = gl_PointCoord - 0.5;
    float d = length(uv);
    if (d > 0.5) discard;
    float soft = smoothstep(0.5, 0.06, d);
    vec3 col = mix(uColorA, uColorB, smoothstep(0.55, 1.0, vTier));
    gl_FragColor = vec4(col, soft * vAlpha * uFade);
  }
`;

export type HeroScene = {
  dispose: () => void;
  setPointer: (x: number, y: number) => void;
  /** 0 = scattered cloud, 1 = resolved ledger grid. */
  setResolve: (v: number) => void;
  setFade: (v: number) => void;
};

export function createHeroScene(canvas: HTMLCanvasElement): HeroScene | null {
  let renderer: THREE.WebGLRenderer;
  try {
    renderer = new THREE.WebGLRenderer({
      canvas,
      antialias: false,
      alpha: true,
      powerPreference: "high-performance",
    });
  } catch {
    return null; // Caller falls back to the static treatment.
  }

  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(42, 1, 0.1, 100);
  camera.position.set(0, 1.05, 11.4);
  camera.lookAt(0, -0.15, 0);

  const small = window.matchMedia("(max-width: 760px)").matches;
  const COUNT = small ? 5200 : 14000;
  const rnd = mulberry32(20261102);

  // ── the two shapes ──────────────────────────────────────────────────────
  // Scatter: a soft vertical cloud, wider than tall, the drifting payments.
  // Grid: an ordered 3D ledger lattice, the same points resolved.
  const scatter = new Float32Array(COUNT * 3);
  const grid = new Float32Array(COUNT * 3);
  const seeds = new Float32Array(COUNT);
  const tiers = new Float32Array(COUNT);

  const GRID_COLS = 34;
  const GRID_ROWS = 22;
  const GRID_DEPTH = 6;

  for (let i = 0; i < COUNT; i++) {
    const i3 = i * 3;

    // Scatter: a column rising from the water line that fans out into a canopy.
    // Same "grown from the ground" gesture as the reference's tree, but the form
    // means something here: individual payments gathering upward into one view.
    const v = rnd();
    let sx: number, sy: number, sz: number;
    if (v < 0.34) {
      // Trunk: a narrow, slightly wavering column.
      const t = rnd();
      const taper = 0.14 + t * 0.26;
      const a = rnd() * Math.PI * 2;
      const r = Math.sqrt(rnd()) * taper;
      sx = Math.cos(a) * r + Math.sin(t * 7.0) * 0.06;
      sz = Math.sin(a) * r * 0.8;
      sy = -1.55 + t * 2.5;
    } else {
      // Canopy: dense core thinning to a ragged edge, which is what makes a
      // particle mass read as a silhouette rather than a sphere of noise.
      let cx = 0, cy = 0, cz = 0, rr = 2;
      let guard = 0;
      while (rr > 1 && guard++ < 24) {
        cx = rnd() * 2 - 1;
        cy = rnd() * 2 - 1;
        cz = rnd() * 2 - 1;
        rr = cx * cx + cy * cy * 0.82 + cz * cz * 0.7;
      }
      const spread = 0.78 + Math.pow(rnd(), 2.2) * 0.42;
      sx = cx * 3.05 * spread;
      sy = 1.05 + cy * 1.42 * spread;
      sz = cz * 1.5 * spread;
      // Ragged edge: push a fraction of the outer points past the envelope.
      if (rnd() > 0.88) {
        sx *= 1.22;
        sy = sy * 1.03 + 0.16;
      }
    }
    scatter[i3] = sx;
    scatter[i3 + 1] = sy;
    scatter[i3 + 2] = sz;

    // Grid: jittered lattice so it reads as a ledger, not as a wireframe box.
    const gx = i % GRID_COLS;
    const gy = Math.floor(i / GRID_COLS) % GRID_ROWS;
    const gz = Math.floor(i / (GRID_COLS * GRID_ROWS)) % GRID_DEPTH;
    const stepX = 7.0 / (GRID_COLS - 1);
    const stepY = 3.5 / (GRID_ROWS - 1);
    const stepZ = 0.5 / Math.max(GRID_DEPTH - 1, 1);
    grid[i3] = -3.5 + gx * stepX + (rnd() - 0.5) * 0.05;
    grid[i3 + 1] = -1.6 + gy * stepY + (rnd() - 0.5) * 0.05;
    grid[i3 + 2] = -1.25 + gz * stepZ * 5 + (rnd() - 0.5) * 0.04;

    seeds[i] = rnd();
    // A few bright "nodes" among many dim ones is what makes a node cloud read.
    tiers[i] = rnd() > 0.93 ? 1 : rnd() * 0.55;
  }

  const geo = new THREE.BufferGeometry();
  geo.setAttribute("position", new THREE.BufferAttribute(grid, 3));
  geo.setAttribute("aScatter", new THREE.BufferAttribute(scatter, 3));
  geo.setAttribute("aGrid", new THREE.BufferAttribute(grid, 3));
  geo.setAttribute("aSeed", new THREE.BufferAttribute(seeds, 1));
  geo.setAttribute("aTier", new THREE.BufferAttribute(tiers, 1));

  const uniforms = {
    uTime: { value: 0 },
    uResolve: { value: 0 },
    uFade: { value: 0 },
    uPixelRatio: { value: 1 },
    uPointer: { value: new THREE.Vector3(999, 999, 0) },
    uColorA: { value: new THREE.Color("#1fd1c4") },
    uColorB: { value: new THREE.Color("#22e07a") },
  };

  const material = new THREE.ShaderMaterial({
    uniforms,
    vertexShader,
    fragmentShader,
    transparent: true,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
  });

  const points = new THREE.Points(geo, material);
  scene.add(points);

  // ── the water ──────────────────────────────────────────────────────────
  // A mirrored copy below the horizon, dimmer and vertically squeezed, which is
  // what sells the surface without a second full particle simulation.
  const reflectionGeo = geo.clone();
  const reflectionMat = material.clone();
  (reflectionMat.uniforms as typeof uniforms).uFade = { value: 0 };
  const reflection = new THREE.Points(reflectionGeo, reflectionMat);
  reflection.scale.set(1, -0.62, 1);
  reflection.position.set(0, -2.05, 0);
  scene.add(reflection);

  // The surface itself: a large disc that catches a soft glow at its centre and
  // falls to black at the rim, so the water has a horizon rather than floating
  // rings in a void.
  const waterGeo = new THREE.CircleGeometry(16, 64);
  const waterMat = new THREE.ShaderMaterial({
    transparent: true,
    depthWrite: false,
    uniforms: {
      uFade: { value: 0 },
      uTime: { value: 0 },
      uA: { value: new THREE.Color("#1fd1c4") },
      uB: { value: new THREE.Color("#0b3a38") },
    },
    vertexShader: /* glsl */ `
      varying vec2 vUv;
      void main() {
        vUv = uv;
        gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
      }
    `,
    fragmentShader: /* glsl */ `
      varying vec2 vUv;
      uniform float uFade;
      uniform float uTime;
      uniform vec3 uA;
      uniform vec3 uB;
      void main() {
        vec2 p = vUv - 0.5;
        float r = length(p) * 2.0;
        // Glow strongest at the centre, dying out well before the rim.
        float core = smoothstep(0.95, 0.0, r);
        float glow = pow(core, 2.6) * 0.55 + core * 0.10;
        // Slow concentric swell so the surface is never static.
        float wave = 0.5 + 0.5 * sin(r * 26.0 - uTime * 0.55);
        glow *= 0.86 + wave * 0.14;
        vec3 col = mix(uB, uA, core);
        float a = glow * uFade * smoothstep(1.0, 0.55, r);
        gl_FragColor = vec4(col, a);
      }
    `,
  });
  const water = new THREE.Mesh(waterGeo, waterMat);
  water.rotation.x = -Math.PI / 2;
  water.position.y = -2.05;
  scene.add(water);

  // Ripple rings on the surface, drawn as thin line loops.
  const rippleMat = new THREE.LineBasicMaterial({
    color: new THREE.Color("#1fd1c4"),
    transparent: true,
    opacity: 0,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
  });
  const ripples: THREE.Line[] = [];
  for (let i = 0; i < 7; i++) {
    const pts: THREE.Vector3[] = [];
    const segs = 128;
    for (let s = 0; s <= segs; s++) {
      const a = (s / segs) * Math.PI * 2;
      // Slight vertical wobble so the ring reads as water, not as a circle vector.
      const wob = 1 + Math.sin(a * 3 + i) * 0.045;
      pts.push(new THREE.Vector3(Math.cos(a) * wob, 0, Math.sin(a) * wob));
    }
    const g = new THREE.BufferGeometry().setFromPoints(pts);
    const line = new THREE.Line(g, rippleMat.clone());
    const base = 0.85 + i * 0.66;
    line.scale.setScalar(base);
    line.position.y = -2.05;
    line.rotation.x = Math.PI / 2;
    scene.add(line);
    ripples.push(line);
  }

  // ── resize ─────────────────────────────────────────────────────────────
  const maxDpr = small ? 1.5 : 2;
  const resize = () => {
    const w = canvas.clientWidth || 1;
    const h = canvas.clientHeight || 1;
    const dpr = Math.min(window.devicePixelRatio || 1, maxDpr);
    renderer.setPixelRatio(dpr);
    renderer.setSize(w, h, false);
    uniforms.uPixelRatio.value = dpr;
    (reflectionMat.uniforms as typeof uniforms).uPixelRatio.value = dpr;
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
  };
  resize();
  const ro = new ResizeObserver(resize);
  ro.observe(canvas);

  // ── loop ───────────────────────────────────────────────────────────────
  let raf = 0;
  let running = false;
  const clock = new THREE.Clock();
  const pointerTarget = new THREE.Vector3(999, 999, 0);

  const frame = () => {
    if (!running) return;
    const t = clock.getElapsedTime();
    uniforms.uTime.value = t;
    (reflectionMat.uniforms as typeof uniforms).uTime.value = t;

    // Ease the pointer so the push is not a jump.
    uniforms.uPointer.value.lerp(pointerTarget, 0.08);
    (reflectionMat.uniforms as typeof uniforms).uPointer.value.copy(
      uniforms.uPointer.value
    );

    // Ripples expand and fade on a slow loop.
    ripples.forEach((line, i) => {
      const phase = (t * 0.14 + i * 0.16) % 1;
      const s = 0.85 + phase * 5.2 + i * 0.5;
      line.scale.setScalar(s);
      const m = line.material as THREE.LineBasicMaterial;
      m.opacity = uniforms.uFade.value * 0.38 * (1 - phase) * (1 - phase);
    });

    reflectionMat.uniforms.uFade.value = uniforms.uFade.value * 0.55;
    waterMat.uniforms.uFade.value = uniforms.uFade.value;
    waterMat.uniforms.uTime.value = t;

    renderer.render(scene, camera);
    raf = requestAnimationFrame(frame);
  };

  const start = () => {
    if (running) return;
    running = true;
    clock.start();
    raf = requestAnimationFrame(frame);
  };
  const stop = () => {
    running = false;
    cancelAnimationFrame(raf);
  };

  // Only run while the canvas is actually on screen and the tab is visible.
  const io = new IntersectionObserver(
    (entries) => {
      if (entries[0].isIntersecting && !document.hidden) start();
      else stop();
    },
    { threshold: 0.01 }
  );
  io.observe(canvas);

  const onVisibility = () => {
    if (document.hidden) stop();
    else if (canvas.getBoundingClientRect().bottom > 0) start();
  };
  document.addEventListener("visibilitychange", onVisibility);

  const dispose = () => {
    stop();
    io.disconnect();
    ro.disconnect();
    document.removeEventListener("visibilitychange", onVisibility);
    geo.dispose();
    reflectionGeo.dispose();
    material.dispose();
    reflectionMat.dispose();
    waterGeo.dispose();
    waterMat.dispose();
    ripples.forEach((l) => {
      l.geometry.dispose();
      (l.material as THREE.Material).dispose();
    });
    renderer.dispose();
  };

  return {
    dispose,
    setPointer(x, y) {
      // Screen-normalised (-1..1) projected onto the z=0 plane at the cloud.
      const v = new THREE.Vector3(x * 5.2, y * 3.4 - 0.15, 0);
      pointerTarget.copy(v);
    },
    setResolve(v) {
      uniforms.uResolve.value = v;
    },
    setFade(v) {
      uniforms.uFade.value = v;
    },
  };
}
