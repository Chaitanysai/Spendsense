// Fails loudly on any invalid YAML in the repository.
//
// Written because a bad edit silently produced a workflow file GitHub could not
// even register ("This run likely failed because of a workflow file issue"),
// while an earlier string-based check still reported success.
//
//   node tool/validate_yaml.js
//
// Exits 1 on the first unparseable document, printing file, line and column.

const fs = require('fs');
const path = require('path');
const { parse } = require('yaml');

const ROOT = path.resolve(__dirname, '..');
const SKIP_DIRS = new Set([
  'node_modules', '.git', 'build', '.dart_tool', '.gradle',
  'android/.gradle', 'ios/Pods', '.slim',
]);
const EXTENSIONS = new Set(['.yml', '.yaml']);

function walk(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    const rel = path.relative(ROOT, full).split(path.sep).join('/');
    if (entry.isDirectory()) {
      if (SKIP_DIRS.has(entry.name) || SKIP_DIRS.has(rel)) continue;
      walk(full, out);
    } else if (EXTENSIONS.has(path.extname(entry.name).toLowerCase())) {
      out.push(full);
    }
  }
  return out;
}

const files = walk(ROOT).sort();
const failures = [];

// Firebase Hosting deploys replace the whole site, so ota-publish.yml's deploy
// job must publish the artifact the validate job built and verified. A deploy
// job that publishes its own checkout ships nothing: ota/public tracks only
// .gitkeep placeholders, and the resulting empty release deletes the live
// manifest and APKs. Checked here because nothing else runs this workflow
// before it reaches production.
function checkOtaPayloadHandoff(doc, rel) {
  const validate = doc.jobs.validate;
  const deploy = doc.jobs.deploy;
  if (!validate || !deploy) {
    failures.push(`${rel}: expected both a validate and a deploy job`);
    return;
  }

  const stepsOf = (job) => (Array.isArray(job.steps) ? job.steps : []);
  const usesStartsWith = (prefix) => (step) =>
    step && typeof step === 'object' && String(step.uses || '').startsWith(prefix);

  const upload = stepsOf(validate).find(usesStartsWith('actions/upload-artifact@'));
  const download = stepsOf(deploy).find(usesStartsWith('actions/download-artifact@'));

  if (!upload) {
    failures.push(`${rel}: validate does not upload the OTA payload`);
    return;
  }
  const uploaded = upload.with && upload.with.name;
  if (!uploaded) {
    failures.push(`${rel}: validate uploads an artifact with no name`);
    return;
  }
  if (!download) {
    failures.push(
      `${rel}: deploy does not download the OTA payload; it would publish its own checkout and empty the site`,
    );
    return;
  }
  const downloaded = download.with && download.with.name;
  if (downloaded !== uploaded) {
    failures.push(
      `${rel}: deploy downloads "${downloaded}" but validate uploads "${uploaded}"`,
    );
  }

  let hostingDir = null;
  try {
    const firebase = JSON.parse(fs.readFileSync(path.join(ROOT, 'firebase.json'), 'utf8'));
    hostingDir = firebase?.hosting?.public;
  } catch {
    failures.push(`${rel}: firebase.json is missing or unreadable`);
    return;
  }
  if (typeof hostingDir !== 'string' || hostingDir.trim() === '') {
    failures.push(`${rel}: firebase.json has no hosting.public directory`);
    return;
  }
  const normalise = (p) => String(p || '').replace(/^\.\//, '').replace(/\/+$/, '');
  const target = download.with && download.with.path;
  if (normalise(target) !== normalise(hostingDir)) {
    failures.push(
      `${rel}: deploy downloads the payload to "${target}" but hosting serves "${hostingDir}"`,
    );
  }

  // GitHub drops a job output whose value matches a registered secret, so an
  // APK path passed from validate can arrive empty and a guard that trusts it
  // fails closed on every real deploy. The payload must be verified directly.
  const deploySteps = stepsOf(deploy);
  if (JSON.stringify(deploySteps).includes('outputs.apk_path')) {
    failures.push(
      `${rel}: deploy reads needs.validate.outputs.apk_path, which GitHub silently drops when the value matches a secret`,
    );
  }
  const digestGuard = deploySteps.find((step) => {
    const run = String((step && step.run) || '');
    return run.includes('sha256sum') && run.includes('manifest.json');
  });
  if (!digestGuard) {
    failures.push(
      `${rel}: no deploy step re-checks the payload APK digest against manifest.json before publishing`,
    );
  }
}

for (const file of files) {
  const rel = path.relative(ROOT, file).split(path.sep).join('/');
  const text = fs.readFileSync(file, 'utf8');
  try {
    parse(text);
    // Workflows must additionally be a mapping with a jobs key: a file that
    // parses as a scalar or list can still be rejected at job registration.
    if (rel.startsWith('.github/workflows/')) {
      const doc = parse(text);
      if (!doc || typeof doc !== 'object' || Array.isArray(doc)) {
        failures.push(`${rel}: top level is not a mapping`);
        continue;
      }
      if (!doc.jobs || typeof doc.jobs !== 'object') {
        failures.push(`${rel}: no jobs mapping`);
        continue;
      }
      for (const [id, job] of Object.entries(doc.jobs)) {
        if (!job || typeof job !== 'object' || Array.isArray(job)) {
          failures.push(`${rel}: job "${id}" is not a mapping`);
        } else if (!job['runs-on']) {
          failures.push(`${rel}: job "${id}" has no runs-on`);
        }
      }
      if (rel === '.github/workflows/ota-publish.yml') {
        checkOtaPayloadHandoff(doc, rel);
      }
    }
    console.log(`  ok    ${rel}`);
  } catch (error) {
    const where = error.linePos?.[0];
    const loc = where ? `:${where.line}:${where.col}` : '';
    failures.push(`${rel}${loc}: ${String(error.message).split('\n')[0]}`);
    console.log(`  FAIL  ${rel}${loc}`);
  }
}

console.log('');
if (failures.length > 0) {
  console.error(`INVALID YAML in ${failures.length} file(s):`);
  for (const f of failures) console.error(`  ${f}`);
  process.exit(1);
}
console.log(`OK: ${files.length} YAML file(s) parsed and workflow structure checked`);
