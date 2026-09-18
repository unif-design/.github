'use strict';
const { Buffer } = require('node:buffer');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const workspace = fs.mkdtempSync(path.join(os.tmpdir(), 'unif-llms-sync-'));
const synchronizer = path.join(__dirname, 'sync-llms.cjs');
try {
  for (const name of [
    'react-native-design',
    'react-native-camera',
    'react-native-hms-scan',
    'react-native-umeng',
    'react-native-chat',
  ]) {
    const target = path.join(workspace, name);
    fs.mkdirSync(target);
    fs.writeFileSync(
      path.join(target, 'package.json'),
      JSON.stringify({ name: `@unif/${name}` })
    );
    for (const args of [
      [name, target],
      [name, target, '--check'],
    ]) {
      const result = spawnSync(process.execPath, [synchronizer, ...args], {
        encoding: 'utf8',
      });
      assert.equal(result.status, 0, result.stderr);
    }
    const indexPath = path.join(target, 'website/scripts/llms/index.js');
    const clean = fs.readFileSync(indexPath);
    fs.appendFileSync(indexPath, '\n// drift\n');
    const result = spawnSync(
      process.execPath,
      [synchronizer, name, target, '--check'],
      { encoding: 'utf8' }
    );
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /drift/);
    assert(fs.readFileSync(indexPath).includes(Buffer.from('// drift')));
    fs.writeFileSync(indexPath, clean);
    if (name === 'react-native-design') {
      // Run the existing common suite in the same distributed layout used by each library.
      const docs = path.join(target, 'website/docs');
      fs.mkdirSync(docs, { recursive: true });
      fs.writeFileSync(path.join(docs, 'intro.md'), '# Fixture\n');
      fs.writeFileSync(
        path.join(target, 'package.json'),
        JSON.stringify({
          name: '@unif/react-native-design',
          version: '1.0.0',
          description: 'Fixture',
        })
      );
      const common = spawnSync(
        process.execPath,
        [path.join(target, 'website/scripts/build-llms-core.test.js')],
        { encoding: 'utf8' }
      );
      assert.equal(common.status, 0, common.stdout + common.stderr);
    }
  }
  function snapshot(directory) {
    const found = {};
    const walk = (current) => {
      for (const name of fs.readdirSync(current)) {
        const file = path.join(current, name);
        const stat = fs.lstatSync(file);
        if (stat.isSymbolicLink())
          found[path.relative(directory, file)] =
            `link:${fs.readlinkSync(file)}`;
        else if (stat.isDirectory()) walk(file);
        else
          found[path.relative(directory, file)] = fs
            .readFileSync(file)
            .toString('base64');
      }
    };
    walk(directory);
    return found;
  }
  for (const failure of [
    'missing-template',
    'parent-link',
    'dangling-link',
    'install-error',
  ]) {
    const caseRoot = path.join(workspace, failure);
    const org = path.join(caseRoot, 'org');
    const target = path.join(caseRoot, 'target');
    fs.mkdirSync(path.join(org, 'scripts'), { recursive: true });
    fs.cpSync(
      path.join(__dirname, '../templates/llms'),
      path.join(org, 'templates/llms'),
      { recursive: true }
    );
    fs.copyFileSync(synchronizer, path.join(org, 'scripts/sync-llms.cjs'));
    fs.mkdirSync(path.join(target, 'website/scripts/llms'), {
      recursive: true,
    });
    fs.writeFileSync(
      path.join(target, 'package.json'),
      JSON.stringify({ name: '@unif/react-native-camera' })
    );
    fs.writeFileSync(
      path.join(target, 'website/scripts/build-llms.js'),
      'original entry'
    );
    const outside = path.join(caseRoot, 'outside');
    fs.mkdirSync(outside);
    fs.writeFileSync(path.join(outside, 'sentinel'), 'original outside');
    let preload;
    if (failure === 'missing-template')
      fs.rmSync(path.join(org, 'templates/llms/llms/index.js'));
    if (failure === 'parent-link') {
      fs.rmSync(path.join(target, 'website/scripts/llms'), { recursive: true });
      fs.symlinkSync(outside, path.join(target, 'website/scripts/llms'));
    }
    if (failure === 'dangling-link')
      fs.symlinkSync(
        path.join(outside, 'absent'),
        path.join(target, 'website/scripts/llms/index.js')
      );
    if (failure === 'install-error') {
      preload = path.join(caseRoot, 'fault.cjs');
      fs.writeFileSync(
        preload,
        `const fs = require('node:fs'); const rename = fs.renameSync; fs.renameSync = (a,b) => { if (b.endsWith('/llms/index.js')) throw new Error('injected install failure'); return rename(a,b); };`
      );
    }
    const before = snapshot(target);
    const externalBefore = snapshot(outside);
    const args = [
      ...(preload ? ['--require', preload] : []),
      path.join(org, 'scripts/sync-llms.cjs'),
      'react-native-camera',
      target,
    ];
    const result = spawnSync(process.execPath, args, { encoding: 'utf8' });
    assert.notEqual(result.status, 0, failure);
    assert.deepEqual(snapshot(target), before, failure);
    assert.deepEqual(snapshot(outside), externalBefore, failure);
  }
  const wrong = path.join(workspace, 'wrong');
  fs.mkdirSync(wrong);
  fs.writeFileSync(
    path.join(wrong, 'package.json'),
    JSON.stringify({ name: '@unif/wrong' })
  );
  const rejected = spawnSync(
    process.execPath,
    [synchronizer, 'react-native-camera', wrong],
    { encoding: 'utf8' }
  );
  assert.notEqual(rejected.status, 0);
  assert(!fs.existsSync(path.join(wrong, 'website')));
  console.log(
    'PASS shared LLM source, distribution, drift and target identity'
  );
} finally {
  fs.rmSync(workspace, { recursive: true, force: true });
}
