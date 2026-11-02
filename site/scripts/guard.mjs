import { createHash } from "node:crypto";
import { readFileSync, existsSync, readdirSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

/**
 * Post-build guard.
 *
 * `firebase deploy` replaces the entire Hosting release with whatever is in
 * ota/public, so anything this build deletes is deleted from production. The
 * update channel for every installed app lives in that directory. This script
 * asserts the OTA payload and the legal pages survived the build; if they did
 * not, the build is a failure, not a commit.
 */
const HERE = dirname(fileURLToPath(import.meta.url));
const HOSTING = resolve(HERE, "../../ota/public");

const REQUIRED = [
  "index.html",
  "404.html",
  "landing.css",
  "manifest.json",
  "legal/index.html",
  "legal/style.css",
  "legal/fonts/fonts.css",
];

let failed = false;

for (const rel of REQUIRED) {
  const p = resolve(HOSTING, rel);
  if (!existsSync(p) || readFileSync(p).length === 0) {
    console.error(`FAIL ${rel} is missing or empty in ota/public`);
    failed = true;
  }
}

// The manifest must still describe a real APK that is present and matches.
const manifestPath = resolve(HOSTING, "manifest.json");
if (existsSync(manifestPath)) {
  const m = JSON.parse(readFileSync(manifestPath, "utf8"));
  const rel = String(m.downloadUrl || "").split("/").slice(-2).join("/");
  const apk = resolve(HOSTING, rel);
  if (!existsSync(apk)) {
    console.error(`FAIL manifest points at ${rel}, which is not in ota/public`);
    failed = true;
  } else {
    const digest = createHash("sha256").update(readFileSync(apk)).digest("hex");
    if (digest !== m.sha256) {
      console.error(`FAIL ${rel} does not match the sha256 in manifest.json`);
      failed = true;
    }
  }
}

// The shell must be the app build, not a stale page.
const shell = resolve(HOSTING, "index.html");
if (existsSync(shell)) {
  const html = readFileSync(shell, "utf8");
  if (!html.includes("/site/assets/")) {
    console.error("FAIL ota/public/index.html does not reference /site/assets/");
    failed = true;
  }
}

const assetDir = resolve(HOSTING, "site/assets");
if (!existsSync(assetDir) || readdirSync(assetDir).length === 0) {
  console.error("FAIL ota/public/site/assets is missing or empty");
  failed = true;
}

// Every asset the shell asks for must exist. This is the check that catches a
// payload where index.html survived but the bundles it references did not —
// the state CI would produce if the built output were not committed. Without
// it the page 404s on its own CSS and JS while the deploy still succeeds.
if (existsSync(shell)) {
  const html = readFileSync(shell, "utf8");
  const referenced = new Set();
  const attr = /(?:src|href)="(\/site\/assets\/[^"]+)"/g;
  for (const m of html.matchAll(attr)) referenced.add(m[1]);
  for (const href of referenced) {
    if (!existsSync(resolve(HOSTING, href.replace(/^\//, "")))) {
      console.error(`FAIL ota/public/index.html references ${href}, which is missing`);
      failed = true;
    }
  }
  if (referenced.size === 0) {
    console.error("FAIL ota/public/index.html references no /site/assets/ files");
    failed = true;
  }
}

if (failed) {
  console.error("\nBuild guard failed: the hosting payload is not safe to deploy.");
  process.exit(1);
}

console.log("Build guard passed: OTA manifest, APK digest and legal pages intact.");
