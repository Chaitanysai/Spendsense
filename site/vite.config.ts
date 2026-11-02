import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

/**
 * SpendSense landing site.
 *
 * Output topology, decided by the hosting constraint rather than preference:
 *
 *   ota/public/index.html      the app shell
 *   ota/public/site/assets/*   hashed JS/CSS
 *   ota/public/manifest.json   OTA contract   — this build never writes it
 *   ota/public/releases/*.apk  OTA payload    — this build never writes it
 *   ota/public/legal/**        legal pages    — this build never writes it
 *
 * `firebase deploy` replaces the whole Hosting release, so anything missing from
 * ota/public at deploy time disappears from production. The update channel for
 * every installed app lives in that directory, and a previous deploy did remove
 * it. `emptyOutDir` is therefore OFF, so Vite only adds and overwrites its own
 * two outputs, and `scripts/guard.mjs` verifies afterwards that the manifest,
 * the APK and its digest, and the legal pages are all still intact.
 */
export default defineConfig({
  base: "/",
  plugins: [react()],
  build: {
    outDir: "../ota/public",
    emptyOutDir: false,
    assetsDir: "site/assets",
    sourcemap: false,
    target: "es2020",
    rollupOptions: {
      output: {
        manualChunks: {
          // Three.js is the heavy half and is not needed for first paint.
          three: ["three"],
        },
      },
    },
  },
});
