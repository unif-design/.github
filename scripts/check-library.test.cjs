'use strict';
const assert = require('node:assert/strict');
const { execFileSync, spawnSync } = require('node:child_process');
const { createHash } = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { test } = require('node:test');
const checkerPath = path.resolve(__dirname, '../templates/scripts/check-library.cjs');
const packageName = '@unif/react-native-fixture';
const registry = 'https://registry.npmjs.org/';
function checker() {
  assert.ok(fs.existsSync(checkerPath), 'the shared library checker must exist');
  return require(checkerPath).checkLibrary;
}
function write(root, file, content) {
  fs.mkdirSync(path.dirname(path.join(root, file)), { recursive: true });
  fs.writeFileSync(path.join(root, file), content);
}
function fixture(t, { website = false } = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'unif-library-test-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const pkg = {
    name: packageName, version: '0.1.0', description: 'A public React Native library fixture',
    homepage: 'https://unif-design.github.io/react-native-fixture/',
    repository: { type: 'git', url: 'git+https://github.com/unif-design/react-native-fixture.git' },
    license: 'MIT', main: './lib/module/index.js', types: './lib/typescript/index.d.ts',
    exports: {
      '.': { source: './src/index.ts', types: './lib/typescript/index.d.ts', default: './lib/module/index.js' },
      './package.json': './package.json',
    },
    files: ['src', 'lib'], publishConfig: { registry, access: 'public' },
    'release-it': { npm: { publish: true, skipChecks: true } },
  };
  const save = () => write(root, 'package.json', JSON.stringify(pkg));
  const readme = `# Fixture\n\nyarn add ${packageName}\n\n[Docs](${pkg.homepage}) · [npm](https://www.npmjs.com/package/${packageName}) · [MIT](LICENSE)\n`;
  write(root, 'README.md', readme);
  write(root, 'LICENSE', 'MIT License\n\nCopyright (c) 2026 Unif\n\nPermission is hereby granted, free of charge, to any person obtaining a copy of this software.\n');
  write(root, 'src/index.ts', 'export const answer = 42;\n');
  write(root, 'lib/module/index.js', 'exports.answer = 42;\n');
  write(root, 'lib/typescript/index.d.ts', 'export declare const answer: number;\n');
  const site = {
    name: `${packageName}-website`, private: true,
    scripts: { build: 'node scripts/build-llms.js && docusaurus build', typecheck: 'tsc --noEmit' },
  };
  if (website) {
    pkg.workspaces = ['website'];
    write(root, 'website/package.json', JSON.stringify(site));
    write(root, 'website/scripts/build-llms.js', '// shared LLM builder\n');
    write(root, 'website/scripts/build-llms.test.js', '// shared LLM test entry\n');
  }
  save();
  return { root, pkg, save, readme, site };
}
async function reject(f, mode, pattern) {
  await assert.rejects(() => checker()(mode, f.root), pattern);
}
test('source accepts a private candidate without a website while release rejects it', async t => {
  const f = fixture(t);
  f.pkg.private = true;
  f.pkg.license = 'UNLICENSED';
  f.save();
  assert.equal((await checker()('source', f.root)).name, packageName);
  await reject(f, 'release', /private/);
  assert.equal((await checker()('pack', f.root)).version, '0.1.0');
});
test('source validates metadata and export target paths before any packaging', async t => {
  const f = fixture(t);
  for (const target of ['../secret.js', './lib/../../secret.js', '/tmp/secret.js', './node_modules/pkg/index.js', './lib/%2e%2e/secret.js']) {
    f.pkg.exports['.'].default = target;
    f.save();
    await reject(f, 'source', /export.*target|unsafe.*path/i);
  }
  f.pkg.exports['.'].default = './lib/module/index.js';
  f.pkg.version = 'latest';
  f.save();
  await reject(f, 'source', /version/);
});
test('source requires a nonempty README', async t => {
  const f = fixture(t);
  fs.rmSync(path.join(f.root, 'README.md'));
  await reject(f, 'source', /README/);
});
test('source checks a present website even when it is not a workspace', async t => {
  const f = fixture(t, { website: true });
  delete f.pkg.workspaces;
  f.save();
  await reject(f, 'source', /website.*workspace|workspace.*website/);
});
test('source rejects an incomplete website package, commands, or LLM wiring', async t => {
  const f = fixture(t, { website: true });
  fs.rmSync(path.join(f.root, 'website/package.json'));
  await reject(f, 'source', /website.*package/);
  write(f.root, 'website/package.json', JSON.stringify({ ...f.site, scripts: { build: f.site.scripts.build } }));
  await reject(f, 'source', /typecheck/);
  write(f.root, 'website/package.json', JSON.stringify({ ...f.site, scripts: { ...f.site.scripts, build: 'docusaurus build' } }));
  await reject(f, 'source', /LLM|llms/);
  write(f.root, 'website/package.json', JSON.stringify(f.site));
  fs.rmSync(path.join(f.root, 'website/scripts/build-llms.test.js'));
  await reject(f, 'source', /build-llms.test.js/);
});
test('source rejects a metadata symlink that escapes the package root', async t => {
  const f = fixture(t);
  const outside = fs.mkdtempSync(path.join(os.tmpdir(), 'unif-outside-'));
  t.after(() => fs.rmSync(outside, { recursive: true, force: true }));
  write(outside, 'README.md', '# outside\n');
  fs.rmSync(path.join(f.root, 'README.md'));
  fs.symlinkSync(path.join(outside, 'README.md'), path.join(f.root, 'README.md'));
  await reject(f, 'source', /outside|escape|symlink/i);
});
test('release accepts a public library and permits the workflow public-access default', async t => {
  const f = fixture(t, { website: true });
  assert.equal((await checker()('release', f.root)).mode, 'release');
  delete f.pkg.publishConfig.access;
  f.save();
  assert.equal((await checker()('release', f.root)).name, packageName);
});
for (const [label, change, pattern] of [
  ['private publish skip', f => { f.pkg.private = true; }, /private/],
  ['disabled npm publishing', f => { f.pkg['release-it'].npm.publish = false; }, /publish/],
  ['missing OIDC skipChecks', f => { delete f.pkg['release-it'].npm.skipChecks; }, /skipChecks/],
  ['restricted npm access', f => { f.pkg.publishConfig.access = 'restricted'; }, /access/],
  ['nonofficial registry', f => { f.pkg.publishConfig.registry = 'https://registry.example.com/'; }, /registry/],
  ['unlicensed package', f => { f.pkg.license = 'UNLICENSED'; }, /license|LICENSE/],
  ['missing license text', f => { fs.rmSync(path.join(f.root, 'LICENSE')); }, /LICENSE/],
  ['empty license text', f => { write(f.root, 'LICENSE', ' \n'); }, /LICENSE/],
  ['repository homepage', f => { f.pkg.homepage = 'https://github.com/unif-design/react-native-fixture'; }, /homepage|documentation/],
]) {
  test(`release rejects ${label}`, async t => {
    const f = fixture(t, { website: true });
    change(f);
    f.save();
    await reject(f, 'release', pattern);
  });
}
test('release requires the formal website', async t => {
  const f = fixture(t);
  await reject(f, 'release', /website/);
});
for (const [label, remove, pattern] of [
  ['installation command', /yarn add [^\n]+/, /install|安装/],
  ['npm entry', /\[npm\]\([^\)]+\)/, /npm/],
  ['documentation entry', /\[Docs\]\([^\)]+\)/, /homepage|documentation|文档/],
  ['license entry', /\[MIT\]\([^\)]+\)/, /license|LICENSE/],
]) {
  test(`release requires the README ${label}`, async t => {
    const f = fixture(t, { website: true });
    write(f.root, 'README.md', f.readme.replace(remove, ''));
    await reject(f, 'release', pattern);
  });
}
test('pack checks the real tarball and never runs lifecycle scripts or leaves artifacts in the repo', async t => {
  const f = fixture(t);
  f.pkg.scripts = { prepack: 'node -e "require(\'node:fs\').writeFileSync(\'hook-ran\',\'bad\')"' };
  f.save();
  const before = fs.readdirSync(f.root).sort();
  assert.ok((await checker()('pack', f.root)).fileCount >= 6);
  assert.deepEqual(fs.readdirSync(f.root).sort(), before);
});
test('pack rejects an export that exists locally but is absent from the tarball', async t => {
  const f = fixture(t);
  f.pkg.exports['./hidden'] = './hidden.js';
  write(f.root, 'hidden.js', 'module.exports = 1;\n');
  f.save();
  await reject(f, 'pack', /hidden.js/);
});
test('pack checks every nested conditional export', async t => {
  const f = fixture(t);
  f.pkg.exports['.'].browser = { types: './lib/typescript/index.d.ts', default: './lib/module/index.web.js' };
  f.save();
  await reject(f, 'pack', /index.web.js/);
});
test('pack requires every wildcard instance to have its declaration', async t => {
  const f = fixture(t);
  f.pkg.exports['./*'] = { source: './src/icons/*.tsx', types: './lib/typescript/icons/*.d.ts', default: './lib/module/icons/*.js' };
  for (const name of ['Add', 'Remove']) {
    write(f.root, `src/icons/${name}.tsx`, 'export default 1;\n');
    write(f.root, `lib/typescript/icons/${name}.d.ts`, 'declare const value: number; export default value;\n');
    write(f.root, `lib/module/icons/${name}.js`, 'exports.default = 1;\n');
  }
  f.save();
  assert.equal((await checker()('pack', f.root)).mode, 'pack');
  fs.rmSync(path.join(f.root, 'lib/typescript/icons/Remove.d.ts'));
  await reject(f, 'pack', /Remove.d.ts/);
});
test('pack rejects an unmatched wildcard and a missing top-level type entry', async t => {
  const f = fixture(t);
  f.pkg.exports['./*'] = './lib/module/unused/*.js';
  f.save();
  await reject(f, 'pack', /unused/);
  delete f.pkg.exports['./*'];
  f.pkg.types = './lib/typescript/absent.d.ts';
  f.save();
  await reject(f, 'pack', /absent.d.ts/);
});
test('pack requires the license document in the distributed archive', async t => {
  const f = fixture(t);
  fs.rmSync(path.join(f.root, 'LICENSE'));
  await reject(f, 'pack', /LICENSE/);
});
function publication(t, f, requestedSpec = `${packageName}@0.1.0`) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'unif-registry-test-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const output = JSON.parse(execFileSync('npm', ['pack', f.root, '--ignore-scripts', '--json', '--pack-destination', directory, '--cache', path.join(directory, 'cache')], { cwd: directory, encoding: 'utf8', timeout: 60000 }));
  const [packed] = Array.isArray(output) ? output : Object.values(output);
  const archive = path.join(directory, packed.filename);
  const bytes = fs.readFileSync(archive);
  const metadata = {
    name: packageName, version: '0.1.0', gitHead: 'a'.repeat(40),
    dist: { tarball: `${registry}@unif/react-native-fixture/-/react-native-fixture-0.1.0.tgz`, integrity: `sha512-${createHash('sha512').update(bytes).digest('base64')}` },
  };
  const options = {
    fetch: async url => {
      assert.equal(url, `${registry}${encodeURIComponent(packageName)}/0.1.0`);
      return new Response(JSON.stringify(metadata), { status: 200 });
    },
    npm: (args, execution) => {
      assert.equal(args[0], 'pack');
      assert.equal(args[1], requestedSpec);
      assert.ok(args.includes('--ignore-scripts'));
      assert.equal(args[args.indexOf('--registry') + 1], registry);
      const destination = args[args.indexOf('--pack-destination') + 1];
      assert.notEqual(execution.cwd, f.root);
      fs.copyFileSync(archive, path.join(destination, packed.filename));
      return JSON.stringify([packed]);
    },
  };
  return { metadata, options, archive };
}
test('published verifies the exact registry version and downloaded tarball independently of gitHead', async t => {
  const f = fixture(t);
  const p = publication(t, f);
  assert.equal((await checker()('published', f.root, p.options)).version, '0.1.0');
});
for (const [label, response, pattern] of [
  ['registry 404', () => new Response('{}', { status: 404 }), /404/],
  ['registry server failure', () => new Response('{}', { status: 503 }), /503/],
  ['network failure', () => { throw new Error('offline'); }, /registry|network/i],
  ['invalid registry JSON', () => new Response('invalid', { status: 200 }), /registry|JSON/i],
  ['wrong version', () => new Response(JSON.stringify({ name: packageName, version: '0.0.9' })), /version/],
  ['wrong package', () => new Response(JSON.stringify({ name: '@unif/react-native-other', version: '0.1.0' })), /name|identity/],
]) {
  test(`published fails on ${label} instead of accepting existing tags`, async t => {
    const f = fixture(t);
    await assert.rejects(() => checker()('published', f.root, {
      fetch: async () => response(),
      npm: () => assert.fail('invalid registry evidence must not download a package'),
    }), pattern);
  });
}
test('published rejects an archive with different package metadata', async t => {
  const f = fixture(t);
  const remote = fixture(t);
  remote.pkg.version = '0.0.9';
  remote.save();
  const p = publication(t, remote);
  await assert.rejects(() => checker()('published', f.root, p.options), /version/);
});
test('published rejects tampered integrity and missing distributed exports', async t => {
  const f = fixture(t);
  f.pkg.exports['./hidden'] = './hidden.js';
  f.save();
  const p = publication(t, f);
  await assert.rejects(() => checker()('published', f.root, p.options), /hidden.js/);
  p.metadata.dist.integrity = `sha512-${Buffer.alloc(64).toString('base64')}`;
  await assert.rejects(() => checker()('published', f.root, p.options), /integrity/);
});
test('CLI defaults to cwd, fails invalid checks, and importing the module does not run it', t => {
  const f = fixture(t);
  const source = spawnSync(process.execPath, [checkerPath, 'source'], { cwd: f.root, encoding: 'utf8' });
  assert.equal(source.status, 0, source.stderr);
  const release = spawnSync(process.execPath, [checkerPath, 'release', f.root], { encoding: 'utf8' });
  assert.notEqual(release.status, 0);
  const invalid = spawnSync(process.execPath, [checkerPath, 'unknown'], { cwd: f.root, encoding: 'utf8' });
  assert.notEqual(invalid.status, 0);
  const imported = spawnSync(process.execPath, ['-e', `require(${JSON.stringify(checkerPath)})`], { encoding: 'utf8' });
  assert.equal(imported.status, 0, imported.stderr);
  assert.equal(imported.stdout, '');
  assert.equal(imported.stderr, '');
});

