import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { exec } from 'child_process';
import { promisify } from 'util';
import { readFileSync, existsSync } from 'fs';
import http from 'http';
import { z } from 'zod';

const execAsync = promisify(exec);

const MCP_TOKEN   = process.env.MCP_TOKEN;
const PORT        = process.env.PORT || 8000;
const MCP_TIMEOUT = parseInt(process.env.MCP_TIMEOUT || '30000', 10);
const WHITELIST_FILE = '/app/allowed-commands.txt';

if (!MCP_TOKEN) {
  console.error('MCP_TOKEN environment variable is required');
  process.exit(1);
}

// ─── Whitelist ────────────────────────────────────────────────────────────────

let allowedPrefixes = null; // null = mode ouvert (pas de fichier whitelist)

if (existsSync(WHITELIST_FILE)) {
  const lines = readFileSync(WHITELIST_FILE, 'utf8')
    .split('\n')
    .map(l => l.trim())
    .filter(l => l && !l.startsWith('#'));

  if (lines.length > 0) {
    allowedPrefixes = lines;
    console.log(`Whitelist active: ${allowedPrefixes.length} command(s) allowed`);
  }
}

function isAllowed(command) {
  if (!allowedPrefixes) return true;
  const cmd = command.trimStart();
  return allowedPrefixes.some(prefix => cmd === prefix || cmd.startsWith(prefix + ' '));
}

// ─── MCP Server ───────────────────────────────────────────────────────────────

const server = new McpServer({
  name: 'vps-shell',
  version: '1.0.0',
});

server.tool(
  'execute_command',
  `Execute a shell command on the VPS. Returns stdout and stderr.${allowedPrefixes ? ` Allowed commands: ${allowedPrefixes.join(', ')}` : ''}`,
  { command: z.string().describe('The shell command to execute') },
  async ({ command }) => {
    if (!isAllowed(command)) {
      return {
        content: [{ type: 'text', text: `Command not allowed: "${command.split(' ')[0]}"` }],
        isError: true,
      };
    }

    try {
      const { stdout, stderr } = await execAsync(command, {
        timeout: MCP_TIMEOUT,
        maxBuffer: 1024 * 1024 * 5,
        shell: '/bin/bash',
      });
      return {
        content: [{ type: 'text', text: stdout || stderr || '(no output)' }],
      };
    } catch (err) {
      return {
        content: [{ type: 'text', text: `Error (exit ${err.code}):\n${err.stderr || err.message}` }],
        isError: true,
      };
    }
  }
);

// ─── HTTP Server ──────────────────────────────────────────────────────────────

const httpServer = http.createServer(async (req, res) => {
  // Auth par token — seule vérification nécessaire
  const auth = req.headers['authorization'];
  if (!auth || auth !== `Bearer ${MCP_TOKEN}`) {
    res.writeHead(403, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Forbidden' }));
    return;
  }

  const transport = new StreamableHTTPServerTransport({
    sessionIdGenerator: undefined,
  });

  await server.connect(transport);
  res.on('close', () => transport.close());

  const body = await parseBody(req);
  await transport.handleRequest(req, res, body);
});

function parseBody(req) {
  return new Promise((resolve) => {
    let body = '';
    req.on('data', (chunk) => (body += chunk));
    req.on('end', () => {
      try { resolve(body ? JSON.parse(body) : undefined); }
      catch { resolve(undefined); }
    });
  });
}

httpServer.listen(PORT, '0.0.0.0', () => {
  console.log(`VPS Shell MCP server running on port ${PORT}`);
  console.log(`Timeout: ${MCP_TIMEOUT}ms`);
  console.log(`Whitelist: ${allowedPrefixes ? 'active' : 'disabled (all commands allowed)'}`);
});
