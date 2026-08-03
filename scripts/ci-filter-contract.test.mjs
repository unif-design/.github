import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const template = readFileSync(
  resolve(scriptDirectory, '../templates/workflows/ci.yml'),
  'utf8'
);
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
  return patterns.some((pattern) => globToRegExp(pattern).test(inputPath));
}

const cases = [
  ['example/src/App.tsx', ['shared', 'code']],
  ['example/android/app/build.gradle', ['shared', 'code']],
  ['example/babel.config.js', ['shared', 'code']],
  ['.yarnrc.yml', ['shared', 'code', 'website']],
  ['.yarn/releases/yarn-4.11.0.cjs', ['shared', 'code', 'website']],
];

for (const [inputPath, expectedFilters] of cases) {
  for (const filterName of expectedFilters) {
    assert.equal(
      matches(filterName, inputPath),
      true,
      `${inputPath} 必须命中 ${filterName} filter`
    );
  }
}

console.log('PASS: shared CI path-filter contract');
