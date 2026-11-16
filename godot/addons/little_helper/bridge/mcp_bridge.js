#!/usr/bin/env node

/**
 * LittleHelper - Zero-Dependency MCP Bridge for Godot 4
 * 
 * Bridges standard Model Context Protocol (stdio) directly to Godot's
 * in-editor TCP server without requiring ANY npm packages or node_modules.
 * 
 * Usage:
 *   node addons/little_helper/bridge/mcp_bridge.js [port]
 */

const readline = require('node:readline');
const net = require('node:net');

const GODOT_HOST = process.env.GODOT_HOST || '127.0.0.1';
const portArg = process.argv.slice(2).find(arg => /^\d+$/.test(arg));
const parsedPort = parseInt(portArg || process.env.GODOT_PORT || '9099', 10);
const GODOT_PORT = (!isNaN(parsedPort) && parsedPort > 0 && parsedPort < 65536) ? parsedPort : 9099;

let godotSocket = null;
let isConnected = false;
let isConnecting = false;
let connectWaiters = [];
let pendingRequests = new Map(); // id -> resolve
let messageBuffer = '';

function log(msg) {
  process.stderr.write(`[LittleHelper-Bridge] ${msg}\n`);
}

function ensureConnected() {
  if (isConnected) return Promise.resolve(true);
  return new Promise((resolve) => {
    connectWaiters.push(resolve);
    if (!isConnecting) {
      connectToGodot();
    }
    setTimeout(() => {
      const idx = connectWaiters.indexOf(resolve);
      if (idx !== -1) {
        connectWaiters.splice(idx, 1);
        resolve(isConnected);
      }
    }, 2500);
  });
}

function connectToGodot() {
  if (isConnecting || isConnected) return;
  isConnecting = true;
  godotSocket = new net.Socket();

  godotSocket.connect(GODOT_PORT, GODOT_HOST, () => {
    isConnected = true;
    isConnecting = false;
    log(`Connected to Godot editor at ${GODOT_HOST}:${GODOT_PORT}`);
    while (connectWaiters.length > 0) {
      const waiter = connectWaiters.shift();
      waiter(true);
    }
  });

  godotSocket.on('data', (data) => {
    messageBuffer += data.toString('utf8');
    while (messageBuffer.includes('\n')) {
      const idx = messageBuffer.indexOf('\n');
      const line = messageBuffer.slice(0, idx).trim();
      messageBuffer = messageBuffer.slice(idx + 1);
      if (line) {
        handleGodotMessage(line);
      }
    }
  });

  godotSocket.on('error', (err) => {
    log(`Godot socket error: ${err.message}`);
    isConnected = false;
    isConnecting = false;
    while (connectWaiters.length > 0) {
      const waiter = connectWaiters.shift();
      waiter(false);
    }
  });

  godotSocket.on('close', () => {
    isConnected = false;
    isConnecting = false;
    while (connectWaiters.length > 0) {
      const waiter = connectWaiters.shift();
      waiter(false);
    }
    log('Godot connection closed. Retrying in 2s...');
    setTimeout(connectToGodot, 2000);
  });
}

function handleGodotMessage(raw) {
  try {
    const parsed = JSON.parse(raw);
    const id = parsed.id;
    if (id !== undefined && pendingRequests.has(id)) {
      const handler = pendingRequests.get(id);
      pendingRequests.delete(id);
      handler(parsed);
    } else {
      // Direct pass-through to MCP stdout
      sendToMcp(parsed);
    }
  } catch (e) {
    log(`Failed to parse Godot reply: ${e.message}`);
  }
}

async function sendToGodot(obj) {
  if (!isConnected) {
    await ensureConnected();
  }

  return new Promise((resolve) => {
    if (!godotSocket || !isConnected) {
      resolve({
        error: {
          code: -32000,
          message: "Godot editor is not connected. Make sure Godot is running and LittleHelper plugin is enabled."
        }
      });
      return;
    }
    const id = obj.id;
    if (id !== undefined) {
      pendingRequests.set(id, resolve);
    }
    godotSocket.write(JSON.stringify(obj) + '\n');
  });
}

function sendToMcp(obj) {
  process.stdout.write(JSON.stringify(obj) + '\n');
}

// ----------------------------------------------------------------------------
// MCP Stdio Message Loop
// ----------------------------------------------------------------------------

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
  terminal: false
});

rl.on('line', async (line) => {
  const trimmed = line.trim();
  if (!trimmed) return;

  let msg;
  try {
    msg = JSON.parse(trimmed);
  } catch (err) {
    log(`Invalid JSON from MCP client: ${err.message}`);
    return;
  }

  const id = msg.id;
  const method = msg.method;

  // Handle MCP Handshake
  if (method === 'initialize') {
    sendToMcp({
      jsonrpc: '2.0',
      id: id,
      result: {
        protocolVersion: '2024-11-05',
        capabilities: {
          tools: { listChanged: false }
        },
        serverInfo: {
          name: 'little-helper-godot',
          version: '1.0.0'
        }
      }
    });
    return;
  }

  if (method === 'notifications/initialized') {
    // Client notification, no response required
    return;
  }

  if (method === 'tools/list') {
    const godotReply = await sendToGodot({ id: id, method: 'tools/list' });
    if (godotReply.result) {
      sendToMcp({
        jsonrpc: '2.0',
        id: id,
        result: godotReply.result
      });
    } else {
      sendToMcp({
        jsonrpc: '2.0',
        id: id,
        error: godotReply.error || { code: -32603, message: "Failed to retrieve tools from Godot." }
      });
    }
    return;
  }

  if (method === 'tools/call') {
    const godotReply = await sendToGodot({
      id: id,
      method: 'tools/call',
      params: msg.params
    });
    sendToMcp(godotReply);
    return;
  }

  // Fallback forward any other method to Godot
  const fallbackReply = await sendToGodot(msg);
  sendToMcp(fallbackReply);
});

// Start listening to Godot
connectToGodot();

