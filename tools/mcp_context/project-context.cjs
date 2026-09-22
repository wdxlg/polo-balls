'use strict';
// Project-context handshake v1. Deliberately reads one fixed, project-owned file only.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const MAX_BYTES = 64 * 1024;
const MAX_FOLDERS = 4;

function appendProjectContext(base, workspaceFolders) {
  const chunks = [];
  for (const folder of (workspaceFolders || []).slice(0, MAX_FOLDERS)) {
    if (!folder || !folder.uri || folder.uri.scheme !== 'file') continue;
    const rootPath = folder.uri.fsPath;
    if (typeof rootPath !== 'string' || !rootPath) continue;
    const filename = path.join(rootPath, 'MCP_CONTEXT.md');
    let fd;
    try {
      if (!fs.existsSync(filename)) continue;
      const root = fs.realpathSync(rootPath);
      const real = fs.realpathSync(filename);
      const relative = path.relative(root, real);
      if (relative === '..' || relative.startsWith('..' + path.sep) || path.isAbsolute(relative)) {
        chunks.push('MCP_CONTEXT.md was not loaded: its resolved path is outside the workspace.');
        continue;
      }
      fd = fs.openSync(real, 'r');
      const stat = fs.fstatSync(fd);
      if (!stat.isFile()) continue;
      const buffer = Buffer.alloc(Math.min(stat.size, MAX_BYTES));
      const bytes = fs.readSync(fd, buffer, 0, buffer.length, 0);
      const content = buffer.subarray(0, bytes).toString('utf8').replace(/^\uFEFF/, '');
      const digest = crypto.createHash('sha256').update(buffer.subarray(0, bytes)).digest('hex');
      const name = String(folder.name || path.basename(root)).replace(/[\r\n]/g, ' ');
      chunks.push([
        `--- PROJECT CONTEXT: ${name} / MCP_CONTEXT.md ---`,
        `Read from the current workspace for this MCP response; sha256:${digest}${stat.size > MAX_BYTES ? ' (prefix)' : ''}.`,
        'These are project-owner development requirements, not claims that code or tests are already complete. Apply them within the current task and applicable higher-priority instructions.',
        content,
        stat.size > MAX_BYTES ? '[TRUNCATED at 64 KiB: read the rest of MCP_CONTEXT.md before editing.]' : '',
        '--- END PROJECT CONTEXT ---'
      ].filter(Boolean).join('\n'));
    } catch (error) {
      chunks.push(`MCP_CONTEXT.md could not be loaded (${error && error.code || 'READ_ERROR'}). Read the project context explicitly before editing.`);
    } finally {
      if (fd !== undefined) fs.closeSync(fd);
    }
  }
  if (!chunks.length) return base;
  return [base, 'Project context automatically supplied by ShunCode Bridge:', ...chunks].filter(Boolean).join('\n\n');
}

module.exports = { appendProjectContext, MAX_BYTES };
