// Proves tool/validate_yaml.js fails closed on the OTA pre-publish APK guard.
//
//   node tool/test_validate_yaml_ota_guard.js
//
// Each case copies ota-publish.yml into an isolated temp tree, applies one
// mutation and runs the real validator there. Removing the pre-publish
// digest-vs-manifest refusal must make it exit non-zero, and a sha256sum next to
// manifest.json somewhere else must not be able to stand in for it.

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const WORKFLOW = '.github/workflows/ota-publish.yml';
const ASSERT_STEP = 'Assert the payload is the one that will be published';
const isDeployLine = (line) => /\bnpx\b[^\n]*firebase-tools(@\S+)?[^\n]*[ \t]deploy\b|\bfirebase[ \t]+deploy\b/.test(line);

function linesOf(text) {
  return text.replace(/\r\n/g, '\n').split('\n');
}

function removeRange(lines, start, end) {
  return lines.slice(0, start).concat(lines.slice(end));
}

function bodyRange(body, from, to) {
  const start = body.findIndex((line) => line.includes(from));
  const stop = body.findIndex((line) => line.includes(to));
  if (start < 0 || stop < start) throw new Error(`fixture drift: ${from} .. ${to}`);
  return [start, stop + 1];
}

// The guard is the refusal block that runs from the APK digest to the line
// that reports the publish. The block is delimited by its own `if ... fi`, so
// mutating it keeps the sibling manifest-path check and leaves the rest of the
// step's shell valid - a mutant that does not parse would be rejected by the
// YAML parser before the digest predicate is ever consulted.
const GUARD_BLOCK = ['SHA="$(sha256sum "$APK"', 'echo "Publishing $DIR/manifest.json'];
const guardRange = (body) => {
  const [start, end] = bodyRange(body, ...GUARD_BLOCK);
  // bodyRange is exclusive, so end - 1 is the publish line and the guard's
  // closing `fi` is the line before it.
  return [start, end - 1];
};

const steppedRun = (lines, stepNeedle) => {
  const stepAt = lines.findIndex((line) => line.includes(stepNeedle));
  const runAt = lines.findIndex((line, i) => i > stepAt && /^\s+run: \|$/.test(line));
  const end = lines.findIndex((line, i) => i > runAt && /^ {6}- /.test(line));
  if (stepAt < 0 || runAt < 0 || end < 0) throw new Error(`fixture drift: no run block for ${stepNeedle}`);
  // A blank line ends a YAML block scalar, so it belongs to the step, not the shell.
  const body = lines.slice(runAt + 1, end);
  const blankAt = body.findIndex((line) => line.trim() === '');
  return { runAt, end, shell: blankAt < 0 ? body : body.slice(0, blankAt), tail: blankAt < 0 ? [] : body.slice(blankAt) };
};

function mutateWorkflow(bytes) {
  const source = fs.readFileSync(path.join(ROOT, WORKFLOW), 'utf8');
  const lines = linesOf(source);
  const assert = steppedRun(lines, `- name: ${ASSERT_STEP}`);
  const next = bytes(assert.shell).concat(assert.tail);
  const text = lines
    .slice(0, assert.runAt + 1)
    .concat(
      next.map((line) => (line ? `          ${line}` : line)),
    )
    .concat(lines.slice(assert.end))
    .join('\n');
  if (text === source) throw new Error('mutation did not change the workflow');
  return text;
}

// Removes the guard from the assert step, then adds `step` (already indented as
// a workflow step) immediately before the deploy step. The guard now sits after
// the assert step, so it is only ever reached after the publish.
function guardAfterAssert(step) {
  const lines = linesOf(fs.readFileSync(path.join(ROOT, WORKFLOW), 'utf8'));
  const assert = steppedRun(lines, `- name: ${ASSERT_STEP}`);
  const assertShell = removeRange(assert.shell, ...guardRange(assert.shell));
  const withoutGuard = lines
    .slice(0, assert.runAt + 1)
    .concat(assertShell.map((line) => `          ${line}`), assert.tail, lines.slice(assert.end));
  const deploy = steppedRun(withoutGuard, '- name: Deploy hosting');
  // This step's header is seven lines above its run block: name, three comment
  // lines, env, FIREBASE_TOKEN, run.
  const stepAt = deploy.runAt - 7;
  if (!String(withoutGuard[stepAt]).includes('- name: Deploy hosting')) {
    throw new Error('fixture drift: deploy step header');
  }
  return withoutGuard
    .slice(0, stepAt)
    .concat(step)
    .concat(withoutGuard.slice(stepAt))
    .join('\n');
}

