'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { appendProjectContext, MAX_BYTES } = require('./project-context.cjs');
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'shuncode-context-test-'));
const folders = [{ name: 'test-project', uri: { scheme: 'file', fsPath: temp } }];
let checks = 0;
function check(condition) { assert(condition); checks++; }
try {
  check(appendProjectContext('BASE', folders) === 'BASE');
  const p = path.join(temp, 'MCP_CONTEXT.md');
  fs.writeFileSync(p, '\uFEFF规则 v1：伤害 > 50 播放暴击。\n本地 Git 检查点。\n真实威胁显示。');
  const first = appendProjectContext('BASE', folders);
  check(first.startsWith('BASE\n\n'));
  check(first.includes('伤害 > 50'));
  check(first.includes('本地 Git 检查点'));
  check(first.includes('真实威胁显示'));
  check(first.includes('sha256:'));
  check(!first.includes('\uFEFF'));
  fs.writeFileSync(p, '规则 v2');
  const second = appendProjectContext('', folders);
  check(second.includes('规则 v2') && !second.includes('规则 v1'));
  check(!second.startsWith('\n'));
  check(appendProjectContext('BASE', [{ uri: { scheme: 'https', fsPath: temp } }]) === 'BASE');
  check(appendProjectContext('BASE', []) === 'BASE');
  fs.writeFileSync(p, 'x'.repeat(MAX_BYTES + 20));
  const bounded = appendProjectContext('', folders);
  check(bounded.includes('[TRUNCATED at 64 KiB'));
  check(bounded.length < MAX_BYTES + 1500);
  check(!bounded.includes('x'.repeat(MAX_BYTES + 1)));
  fs.unlinkSync(p);
  fs.mkdirSync(p);
  check(appendProjectContext('BASE', folders) === 'BASE');
  console.log(`CONTEXT_TEST: ${checks} checks / 0 failures`);
} finally { fs.rmSync(temp, { recursive: true, force: true }); }
