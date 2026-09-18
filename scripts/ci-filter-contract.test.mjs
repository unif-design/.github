import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { spawnSync } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const workflowPath = process.argv[2]
  ? resolve(process.cwd(), process.argv[2])
  : resolve(scriptDirectory, '../templates/workflows/ci.yml');
const template = readFileSync(workflowPath, 'utf8');
const block = template.match(/          filters: \|\n([\s\S]*?)\n\n  lint:/);

assert.ok(block, 'CI 模板缺少可解析的 paths-filter block');

const filters = new Map();
let currentFilter;

for (const line of block[1].split('\n')) {
  const header = /^            ([a-z][a-z0-9_-]*):$/.exec(line);
  if (header != null) {
    currentFilter = header[1];
    filters.set(currentFilter, []);
    continue;
  }

  const item = /^              - '([^']+)'/.exec(line);
  if (item != null && currentFilter != null) {
    filters.get(currentFilter).push(item[1]);
  }
}

function globToRegExp(glob) {
  const globstar = '\u0000';
  const escaped = glob
    .replace(/[.+^${}()|[\]\\]/g, '\\$&')
    .replaceAll('**', globstar)
    .replaceAll('*', '[^/]*')
    .replaceAll(globstar, '.*');
  return new RegExp(`^${escaped}$`);
}

function matches(filterName, inputPath) {
  const patterns = filters.get(filterName);
  assert.ok(patterns, `CI 模板缺少 ${filterName} filter`);
  const positivePatterns = patterns.filter((pattern) => !pattern.startsWith('!'));
  const excludedPatterns = patterns
    .filter((pattern) => pattern.startsWith('!'))
    .map((pattern) => pattern.slice(1));
  return (
    positivePatterns.some((pattern) => globToRegExp(pattern).test(inputPath)) &&
    !excludedPatterns.some((pattern) => globToRegExp(pattern).test(inputPath))
  );
}

const cases = [
  ['example/src/App.tsx', ['shared', 'code', 'website'], []],
  ['example/android/app/build.gradle', ['shared', 'code'], []],
  ['example/babel.config.js', ['shared', 'code'], []],
  ['src/index.ts', ['js', 'website', 'code'], []],
  ['src/__tests__/index.test.ts', ['code'], ['js', 'website', 'shared']],
  [
    'example/src/__tests__/componentCatalog.test.ts',
    ['code'],
    ['shared', 'js', 'website'],
  ],
  ['scripts/__tests__/cache.test.mjs', ['code'], ['shared']],
  ['example/README.md', ['website'], ['shared', 'code']],
  ['README.md', ['website'], ['shared', 'code']],
  ['eslint.config.mjs', ['code'], ['shared']],
  ['jest.setup.ts', ['code'], ['shared']],
  ['.yarnrc.yml', ['shared', 'code', 'website'], []],
  ['.yarn/releases/yarn-4.11.0.cjs', ['shared', 'code', 'website'], []],
];

for (const [inputPath, expectedFilters, excludedFilters] of cases) {
  for (const filterName of expectedFilters) {
    assert.equal(
      matches(filterName, inputPath),
      true,
      `${inputPath} 必须命中 ${filterName} filter`
    );
  }
  for (const filterName of excludedFilters) {
    assert.equal(
      matches(filterName, inputPath),
      false,
      `${inputPath} 不得命中 ${filterName} filter`
    );
  }
}

console.log('PASS: shared CI path-filter contract');

// 执行工作流的真实检测脚本，覆盖新库、空目录和已接入的 website。
const detector = template.match(/      - name: Detect website workspace\n        id: project\n        run: \|\n([\s\S]*?)        shell: bash/);
assert.ok(detector, '缺少 website workspace 检测步骤');
const detectorScript = detector[1].split('\n').map(line => line.replace(/^          /, '')).join('\n');
const fixture = mkdtempSync(resolve(tmpdir(), 'unif-ci-website-'));
try {
  const output = resolve(fixture, 'output');
  const check = expected => {
    writeFileSync(output, '');
    const result = spawnSync('bash', ['-e', '-c', detectorScript], { cwd: fixture, env: { ...process.env, GITHUB_OUTPUT: output }, encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(readFileSync(output, 'utf8').trim(), `has_website=${expected}`);
  };
  check(false);
  mkdirSync(resolve(fixture, 'website'));
  check(false);
  writeFileSync(resolve(fixture, 'website/package.json'), '{"name":"site"}');
  check(true);
} finally {
  rmSync(fixture, { recursive: true, force: true });
}
console.log('PASS: optional website workspace contract');

// 文档站会消费原生 example 的组合示例，CI 与实际部署必须使用一致的输入。
const deployTemplate = readFileSync(resolve(scriptDirectory, '../templates/workflows/deploy-docs.yml'), 'utf8');
const deployPaths = deployTemplate.split('  workflow_dispatch:')[0].split('    paths:')[1];
assert.ok(deployPaths, 'docs deploy 缺少 push paths');
filters.set('deploy', [...deployPaths.matchAll(/^      - '([^']+)'/gm)].map(match => match[1]));
assert.equal(matches('deploy', 'example/src/examples/MainChatExample/MainChatExample.tsx'), true);
assert.equal(matches('deploy', 'example/src/__tests__/Composition.test.tsx'), false);
assert.equal(matches('deploy', 'example/src/examples/Foo/__tests__/Foo.test.tsx'), false);
console.log('PASS: shared example documentation consumers');