const guardStep = (name) => {
  const lines = linesOf(fs.readFileSync(path.join(ROOT, WORKFLOW), 'utf8'));
  const assert = steppedRun(lines, `- name: ${ASSERT_STEP}`);
  const guard = assert.shell.slice(...guardRange(assert.shell));
  return ['      - name: ' + name, '        run: |', ...guard.map((line) => `          ${line}`), ''];
};

// Moves the real guard into its own step after the assert, before the deploy.
const moveGuardAfterAssert = () => guardAfterAssert(guardStep('Re-check the payload digest'));

// The assert step loses its guard, and a step between it and the deploy carries
// a near-copy. Only a copy that resolves its manifest through the step's own DIR
// is accepted as an equivalent guard; every other shape must fail.
//
// OTA_GUARD_WEAKEN_DECOY drops the hash line, proving that an accepted decoy
// fails loudly once it stops verifying "$APK".
const decoyBeforeDeploy = (overrides = {}) => {
  // `in` rather than `??`: an explicit null means "no DIR assignment at all".
  const dir = 'dir' in overrides ? overrides.dir : 'ota/public${SUBDIR:+/$SUBDIR}';
  const grep = 'grep' in overrides ? overrides.grep : 'grep -qF "$SHA" "$DIR/manifest.json"';
  const weaken = process.env.OTA_GUARD_WEAKEN_DECOY === '1';
  const hash = weaken ? [] : [`SHA="$(sha256sum "$APK" | cut -d' ' -f1)"`];
  return guardAfterAssert([
    '      - name: Check the pinned channel',
    '        # npx --yes firebase-tools@13.35.1 deploy would publish this',
    '        run: |',
    ...(dir === null ? [] : [`          DIR="${dir}"`]),
    ...hash.map((line) => `          ${line}`),
    `          if ! ${grep}; then`,
    '            echo "::error::manifest.json does not carry the sha256 of releases/$APK_NAME; refusing to publish"',
    '            exit 1',
    '          fi',
    '',
  ]);
};

// The deploy step itself carries the guard: the guard runs with the upload.
const guardOnlyInDeployStep = () => {
  const lines = linesOf(fs.readFileSync(path.join(ROOT, WORKFLOW), 'utf8'));
  const assert = steppedRun(lines, `- name: ${ASSERT_STEP}`);
  const guard = assert.shell.slice(...guardRange(assert.shell));
  const assertShell = removeRange(assert.shell, ...guardRange(assert.shell));
  const withoutGuard = lines
    .slice(0, assert.runAt + 1)
    .concat(assertShell.map((line) => `          ${line}`), assert.tail, lines.slice(assert.end));
  const deploy = steppedRun(withoutGuard, '- name: Deploy hosting');
  // `guard` lines are already indented as run-block content, like `deploy.shell`.
  return withoutGuard
    .slice(0, deploy.runAt + 1)
    .concat(guard, deploy.shell, deploy.tail)
    .concat(withoutGuard.slice(deploy.end))
    .join('\n');
};

// The payload DIR the guard assigns; a suffix such as ${SUBDIR:+/$SUBDIR} keeps
// the same directory for production and resolves to ota/public.
const PAYLOAD_DIR = 'DIR="ota/public${SUBDIR:+/$SUBDIR}"';

// Rewrites the payload DIR line and keeps the guard's grep reading it.
const retargetGuard = (assignment) => (body) =>
  body.map((line) => (line.trim() === PAYLOAD_DIR ? `            ${assignment}` : line));

// Stray DIR-like lines before the real payload DIR. `DIR_BACKUP=` is not an
// assignment at all, and `export DIR=recovery-baseline` is overridden by the
// later payload assignment, so the guard still verifies the payload and passes.
// A stray after the payload DIR would be the one the grep reads, so it is the
// copy that must fail - covered by the DIR-unresolvable and retargeted cases.
const strayDirBefore = (body) => {
  const at = body.findIndex((line) => line.trim() === PAYLOAD_DIR);
  if (at < 0) throw new Error('fixture drift: no payload DIR line');
  return body
    .slice(0, at)
    .concat(['            DIR_BACKUP="ota/recovery-baseline"'], ['            export DIR="ota/recovery-baseline"'])
    .concat(body.slice(at));
};

