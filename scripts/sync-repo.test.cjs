const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { test } = require('node:test');

const scripts = __dirname;
function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'unif-onboarding-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  fs.writeFileSync(path.join(root, 'package.json'), JSON.stringify({
    name: '@unif/react-native-fixture', version: '0.1.0', private: true,
    devDependencies: { turbo: '1', '@release-it/conventional-changelog': '1' },
    'release-it': { npm: { publish: true, skipChecks: true } },
  }));
  return root;
}
function sync(root, check = false) {
  return spawnSync('bash', [path.join(scripts, 'sync-repo.sh'),
    ...(check ? ['--check'] : []), 'react-native-fixture', root], { encoding: 'utf8' });
}
function snapshot(root) {
  return fs.readdirSync(root, { recursive: true }).sort().filter(name =>
    fs.statSync(path.join(root, name)).isFile()
  ).map(name => [name, fs.readFileSync(path.join(root, name), 'utf8')]);
}
function lintWorkflows(root) {
  const files = fs.readdirSync(path.join(root, '.github/workflows'))
    .filter(name => name.endsWith('.yml')).map(name => path.join(root, '.github/workflows', name));
  const result = spawnSync(process.env.ACTIONLINT || 'actionlint',
    ['-shellcheck=shellcheck', ...files], { cwd: root, encoding: 'utf8' });
  assert.equal(result.status, 0, result.stdout + result.stderr + (result.error || ''));
}
test('new RN library receives real generic entrypoints and supports a read-only check', t => {
  const root = fixture(t);
  const first = sync(root);
  assert.equal(first.status, 0, first.stdout + first.stderr);
  const agents = fs.readFileSync(path.join(root, 'AGENTS.md'), 'utf8');
  assert.match(agents, /code-development/);
  assert.doesNotMatch(agents, /unif-fixture/);
  assert.ok(fs.existsSync(path.join(root, '.github/scripts/check-library.cjs')));
  lintWorkflows(root);
  const before = snapshot(root);
  const checked = sync(root, true);
  assert.equal(checked.status, 0, checked.stdout + checked.stderr);
  assert.deepEqual(snapshot(root), before);
});
test('check detects managed drift and stale automation without modifying either', t => {
  const root = fixture(t);
  assert.equal(sync(root).status, 0);
  fs.appendFileSync(path.join(root, '.github/workflows/ci.yml'), '\n# drift\n');
  fs.writeFileSync(path.join(root, '.github/dependabot.yaml'), 'version: 2\n');
  const before = snapshot(root);
  const checked = sync(root, true);
  assert.notEqual(checked.status, 0);
  assert.match(checked.stdout + checked.stderr, /ci\.yml/);
  assert.match(checked.stdout + checked.stderr, /dependabot\.yaml/);
  assert.deepEqual(snapshot(root), before);
});
test('new RN website gets shared llms sources and missing workflow dependencies fail', t => {
  const root = fixture(t);
  fs.mkdirSync(path.join(root, 'website/scripts'), { recursive: true });
  fs.writeFileSync(path.join(root, 'website/scripts/build-llms.test.js'), '// local checks\n');
  const first = sync(root);
  assert.equal(first.status, 0, first.stdout + first.stderr);
  assert.ok(fs.existsSync(path.join(root, 'website/scripts/llms/bundle.js')));
  assert.ok(fs.existsSync(path.join(root, '.github/workflows/deploy-docs.yml')));
  lintWorkflows(root);
  const pkg = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
  delete pkg.devDependencies.turbo;
  fs.writeFileSync(path.join(root, 'package.json'), JSON.stringify(pkg));
  const before = snapshot(root);
  const checked = sync(root, true);
  assert.notEqual(checked.status, 0);
  assert.match(checked.stdout + checked.stderr, /turbo/);
  assert.deepEqual(snapshot(root), before);
});

test('documentation verification rejects HTTP 200 for an old version and accepts the built version', t => {
  const root = fixture(t);
  const template = fs.readFileSync(path.join(scripts, '../templates/workflows/deploy-docs.yml'), 'utf8');
  const marker = template.indexOf('      - name: Verify public documentation');
  assert.notEqual(marker, -1);
  const run = template.slice(template.indexOf('        run: |\n', marker) + '        run: |\n'.length)
    .split('\n').map(line => line.replace(/^          /, '')).join('\n');
  const bin = path.join(root, 'bin');
  fs.mkdirSync(bin);
  fs.writeFileSync(path.join(bin, 'curl'), `#!/usr/bin/env node
const fs = require('node:fs');
const args = process.argv.slice(2);
const output = args[args.indexOf('--output') + 1];
fs.writeFileSync(output, process.env.INDEX_TEXT);
if (args.some(arg => arg.endsWith('/llms.txt'))) fs.appendFileSync(process.env.CALL_LOG, 'index\\n');
`, { mode: 0o755 });
  fs.writeFileSync(path.join(bin, 'sleep'), '#!/bin/sh\nexit 0\n', { mode: 0o755 });
  const log = path.join(root, 'requests');
  for (const [text, status, requests] of [
    ['文档构建依据：`@unif/react-native-fixture@0.0.9`；', 1, 5],
    ['文档构建依据：`@unif/react-native-fixture@0.1.0-rc.1`；', 1, 5],
    ['文档构建依据：`@unif/react-native-fixture@0.1.0`；', 0, 1],
  ]) {
    fs.writeFileSync(log, '');
    const result = spawnSync('bash', ['-e', '-c', run], { encoding: 'utf8', env: {
      ...process.env, PATH: `${bin}${path.delimiter}${process.env.PATH}`,
      PAGE_URL: 'https://unif-design.github.io/react-native-fixture/',
      EXPECTED_PACKAGE: '@unif/react-native-fixture@0.1.0', INDEX_TEXT: text, CALL_LOG: log,
    } });
    assert.equal(result.status, status, result.stdout + result.stderr);
    assert.equal(fs.readFileSync(log, 'utf8').trim().split('\n').length, requests);
  }
});
