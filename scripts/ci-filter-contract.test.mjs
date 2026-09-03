import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
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
  ['example/src/App.tsx', ['shared', 'code'], []],
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