// Turns the guard step itself into the deploy step, with its refusal before the
// deploy line: exactly one deploy step, whose guard runs too late.
const deployLineAfterGuard = () => {
  // The guard step gets a deploy command right after its refusal and keeps
  // every other step as-is; the validator rejects the second deploy outright,
  // so the refusal has to be what makes this fail. See the same-step ordered
  // case below for the shape that must pass.
  const lines = linesOf(fs.readFileSync(path.join(ROOT, WORKFLOW), 'utf8'));
  const guardStep = steppedRun(lines, `- name: ${ASSERT_STEP}`);
  const digest = guardStep.shell.findIndex((line) => /grep[^\n]*"\$SHA"/.test(line));
  const refusalEnd = guardStep.shell.findIndex((line, i) => line.trim() === 'fi' && i > digest);
  if (refusalEnd < 0) throw new Error('fixture drift: no guard fi');
  const shell = guardStep.shell
    .slice(0, refusalEnd + 1)
    .concat(
      [`${guardStep.shell[refusalEnd].match(/^\s*/)[0]}npx --yes firebase-tools@13.35.1 deploy --token "$FIREBASE_TOKEN" --non-interactive`],
      guardStep.shell.slice(refusalEnd + 1),
    );
  return lines
    .slice(0, guardStep.runAt + 1)
    .concat(shell.map((line) => `          ${line}`), guardStep.tail, lines.slice(guardStep.end))
    .join('\n');
};

// A guard inside the deploy step itself, ahead of the deploy line: the one
// same-step shape that is legitimate.
const guardOrderedInsideDeployStep = () => {
  const lines = linesOf(fs.readFileSync(path.join(ROOT, WORKFLOW), 'utf8'));
  const assert = steppedRun(lines, `- name: ${ASSERT_STEP}`);
  // Both the DIR assignment and the guard sit inside the deploy step's run block.
  const guard = ['          DIR="ota/public"'].concat(assert.shell.slice(...guardRange(assert.shell)));
  const assertShell = removeRange(assert.shell, ...guardRange(assert.shell));
  const withoutGuard = lines
    .slice(0, assert.runAt + 1)
    .concat(assertShell.map((line) => `          ${line}`), assert.tail, lines.slice(assert.end));
  const deploy = steppedRun(withoutGuard, '- name: Deploy hosting');
  return withoutGuard
    .slice(0, deploy.runAt + 1)
    .concat(guard, deploy.shell, deploy.tail)
    .concat(withoutGuard.slice(deploy.end))
    .join('\n');
};

const cases = [
  {
    name: 'authentic pre-publish guard passes',
    expectPass: true,
    bytes: (body) => body,
  },
  {
    name: 'pre-publish digest guard removed, manifest-path check kept',
    expectPass: false,
    mustParse: true,
    bytes: (body) => removeRange(body, ...guardRange(body)),
  },
  {
    name: 'only the recovery-baseline sha256sum --check remains',
    expectPass: false,
    mustParse: true,
    bytes: (body) => {
      const without = removeRange(body, ...guardRange(body));
      return removeRange(without, ...bodyRange(without, 'cmp --silent ota/recovery-baseline/manifest.json', 'PRODUCTION_MANIFEST_ALTERED'));
    },
  },
  {
    name: 'guard retained only after the firebase deploy',
    expectPass: false,
    mustParse: true,
    text: moveGuardAfterAssert,
  },
  {
    // KNOWN LIMITATION, accepted deliberately: a step that re-derives the same
    // DIR from firebase.json and verifies "$APK" against it is indistinguishable
    // from the assert step the deploy consumes. Such an equivalent is expected
    // through; a copy that does not resolve DIR the same way must fail (below).
    name: 'decoy resolving its own DIR (known limitation: accepted)',
    acceptKnown: {
      rejection: 'pass',
      requires: [/sha256sum[^\n]*"\$APK"/, /grep[^\n]*"\$SHA"[^\n]*\$(\{)?DIR(\})?\/manifest\.json/],
    },
    text: decoyBeforeDeploy,
  },
  {
    name: 'guard comparing the recovery-baseline manifest instead of the payload',
    expectPass: false,
    mustParse: true,
    text: () => decoyBeforeDeploy({ grep: 'grep -qF "$SHA" ota/recovery-baseline/manifest.json' }),
  },
  {
    name: 'guard step whose DIR cannot be resolved',
    expectPass: false,
    mustParse: true,
    text: () => decoyBeforeDeploy({ dir: null }),
  },
  {
    name: 'guard step whose DIR is not the payload directory',
    expectPass: false,
    mustParse: true,
    text: () => decoyBeforeDeploy({ dir: 'ota/elsewhere' }),
  },
  {
    name: 'stray DIR-like assignments before the real payload DIR',
    expectPass: true,
    bytes: strayDirBefore,
  },
  {
    name: 'retargeted guard DIR="ota/publicx"',
    expectPass: false,
    mustParse: true,
    bytes: retargetGuard('DIR="ota/publicx"'),
  },
  {
    name: 'retargeted guard DIR="ota/public-backup"',
    expectPass: false,
    mustParse: true,
    bytes: retargetGuard('DIR="ota/public-backup"'),
  },
  {
    name: 'deploy line added after the guard refusal inside its step',
    expectPass: false,
    mustParse: true,
    // The added command makes two deploy steps, so the unique-deploy rule fires
    // first; the ordering rule is covered by the same-step cases around it.
    expectReason: /exactly one deploy step/,
    text: deployLineAfterGuard,
  },
  {
    name: 'guard inside the deploy step, before the deploy line',
    expectPass: true,
    text: guardOrderedInsideDeployStep,
  },
  {
    name: 'guard only inside the deploy step, not before it',
    expectPass: false,
    mustParse: true,
    text: guardOnlyInDeployStep,
  },
  {
    name: 'required refusal wording missing',
    expectPass: false,
    mustParse: true,
    bytes: (body) =>
      body.map((line) => line.replace('does not carry the sha256', 'does not carry a matching digest')),
  },
  {
    name: 'unrelated sha256sum + manifest.json only',
    expectPass: false,
    mustParse: true,
    bytes: (body) => {
      const without = removeRange(body, ...guardRange(body));
      const pathCheck = without.findIndex((line) => line.includes('manifest.json does not reference'));
      if (pathCheck < 0) throw new Error('fixture drift: no manifest-path check');
      without[pathCheck] = `${without[pathCheck].match(/^\s*/)[0]}echo "sha256sum $DIR/manifest.json checked"`;
      return without;
    },
  },
  {
    name: 'malformed YAML',
    expectPass: false,
    text: () => `${fs.readFileSync(path.join(ROOT, WORKFLOW), 'utf8')}\n[unclosed\n`,
  },
];

