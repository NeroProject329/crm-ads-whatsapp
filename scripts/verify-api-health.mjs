import { spawn } from 'node:child_process';

const baseUrl = 'http://127.0.0.1:3001';
const apiProcess = spawn(process.execPath, ['apps/api/dist/main.js'], {
  cwd: process.cwd(),
  env: process.env,
  stdio: ['ignore', 'pipe', 'pipe'],
  windowsHide: true,
});

let processOutput = '';
apiProcess.stdout.on('data', (chunk) => {
  processOutput += chunk.toString();
});
apiProcess.stderr.on('data', (chunk) => {
  processOutput += chunk.toString();
});

const delay = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));

async function request(path) {
  const response = await fetch(`${baseUrl}${path}`, {
    signal: AbortSignal.timeout(15_000),
  });
  const body = await response.json();

  if (!response.ok) {
    throw new Error(`${path} returned HTTP ${response.status}: ${JSON.stringify(body)}`);
  }

  return { path, statusCode: response.status, body };
}

async function waitForApi() {
  for (let attempt = 0; attempt < 30; attempt += 1) {
    if (apiProcess.exitCode !== null) {
      throw new Error(
        `API exited with code ${apiProcess.exitCode}.\n${processOutput.slice(-2_000)}`,
      );
    }

    try {
      return await request('/api/v1/health/live');
    } catch {
      await delay(500);
    }
  }

  throw new Error(`API did not start within 15 seconds.\n${processOutput.slice(-2_000)}`);
}

try {
  const live = await waitForApi();
  const ready = await request('/api/v1/health/ready');
  const health = await request('/api/v1/health');

  console.log(JSON.stringify({ event: 'api.health.verified', checks: [live, ready, health] }));
} finally {
  if (apiProcess.exitCode === null) {
    apiProcess.kill('SIGTERM');
    await Promise.race([new Promise((resolve) => apiProcess.once('exit', resolve)), delay(5_000)]);
  }
}
