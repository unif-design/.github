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
const action = readFileSync(resolve(dirname(workflowPath), '../actions/changes/action.yml'), 'utf8');
const block = action.match(/        filters: \|\n([\s\S]*?)\n    - name: Compare package runtime fields/);

assert.ok(block, 'CI 模板缺少可解析的 paths-filter block');

const filters = new Map();
let currentFilter;

for (const line of block[1].split('\n')) {
  const header = /^          ([a-z][a-z0-9_-]*):$/.exec(line);
  if (header != null) {
    currentFilter = header[1];
    filters.set(currentFilter, []);
    continue;
  }

  const item = /^            - '([^']+)'/.exec(line);
  if (item != null && currentFilter != null) {
    filters.get(currentFilter).push(item[1]);
  }
}

function globToRegExp(glob) {
  // The source deliberately uses only literal paths, * and ** globs.
  assert.ok(!/[?{}[\]]/.test(glob), `Unsupported test glob: ${glob}`);
  let expression = '';
  for (let i = 0; i < glob.length; i += 1) {
    if (glob.slice(i, i + 3) === '**/') {
      expression += '(?:.*/)?'; i += 2;
    } else if (glob.slice(i, i + 2) === '**') {
      expression += '.*'; i += 1;
    } else if (glob[i] === '*') {
      expression += '[^/]*';
    } else {
      expression += glob[i].replace(/[.+^$()|\\]/g, '\\$&');
    }
  }
  return new RegExp(`^${expression}$`);
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
  ['example/android/app/build.gradle', ['android', 'code'], ['shared', 'ios']],
  ['example/ios/Podfile', ['ios', 'code'], ['shared', 'android']],
  ['example/Gemfile', ['ios', 'code'], ['shared', 'android']],
  ['scripts/verify-ios-integration.mjs', ['ios', 'code'], ['shared', 'android']],
  ['scripts/verify-android-integration.mjs', ['android', 'code'], ['shared', 'ios']],
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
  ['ios/Feature.mm', ['ios', 'code'], ['shared', 'android']],
  ['android/src/main/Feature.kt', ['android', 'code'], ['shared', 'ios']],
  ['ios/README.md', [], ['ios', 'shared', 'code']],
  ['website/docs/intro.md', ['website'], ['shared', 'code', 'ios', 'android']],
  ['website/scripts/build-llms.js', ['website'], ['shared', 'code']],
  ['scripts/verify-agent-instructions.mjs', ['code', 'tooling'], ['shared', 'ios', 'android']],
  ['scripts/verify-native-contract.mjs', ['shared', 'code'], []],
  ['scripts/build-icons.js', ['shared', 'code'], []],
  ['scripts/new-build-input.js', ['shared', 'code'], []],
  ['package.json', ['manifest', 'website'], ['shared', 'code']],
  ['example/package.json', ['manifest'], ['shared', 'code', 'example']],
  ['.github/ci/ios.sh', ['ios', 'code'], ['android', 'shared']],
  ['.github/ci/android.sh', ['android', 'code'], ['ios', 'shared']],
  ['type-tests/public-api.tsx', ['code'], ['shared', 'ios', 'android', 'js']],
  ['example/GUIDE.md', [], ['shared', 'code', 'ios', 'android']],
  ['scripts/README.md', [], ['shared', 'code', 'tooling']],
  ['.github/actions/changes/README.md', [], ['shared', 'code']],
  ['example/jest.config.js', ['code', 'example'], ['shared', 'ios', 'android']],
  ['example/jest.forbidOnlyReporter.js', ['code', 'example'], ['shared', 'ios', 'android']],
  ['scripts/verification-utils.mjs', ['code', 'tooling'], ['shared', 'ios', 'android']],
  ['scripts/dependency-contract.mjs', ['code', 'tooling'], ['shared', 'ios', 'android']],
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

// The same action feeds standard CI and repository-specific consumers.
assert.match(template, /uses: \.\/\.github\/actions\/changes/);
assert.match(template, /actionlint:\n    needs: changes\n    if: always\(\)/);
assert.match(template, /run: test "\$CHANGES_RESULT" = success/);
assert.match(template, /fetch-depth: 0/);
for (const platform of ['ios', 'android']) {
  const job = template.split(`  build-${platform}:`)[1].split(/^  [a-z-]+:/m)[0];
  assert.ok(job.includes(`needs.changes.outputs.${platform} == 'true'`));
  assert.ok(job.includes(`hashFiles('.github/ci/${platform}.sh') != ''`));
  assert.ok(job.includes(`run: bash .github/ci/${platform}.sh`));
  assert.ok(job.includes(`if: env.turbo_cache_hit != 1 || hashFiles('.github/ci/${platform}.sh') != ''`));
}

// Execute the actual website detection body without installing or building anything.
const detector = action.match(/    - name: Detect website workspace\n      id: project\n      shell: bash\n      run: \|\n([\s\S]*?)    - name: Filter changed paths/);
assert.ok(detector);
const detectorScript = detector[1].split('\n').map(line => line.replace(/^        /, '')).join('\n');
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
console.log('PASS: optional website workspace and required failure propagation');

// 文档站会消费原生 example 的组合示例，CI 与实际部署必须使用一致的输入。
const deployTemplate = readFileSync(resolve(scriptDirectory, '../templates/workflows/deploy-docs.yml'), 'utf8');
const deployPaths = deployTemplate.split('  workflow_dispatch:')[0].split('    paths:')[1];
assert.ok(deployPaths, 'docs deploy 缺少 push paths');
filters.set('deploy', [...deployPaths.matchAll(/^      - '([^']+)'/gm)].map(match => match[1]));
assert.equal(matches('deploy', 'example/src/examples/MainChatExample/MainChatExample.tsx'), true);
assert.equal(matches('deploy', 'example/src/__tests__/Composition.test.tsx'), false);
assert.equal(matches('deploy', 'example/src/examples/Foo/__tests__/Foo.test.tsx'), false);
console.log('PASS: shared example documentation consumers');