test('source rejects a website whose LLM generation is only in prebuild', async t => {
  const f = fixture(t, { website: true });
  f.site.scripts.prebuild = f.site.scripts.build;
  f.site.scripts.build = 'docusaurus build';
  write(f.root, 'website/package.json', JSON.stringify(f.site));
  await reject(f, 'source', /LLM|llms/);
});

test('source accepts a website build that explicitly runs its LLM script', async t => {
  const f = fixture(t, { website: true });
  f.site.scripts['build:llms'] = 'node scripts/build-llms.js';
  f.site.scripts.build = 'yarn build:llms && docusaurus build';
  write(f.root, 'website/package.json', JSON.stringify(f.site));
  assert.equal((await checker()('source', f.root)).name, packageName);
});

test('source rejects a semantic version with a leading-zero numeric prerelease', async t => {
  const f = fixture(t);
  f.pkg.version = '0.1.0-01';
  f.save();
  await reject(f, 'source', /version/);
});

test('published exits nonzero from the CLI for registry 404', t => {
  const f = fixture(t);
  write(f.root, 'registry-preload.cjs', 'globalThis.fetch = async () => new Response("{}", { status: 404 });\n');
  const run = spawnSync(process.execPath, ['--require', path.join(f.root, 'registry-preload.cjs'), checkerPath, 'published', f.root], { encoding: 'utf8' });
  assert.notEqual(run.status, 0);
  assert.match(run.stderr, /404/);
  assert.doesNotMatch(run.stdout, /PASS/);
});

