const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  mkdtempSync,
  mkdirSync,
  writeFileSync,
  readFileSync,
  rmSync,
} = require('node:fs');
const { tmpdir } = require('node:os');
const { join, resolve } = require('node:path');
const { execFileSync, spawnSync } = require('node:child_process');
const script = resolve(
  __dirname,
  '../templates/actions/changes/classify-package.cjs'
);

function fixture(run) {
  const root = mkdtempSync(join(tmpdir(), 'unif-ci-manifest-'));
  const git = (...args) =>
    execFileSync('git', args, {
      cwd: root,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    }).trim();
  try {
    git('init', '-q');
    git('config', 'user.name', 'CI Fixture');
    git('config', 'user.email', 'ci@example.invalid');
    git('config', 'commit.gpgsign', 'false');
    git('config', 'core.hooksPath', join(root, 'no-hooks'));
    const initial = {
      name: '@unif/fixture',
      version: '1.0.0',
      description: 'old',
      dependencies: { react: '19.2.3' },
      scripts: { build: 'node build.js' },
    };
    const commit = (value, file = 'package.json') => {
      mkdirSync(join(root, 'example'), { recursive: true });
      writeFileSync(
        join(root, file),
        typeof value === 'string' ? value : JSON.stringify(value)
      );
      git('add', file);
      git('commit', '-qm', 'fixture');
      return git('rev-parse', 'HEAD');
    };
    const before = commit(initial);
    const classify = (event, name) => {
      const input = join(root, 'event.json'),
        output = join(root, 'output');
      writeFileSync(input, JSON.stringify(event));
      writeFileSync(output, '');
      const result = spawnSync(process.execPath, [script], {
        cwd: root,
        encoding: 'utf8',
        env: {
          ...process.env,
          GITHUB_EVENT_PATH: input,
          GITHUB_EVENT_NAME: name,
          GITHUB_OUTPUT: output,
        },
      });
      assert.equal(result.status, 0, result.stderr);
      return readFileSync(output, 'utf8').trim();
    };
    run({ root, git, initial, before, commit, classify });
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

for (const eventName of ['push', 'pull_request', 'merge_group']) {
  test(`${eventName}: presentation-only edits skip runtime`, () =>
    fixture(({ initial, before, commit, classify }) => {
      const after = commit({
        ...initial,
        description: 'new',
        keywords: ['docs'],
        homepage: 'https://example.invalid',
      });
      const event =
        eventName === 'push'
          ? { before, after }
          : eventName === 'pull_request'
            ? { pull_request: { base: { sha: before }, head: { sha: after } } }
            : { merge_group: { base_sha: before, head_sha: after } };
      assert.equal(classify(event, eventName), 'runtime=false');
    }));
}
for (const [field, value] of [
  ['dependencies', { react: '20' }],
  ['scripts', { build: 'new-command' }],
  ['codegenConfig', { name: 'NewSpec' }],
  ['version', '2.0.0'],
  ['unknownInput', true],
]) {
  test(`${field} remains a shared runtime input`, () =>
    fixture(({ initial, before, commit, classify }) => {
      const after = commit({
        ...initial,
        description: 'also changed',
        [field]: value,
      });
      assert.equal(classify({ before, after }, 'push'), 'runtime=true');
    }));
}
test('example metadata is separate from example dependencies', () =>
  fixture(({ commit, classify }) => {
    const original = { name: 'example', dependencies: { react: '19' } };
    const before = commit(original, 'example/package.json');
    const metadata = commit(
      { ...original, description: 'new' },
      'example/package.json'
    );
    assert.equal(
      classify({ before, after: metadata }, 'push'),
      'runtime=false'
    );
    const after = commit(
      { ...original, dependencies: { react: '20' } },
      'example/package.json'
    );
    assert.equal(classify({ before: metadata, after }, 'push'), 'runtime=true');
  }));
test('PR comparison uses the merge base, not unrelated main changes', () =>
  fixture(({ git, initial, before, commit, classify }) => {
    git('checkout', '-qb', 'new-base');
    const base = commit({ ...initial, dependencies: { react: '20' } });
    git('checkout', '-qb', 'pr', before);
    const head = commit({ ...initial, description: 'new' });
    assert.equal(
      classify(
        { pull_request: { base: { sha: base }, head: { sha: head } } },
        'pull_request'
      ),
      'runtime=false'
    );
  }));
test('invalid JSON and missing comparison commits conservatively validate runtime', () =>
  fixture(({ before, commit, classify }) => {
    const after = commit('{');
    assert.equal(classify({ before, after }, 'push'), 'runtime=true');
    assert.equal(
      classify({ before: '0'.repeat(40), after }, 'push'),
      'runtime=true'
    );
    assert.equal(
      classify({ before: '1'.repeat(40), after }, 'push'),
      'runtime=true'
    );
    assert.equal(classify({}, 'workflow_dispatch'), 'runtime=true');
  }));
test('manifest removal does not become metadata-only', () =>
  fixture(({ git, before, classify }) => {
    git('rm', 'package.json');
    git('commit', '-qm', 'remove');
    assert.equal(
      classify({ before, after: git('rev-parse', 'HEAD') }, 'push'),
      'runtime=true'
    );
  }));

test('conditional export key order remains a runtime change', () =>
  fixture(({ initial, commit, classify }) => {
    const before = commit({
      ...initial,
      exports: { '.': { source: './src/index.ts', default: './lib/index.js' } },
    });
    const after = commit({
      ...initial,
      exports: { '.': { default: './lib/index.js', source: './src/index.ts' } },
    });
    assert.equal(classify({ before, after }, 'push'), 'runtime=true');
  }));