function runValidator(rel, text) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ota-guard-'));
  const target = path.join(dir, rel);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  if (rel === WORKFLOW) fs.copyFileSync(path.join(ROOT, 'firebase.json'), path.join(dir, 'firebase.json'));
  fs.writeFileSync(target, text);
  const result = spawnSync(process.execPath, [path.join(ROOT, 'tool', 'validate_yaml.js')], {
    cwd: dir,
    encoding: 'utf8',
    env: { ...process.env, YAML_ROOT: dir },
  });
  fs.rmSync(dir, { recursive: true, force: true });
  const output = `${result.stdout || ''}${result.stderr || ''}`;
  // What rejected the mutant matters as much as that it was rejected: a mutant
  // the YAML parser refuses never reaches the digest predicate. The validator
  // prints "INVALID YAML" for every failure, so only a line:column parse error
  // counts as a parse rejection.
  const rejection = result.status === 0
    ? 'pass'
    : /\S+:\d+:\d+: (All mapping items must start|cannot|end of the stream|.*expected)/i.test(output)
      ? 'parse'
      : /re-checks the payload APK digest/.test(output)
        ? 'digest guard'
        : 'other';
  return { status: result.status, output, rejection };
}

let failures = 0;
for (const testCase of cases) {
  const rel = testCase.rel || WORKFLOW;
  let status;
  let output;
  let behavior;
  let rejection = '';
  let text;
  try {
    text = testCase.text ? testCase.text() : mutateWorkflow(testCase.bytes);
    ({ status, output, rejection } = runValidator(rel, text));
    if (testCase.acceptKnown) {
      // The accepted mutant must still contain the checks that make it a real
      // guard; if that changes, the accepted behaviour has got worse.
      const verified = testCase.acceptKnown.requires.every((pattern) => pattern.test(text));
      behavior = status === 0 && rejection === testCase.acceptKnown.rejection && verified;
      rejection = verified ? rejection : 'weaker decoy';
      console.log(`  ${behavior ? 'ok  ' : 'FAIL'} ${testCase.name} (exit ${status}, ${rejection})`);
      if (!behavior) failures += 1;
      continue;
    }
    // A mutation that cannot even be built does not test the validator.
    behavior = testCase.expectPass ? status === 0 : status !== 0;
    // A mutant that does not parse is rejected before the digest predicate is
    // consulted, so it cannot stand in for a guard-specific case.
    if (!testCase.expectPass && testCase.mustParse) {
      const reason = testCase.expectReason
        ? testCase.expectReason.test(output)
        : /re-checks the payload APK digest/.test(output);
      behavior = behavior && reason;
    }
  } catch (error) {
    status = 'fixture error';
    output = String(error.message);
    rejection = 'fixture';
    behavior = false;
  }
  console.log(`  ${behavior ? 'ok  ' : 'FAIL'} ${testCase.name} (exit ${status}, ${rejection})`);
  if (!behavior) {
    failures += 1;
    for (const line of output.trim().split('\n').slice(-3)) console.log(`       ${line}`);
  }
}

console.log('');
if (failures > 0) {
  console.error(`${failures} OTA guard case(s) did not behave as required`);
  const inspect = process.env.OTA_GUARD_INSPECT;
  if (inspect) fs.writeFileSync(inspect, mutateWorkflow((body) => body));
  process.exit(1);
}
console.log(`OK: ${cases.length} OTA guard case(s)`);
