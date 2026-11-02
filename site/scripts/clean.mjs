import { rmSync, existsSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

/**
 * Clears only the hashed asset directory before a build.
 *
 * `emptyOutDir` is off for the hosting root because that directory also holds
 * the OTA manifest and the release APKs. Stale hashed files would otherwise
 * accumulate there forever, so this removes the one directory the build owns.
 */
const HERE = dirname(fileURLToPath(import.meta.url));
// HERE is <repo>/site/scripts, so the hosting root is two levels up. A single
// "../" resolved to <repo>/site/ota/public/site/assets, which does not exist —
// so this script silently did nothing and stale hashed bundles piled up in the
// deployed payload (11 files on disk where the last build produced 3).
const assets = resolve(HERE, "../../ota/public/site/assets");

if (existsSync(assets)) {
  rmSync(assets, { recursive: true, force: true });
  console.log("cleared ota/public/site/assets");
}
