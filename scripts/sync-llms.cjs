#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const args = process.argv.slice(2);
const check = args.includes('--check');
const [name, targetArgument] = args.filter((value) => value !== '--check');
const websites = [
  'react-native-design',
  'react-native-camera',
  'react-native-hms-scan',
  'react-native-umeng',
  'react-native-chat',
];
if (!websites.includes(name))
  throw new Error('Specify a supported library name');
const target = path.resolve(
  targetArgument || path.join(__dirname, '..', '..', name)
);
const manifest = JSON.parse(
  fs.readFileSync(path.join(target, 'package.json'), 'utf8')
);
if (manifest.name !== `@unif/${name}`)
  throw new Error('Target package identity does not match');
const source = path.join(__dirname, '..', 'templates', 'llms');
const files = [
  ['build-llms-core.test.js', 'website/scripts/build-llms-core.test.js'],
  ...['bundle', 'markdown', 'routes', 'index'].map((item) => [
    `llms/${item}.js`,
    `website/scripts/llms/${item}.js`,
  ]),
];
if (name !== 'react-native-chat')
  files.unshift(
    ['build-llms.js', 'website/scripts/build-llms.js'],
    ['build-llms-site.test.js', 'website/scripts/build-llms-site.test.js']
  );
function checkTargetPath(output) {
  let current = target;
  const parts = ['', ...path.relative(target, output).split(path.sep)];
  for (const part of parts) {
    current = path.join(current, part);
    let stat;
    try {
      stat = fs.lstatSync(current);
    } catch (error) {
      if (error.code === 'ENOENT') break;
      throw error;
    }
    if (stat.isSymbolicLink()) throw new Error(`Refusing symlink: ${current}`);
  }
}
// Read every source and validate every target before changing the worktree.
const updates = files.map(([from, to]) => {
  const output = path.join(target, to);
  checkTargetPath(output);
  return { output, content: fs.readFileSync(path.join(source, from)), to };
});
if (check) {
  for (const { output, content, to } of updates) {
    if (!fs.existsSync(output) || !content.equals(fs.readFileSync(output)))
      throw new Error(`Generated implementation drift: ${name}/${to}`);
  }
} else {
  const stage = fs.mkdtempSync(path.join(target, '.llms-sync-'));
  const installed = [];
  let keepStage = false;
  try {
    for (const [index, update] of updates.entries()) {
      update.staged = path.join(stage, `new-${index}`);
      update.previous = fs.existsSync(update.output)
        ? path.join(stage, `old-${index}`)
        : null;
      fs.writeFileSync(update.staged, update.content);
      if (update.previous) {
        fs.copyFileSync(update.output, update.previous);
        fs.chmodSync(update.staged, fs.statSync(update.output).mode);
      }
    }
    try {
      for (const update of updates) {
        fs.mkdirSync(path.dirname(update.output), { recursive: true });
        fs.renameSync(update.staged, update.output);
        installed.push(update);
      }
    } catch (error) {
      const failures = [error];
      for (const update of installed.reverse()) {
        try {
          if (update.previous) fs.renameSync(update.previous, update.output);
          else fs.rmSync(update.output);
        } catch (restoreError) {
          failures.push(restoreError);
        }
      }
      keepStage = failures.length > 1;
      if (keepStage)
        throw new AggregateError(
          failures,
          `LLM sync rollback incomplete; recovery files: ${stage}`
        );
      throw error;
    }
  } finally {
    if (!keepStage) fs.rmSync(stage, { recursive: true, force: true });
  }
}
process.stdout.write(
  `${check ? 'Checked' : 'Synced'} LLM documentation implementation: ${name}\n`
);
