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

// Defaults to the repository this file lives in; YAML_ROOT lets the guard test
// point the same checks at a mutated copy without editing the real workflow.
const ROOT = path.resolve(process.env.YAML_ROOT || path.resolve(__dirname, '..'));
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

  const normalise = (p) => String(p || '').replace(/^\.\//, '').replace(/\/+$/, '');
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

  // The payload is whichever artifact validate uploads from the directory
  // hosting serves. Naming it explicitly is what stops the recovery baseline
  // (uploaded later, stored elsewhere) being mistaken for the payload.
  const upload = stepsOf(validate).find(
    (step) => usesStartsWith('actions/upload-artifact@')(step) && normalise(step.with && step.with.path) === normalise(hostingDir),
  );
  if (!upload) {
    failures.push(`${rel}: validate does not upload "${hostingDir}" as an artifact`);
    return;
  }
  const uploaded = upload.with && upload.with.name;
  if (!uploaded) {
    failures.push(`${rel}: validate uploads an artifact with no name`);
    return;
  }
  const downloads = stepsOf(deploy).filter(usesStartsWith('actions/download-artifact@'));
  const download = downloads.find((s) => s.with && s.with.name === uploaded);
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

  // The recovery baseline is the only offline copy of production's bytes, so
  // validate must upload it and deploy must download the same artifact. A
  // baseline the deploy job never receives cannot be compared against, and the
  // comparison would fail for the wrong reason - or pass if it were removed.
  const recovery = stepsOf(validate).find(
    (step) => usesStartsWith('actions/upload-artifact@')(step) && step.with && step.with.name === 'release-recovery',
  );
  if (!recovery) {
    failures.push(`${rel}: validate does not upload the release-recovery baseline`);
  } else if (!stepsOf(deploy).some(
    (step) => usesStartsWith('actions/download-artifact@')(step) && step.with && step.with.name === 'release-recovery',
  )) {
    failures.push(`${rel}: deploy does not download release-recovery, so the production bytes it publishes cannot be verified`);
  }

  const payloadDownload = downloads.find((s) => normalise(s.with && s.with.path) === normalise(hostingDir));
  if (!payloadDownload) {
    failures.push(
      `${rel}: no download step places an artifact in "${hostingDir}", which hosting serves`,
    );
    return;
  }
  if (normalise(payloadDownload.with.name) !== normalise(uploaded)) {
    failures.push(
      `${rel}: deploy fills "${hostingDir}" from "${payloadDownload.with.name}" but validate uploads "${uploaded}"`,
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
  // The guard must run before the upload, in the step that asserts the payload
  // about to be published. Matching a guard and a deploy independently lets any
  // step that hashes something and says manifest.json satisfy the check while
  // the real deploy stays unguarded, so the deploy step is located first and
  // the guard has to sit in an earlier step AND verify the same manifest path
  // that the deploy publishes.
  const shells = deploySteps.map((step) => shellLines(step));
  const deployStops = shells
    .map((lines, i) => (lines.some(isDeployLine) ? i : -1))
    .filter((i) => i >= 0);
  if (deployStops.length !== 1) {
    failures.push(
      `${rel}: expected exactly one deploy step running a firebase deploy command, found ${deployStops.length}`,
    );
    return;
  }
  const deployAt = deployStops[0];
  // The guard must compare the APK's digest with the digest recorded in the
  // manifest it publishes: hashing "$APK", grepping that hash out of the
  // payload's own manifest.json, and refusing when the manifest lacks it. The
  // guard may sit in an earlier step, or earlier in the deploy step's own run
  // block; either way its refusal must come before the deploy line.
  const payloadManifest = `${normalise(hostingDir)}/manifest.json`;
  const guardAt = shells.findIndex((lines, i) =>
    isPayloadGuard(lines, payloadManifest) && isBeforeDeploy(lines, i, deployAt),
  );
  if (guardAt < 0) {
    failures.push(
      `${rel}: no deploy step re-checks the payload APK digest against ${payloadManifest} before publishing`,
    );
  }
}

// Shell lines of a step's run block, with comments dropped: a commented-out
// `firebase deploy` or a comment quoting the refusal must not count as either.
function shellLines(step) {
  return String((step && step.run) || '')
    .split('\n')
    .filter((line) => !/^\s*#/.test(line));
}

// True when this run block hashes "$APK", greps "$SHA" out of the payload's
// manifest.json, and refuses when the manifest does not carry it. The digest
// grep must read the manifest through the DIR in force at that line; a literal
// path (including the recovery baseline used by the step above) never counts,
// and a block without a resolvable, exact payload DIR fails closed.
function isPayloadGuard(lines, payloadManifest) {
  const digestAt = lines.findIndex((line) =>
    /grep[^\n]*"\$SHA"[^\n]*\$(\{)?DIR(\})?\/manifest\.json/.test(line),
  );
  if (digestAt < 0) return false;
  // The DIR the grep reads is the last assignment before it; one that comes
  // after the grep has no effect on it. Compare it to the hosting directory
  // exactly - ota/public-backup is a different directory, not a prefix match.
  const dir = dirBefore(lines, digestAt);
  if (dir !== hostingDirOf(payloadManifest)) return false;
  return (
    lines.some((line) => /sha256sum[^\n]*"\$APK"/.test(line) && /SHA=/.test(line))
    && lines.some((line) => line.includes('does not carry the sha256'))
    // A digest compared against the recovery baseline or any other literal path
    // is a different check, however it is worded.
    && !lines.some((line) => /grep[^\n]*"\$SHA"[^\n]*recovery-baseline/.test(line))
  );
}

// The literal directory the last `DIR=` assignment before `index` sets, with a
// `${SUBDIR:+/$SUBDIR}` suffix removed so a channel-aware assignment resolves to
// the directory hosting serves. Returns null when that cannot be determined.
function dirBefore(lines, index) {
  let value = null;
  for (let i = 0; i < index; i += 1) {
    const assign = lines[i].match(/^\s*(?:export\s+)?DIR=(.+)$/);
    if (assign) value = assign[1].trim().replace(/^["']|["']$/g, '');
  }
  if (!value) return null;
  const resolved = value.replace(/\$\{SUBDIR:\+\/?\$SUBDIR\}$/, '');
  return /\$/.test(resolved) ? null : resolved.replace(/\/+$/, '');
}

// The guard must run before the publish: in an earlier step, or earlier in the
// deploy step's own run block than the deploy line.
function isBeforeDeploy(lines, index, deployAt) {
  if (index < deployAt) return true;
  if (index > deployAt) return false;
  const deployLine = lines.findIndex(isDeployLine);
  // The guard's own refusal - the one following the $SHA grep, not the earlier
  // manifest-path refusal.
  const digestAt = lines.findIndex((line) => /grep[^\n]*"\$SHA"[^\n]*\$(\{)?DIR(\})?\/manifest\.json/.test(line));
  const refusal = lines.findIndex((line, i) => i > digestAt && line.includes('does not carry the sha256'));
  return deployLine >= 0 && refusal >= 0 && refusal < deployLine;
}

function hostingDirOf(payloadManifest) {
  return payloadManifest.replace(/\/manifest\.json$/, '');
}

// A deploy is a command line invoking firebase-tools or `firebase deploy`;
// comments are stripped before this runs so a commented-out deploy cannot count.
function isDeployLine(line) {
  // [ \t] rather than \s: \s matches a newline, which would make the whole run
  // block one "line" and put the deploy before the guard.
  return /\bnpx\b[^\n]*firebase-tools(@\S+)?[^\n]*[ \t]deploy\b|\bfirebase[ \t]+deploy\b/.test(line);
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
