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