test('pack rejects an npm output path that escapes its temporary directory', async t => {
  const f = fixture(t);
  await assert.rejects(() => checker()('pack', f.root, {
    npm: () => JSON.stringify([{ filename: '../outside.tgz' }]),
  }), /unsafe.*filename/);
});

test('published rejects symlinks inside the archive without extracting them', async t => {
  const f = fixture(t);
  const p = publication(t, f);
  const unpacked = path.join(path.dirname(p.archive), 'archive-fixture');
  fs.mkdirSync(unpacked);
  fs.cpSync(f.root, path.join(unpacked, 'package'), { recursive: true });
  const target = path.join(unpacked, 'package/lib/module/index.js');
  fs.rmSync(target);
  fs.symlinkSync('/tmp/unif-archive-escape', target);
  execFileSync('tar', ['-czf', p.archive, '-C', unpacked, 'package']);
  p.metadata.dist.integrity = `sha512-${createHash('sha512').update(fs.readFileSync(p.archive)).digest('base64')}`;
  await assert.rejects(() => checker()('published', f.root, p.options), /symlink/);
});

for (const mode of ['pack', 'published']) {
  test(`${mode} rejects browser/default condition reordering with unchanged targets`, async t => {
    const f = fixture(t);
    const remote = fixture(t);
    for (const candidate of [f, remote]) {
      write(candidate.root, 'lib/module/index.web.js', 'exports.answer = 24;\n');
    }
    f.pkg.exports['.'] = {
      types: './lib/typescript/index.d.ts',
      browser: './lib/module/index.web.js',
      default: './lib/module/index.js',
    };
    remote.pkg.exports['.'] = {
      types: './lib/typescript/index.d.ts',
      default: './lib/module/index.js',
      browser: './lib/module/index.web.js',
    };
    f.save();
    remote.save();
    const p = publication(t, remote, mode === 'pack' ? fs.realpathSync(f.root) : `${packageName}@0.1.0`);
    await assert.rejects(() => checker()(mode, f.root, p.options), /exports.*contract/);
  });
}
