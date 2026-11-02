import { useEffect, useRef, useState } from "react";
import { createHeroScene, type HeroScene as HeroSceneApi } from "../three/heroScene";
import { useReducedMotion } from "../hooks";

/**
 * The particle centrepiece.
 *
 * Responsible for one thing: owning the WebGL context's lifetime and feeding it
 * scroll and pointer. It deliberately does not re-render React on scroll or
 * pointer move, both of which would be an expensive way to move some pixels.
 *
 * Falls back to a static CSS treatment when WebGL is unavailable, when the
 * device reports reduced motion, or when the bundle cannot run.
 */
export function HeroScene({ progressRef }: { progressRef: React.MutableRefObject<number> }) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const sceneRef = useRef<HeroSceneApi | null>(null);
  const reduced = useReducedMotion();
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    if (reduced) return;
    const canvas = canvasRef.current;
    if (!canvas) return;

    const scene = createHeroScene(canvas);
    if (!scene) {
      setFailed(true);
      return;
    }
    sceneRef.current = scene;

    // Entrance: the cloud fades up while resolving from scatter toward grid.
    let raf = 0;
    const started = performance.now();
    const intro = () => {
      const t = Math.min((performance.now() - started) / 2200, 1);
      const eased = 1 - Math.pow(1 - t, 3);
      scene.setFade(Math.min(eased * 1.4, 1));
      scene.setResolve(0.55 * eased + progressRef.current * 0.45);
      if (t < 1) raf = requestAnimationFrame(intro);
    };
    raf = requestAnimationFrame(intro);

    let queue = 0;
    const onMove = (e: PointerEvent) => {
      if (e.pointerType !== "mouse") return;
      if (queue) return;
      queue = requestAnimationFrame(() => {
        scene.setPointer(
          (e.clientX / window.innerWidth) * 2 - 1,
          -((e.clientY / window.innerHeight) * 2 - 1)
        );
        queue = 0;
      });
    };
    window.addEventListener("pointermove", onMove, { passive: true });

    return () => {
      cancelAnimationFrame(raf);
      if (queue) cancelAnimationFrame(queue);
      window.removeEventListener("pointermove", onMove);
      scene.dispose();
      sceneRef.current = null;
    };
  }, [reduced, progressRef]);

  // Scroll feeds the resolve: the cloud orders itself as the hero leaves.
  useEffect(() => {
    const scene = sceneRef.current;
    if (!scene || reduced) return;
    let raf = 0;
    const tick = () => {
      scene.setResolve(0.55 + Math.min(progressRef.current, 1) * 0.45);
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [reduced, progressRef]);

  if (reduced || failed) {
    return (
      <div className="scene-static" aria-hidden="true">
        <div className="scene-static__orb" />
        <div className="scene-static__surface" />
      </div>
    );
  }

  return <canvas ref={canvasRef} className="scene-canvas" aria-hidden="true" />;
}
