import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { exec } from 'child_process';
import { promisify } from 'util';
import http from 'http';
import { z } from 'zod';

const execAsync = promisify(exec);

const MCP_TOKEN = process.env.MCP_TOKEN;
const PORT = process.env.PORT || 8000;

if (!MCP_TOKEN) {
  console.error('MCP_TOKEN environment variable is required');
  process.exit(1);
}

const server = new McpServer({
  name: 'vps-shell',
  version: '1.0.0',
});

server.tool(
  'execute_command',
  'Execute a shell command on the VPS. Returns stdout and stderr.',
  { command: z.string().describe('The shell command to execute') },
  async ({ command }) => {
    try {
      const { stdout, stderr } = await execAsync(command, {
        timeout: 30000,
        maxBuffer: 1024 * 1024 * 5,
        shell: '/bin/bash',
      });
      return {
        content: [
          {
            type: 'text',
            text: stdout || stderr || '(no output)',
          },
        ],
      };
    } catch (err) {
      return {
        content: [
          {
            type: 'text',
            text: `Error (exit ${err.code}):\n${err.stderr || err.message}`,
          },
        ],
        isError: true,
      };
    }
  }
);

const httpServer = http.createServer(async (req, res) => {
  // Auth par token
  const auth = req.headers['authorization'];
  if (!auth || auth !== `Bearer ${MCP_TOKEN}`) {
    res.writeHead(403, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Forbidden' }));
    return;
  }

  const transport = new StreamableHTTPServerTransport({
    sessionIdGenerator: undefined,
  });

  res.on('close', () => transport.close());

  await server.connect(transport);
  await transport.handleRequest(req, res, await parseBody(req));
});

function parseBody(req) {
  return new Promise((resolve) => {
    let body = '';
    req.on('data', (chunk) => (body += chunk));
    req.on('end', () => {
      try {
        resolve(body ? JSON.parse(body) : undefined);
      } catch {
        resolve(undefined);
      }
    });
  });
}

httpServer.listen(PORT, '0.0.0.0', () => {
  console.log(`VPS Shell MCP server running on port ${PORT}`);
});
