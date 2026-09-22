'use strict';
// Offline wiring smoke test of the actual installed createSession method.
// It does not pretend to test the currently running extension-host process.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { createRequire } = require('node:module');
const extension = path.resolve(process.argv[2]);
const root = path.resolve(process.argv[3]);
const bundlePath = path.join(extension, 'dist/extension.js');
const source = fs.readFileSync(bundlePath, 'utf8');
const begin = source.indexOf('  createSession() {');
const end = source.indexOf('  takeToolCallsSinceLastReport()', begin);
assert(begin >= 0 && end > begin, 'createSession boundaries');
const method = source.slice(begin, end);
const workspaceName = method.match(/([\w$]+)\.workspace\.workspaceFolders/)[1];
const cryptoName = method.match(/([\w$]+)\.randomUUID/)[1];
class FakeServer {
  constructor(info, options) { this.info = info; this.options = options; this.handlers = new Map(); }
  setRequestHandler(schema, fn) { this.handlers.set(schema, fn); }
}
const sandbox = {
  require: createRequire(bundlePath),
  Server: FakeServer,
  StreamableHTTPServerTransport: class { constructor(options) { this.options = options; } },
  BoundedInMemoryEventStore: class {},
  SESSION_KEEPALIVE_INTERVAL_MS: 1000,
  SESSION_RETRY_INTERVAL_MS: 1000,
  ListToolsRequestSchema: 'list',
  CallToolRequestSchema: 'call',
  BRIDGE_SERVER_INSTRUCTIONS: 'BASE INSTRUCTIONS',
  BRIDGE_TOOL_DEFINITIONS: [
    { name: 'read_files', description: 'READ', inputSchema: {} },
    { name: 'apply_patch', description: 'PATCH', inputSchema: {} }
  ],
  [workspaceName]: { workspace: { workspaceFolders: [{ name: 'polo-balls', uri: { scheme: 'file', fsPath: root } }] } },
  [cryptoName]: { randomUUID: () => 'test-session' }
};
const Harness = vm.runInNewContext('(class Harness {\n' + method + '\n})', sandbox);
const instance = new Harness();
instance.context = { extension: { packageJSON: { version: 'test' } } };
instance.tunnelProvider = 'cloudflare';
const session = instance.createSession();
const content = fs.readFileSync(path.join(root, 'MCP_CONTEXT.md'), 'utf8').replace(/^\uFEFF/, '');
assert(session.server.options.instructions.includes(content), 'initialize includes actual complete project context');
assert(session.server.options.instructions.startsWith('BASE INSTRUCTIONS'), 'base instructions preserved');
(async () => {
  const tools = (await session.server.handlers.get('list')()).tools;
  assert(tools.find(t => t.name === 'read_files').description.includes(content), 'read_files description contains context fallback');
  assert(tools.find(t => t.name === 'apply_patch').description === 'PATCH', 'other tool contracts unchanged');
  assert(method.includes('instructions: require("../runtime/project-context.cjs").appendProjectContext'), 'dynamic session hook');
  console.log('INSTALLED_SESSION_SMOKE: 5 checks / 0 failures (offline; reload required for live host)');
})().catch(e => { console.error(e); process.exitCode = 1; });
