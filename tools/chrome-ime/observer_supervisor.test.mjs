import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import process from 'node:process';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const supervisorSource = fileURLToPath(new URL('./observer_supervisor.mjs', import.meta.url));

test('terminates a TERM-ignoring observer and grandchild process group', {
  skip: process.platform === 'win32',
  timeout: 10000,
}, async (context) => {
  const temporaryDirectory = await fs.mkdtemp(path.join(os.tmpdir(), 'hisle-observer-supervisor.'));
  const fixtureSource = path.join(temporaryDirectory, 'term-ignoring-observer.mjs');
  await fs.writeFile(fixtureSource, `
import { spawn } from 'node:child_process';
import process from 'node:process';

for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP']) {
  process.on(signal, () => {});
}

if (process.argv[2] === 'grandchild') {
  setInterval(() => {}, 1000);
} else {
  const grandchild = spawn(process.execPath, [process.argv[1], 'grandchild'], {
    detached: true,
    stdio: 'ignore',
  });
  console.log(JSON.stringify({
    child_pid: process.pid,
    grandchild_pid: grandchild.pid,
    supervisor_pid: Number(process.env.HISLE_SUPERVISOR_PID),
    fixture_token: process.env.HISLE_FIXTURE_TOKEN,
  }));
  setInterval(() => {}, 1000);
}
`, 'utf8');

  let supervisor;
  let childPID;
  let grandchildPID;
  context.after(async () => {
    if (grandchildPID) {
      try {
        process.kill(-grandchildPID, 'SIGKILL');
      } catch (error) {
        if (error?.code !== 'ESRCH') {
          throw error;
        }
      }
    }
    if (childPID) {
      try {
        process.kill(-childPID, 'SIGKILL');
      } catch (error) {
        if (error?.code !== 'ESRCH') {
          throw error;
        }
      }
    }
    if (supervisor && processExists(supervisor.pid)) {
      supervisor.kill('SIGKILL');
    }
    await fs.rm(temporaryDirectory, { recursive: true, force: true });
  });

  supervisor = spawn(process.execPath, [supervisorSource, fixtureSource], {
    env: {
      ...process.env,
      HISLE_OBSERVER_SHUTDOWN_TIMEOUT_MS: '100',
      HISLE_WRAPPER_PID: String(process.pid),
      HISLE_FIXTURE_TOKEN: 'inherited',
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  const fixtureState = await readJSONLine(supervisor.stdout);
  childPID = fixtureState.child_pid;
  grandchildPID = fixtureState.grandchild_pid;
  assert.equal(fixtureState.supervisor_pid, supervisor.pid);
  assert.equal(fixtureState.fixture_token, 'inherited');
  assert.equal(processExists(supervisor.pid), true);
  assert.equal(processExists(childPID), true);
  assert.equal(processExists(grandchildPID), true);

  const supervisorOutcome = childOutcome(supervisor);
  supervisor.kill('SIGTERM');
  const outcome = await supervisorOutcome;
  assert.deepEqual(outcome, { code: null, signal: 'SIGTERM' });

  await waitForProcessExit(supervisor.pid);
  await waitForProcessExit(childPID);
  await waitForProcessExit(grandchildPID);
  assert.equal(processExists(supervisor.pid), false);
  assert.equal(processExists(childPID), false);
  assert.equal(processExists(grandchildPID), false);
});

test('detects wrapper exit and terminates its orphaned observer process group', {
  skip: process.platform === 'win32',
  timeout: 10000,
}, async (context) => {
  const temporaryDirectory = await fs.mkdtemp(path.join(os.tmpdir(), 'hisle-observer-wrapper-exit.'));
  const observerSource = path.join(temporaryDirectory, 'term-ignoring-observer.mjs');
  const wrapperSource = path.join(temporaryDirectory, 'wrapper.mjs');
  await fs.writeFile(observerSource, `
import { spawn } from 'node:child_process';
import process from 'node:process';

for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP']) {
  process.on(signal, () => {});
}
if (process.argv[2] === 'grandchild') {
  setInterval(() => {}, 1000);
} else {
  const grandchild = spawn(process.execPath, [process.argv[1], 'grandchild'], {
    detached: true,
    stdio: 'ignore',
  });
  console.log(JSON.stringify({ child_pid: process.pid, grandchild_pid: grandchild.pid }));
  setInterval(() => {}, 1000);
}
`, 'utf8');
  await fs.writeFile(wrapperSource, `
import { spawn } from 'node:child_process';
import process from 'node:process';

const supervisor = spawn(process.execPath, [${JSON.stringify(supervisorSource)}, ${JSON.stringify(observerSource)}], {
  env: {
    ...process.env,
    HISLE_OBSERVER_SHUTDOWN_TIMEOUT_MS: '100',
    HISLE_WRAPPER_PID: String(process.pid),
  },
  stdio: ['ignore', 'pipe', 'inherit'],
});
let text = '';
supervisor.stdout.on('data', (chunk) => {
  text += chunk;
  const newline = text.indexOf('\\n');
  if (newline === -1) return;
  const state = JSON.parse(text.slice(0, newline));
  process.stdout.write(JSON.stringify({
    ...state,
    supervisor_pid: supervisor.pid,
    wrapper_pid: process.pid,
  }) + '\\n', () => process.exit(0));
});
`, 'utf8');

  const wrapper = spawn(process.execPath, [wrapperSource], {
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const state = await readJSONLine(wrapper.stdout);
  context.after(async () => {
    try {
      process.kill(-state.grandchild_pid, 'SIGKILL');
    } catch (error) {
      if (error?.code !== 'ESRCH') throw error;
    }
    try {
      process.kill(-state.child_pid, 'SIGKILL');
    } catch (error) {
      if (error?.code !== 'ESRCH') throw error;
    }
    if (processExists(state.supervisor_pid)) {
      process.kill(state.supervisor_pid, 'SIGKILL');
    }
    if (processExists(wrapper.pid)) {
      wrapper.kill('SIGKILL');
    }
    await fs.rm(temporaryDirectory, { recursive: true, force: true });
  });

  assert.deepEqual(await childOutcome(wrapper), { code: 0, signal: null });
  await waitForProcessExit(state.wrapper_pid);
  await waitForProcessExit(state.supervisor_pid);
  await waitForProcessExit(state.child_pid);
  await waitForProcessExit(state.grandchild_pid);
});

test('cleans surviving descendants before mirroring an observer failure', {
  skip: process.platform === 'win32',
  timeout: 10000,
}, async (context) => {
  const temporaryDirectory = await fs.mkdtemp(path.join(os.tmpdir(), 'hisle-observer-failure.'));
  const fixtureSource = path.join(temporaryDirectory, 'failing-observer.mjs');
  await fs.writeFile(fixtureSource, `
import { spawn } from 'node:child_process';
import process from 'node:process';

const grandchild = spawn(process.execPath, ['-e', "process.on('SIGTERM', () => {}); setInterval(() => {}, 1000);"], {
  detached: true,
  stdio: 'ignore',
});
process.stdout.write(JSON.stringify({ grandchild_pid: grandchild.pid }) + '\\n', () => process.exit(7));
`, 'utf8');

  const supervisor = spawn(process.execPath, [supervisorSource, fixtureSource], {
    env: {
      ...process.env,
      HISLE_OBSERVER_SHUTDOWN_TIMEOUT_MS: '100',
      HISLE_WRAPPER_PID: String(process.pid),
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const state = await readJSONLine(supervisor.stdout);
  context.after(async () => {
    if (processExists(state.grandchild_pid)) {
      process.kill(state.grandchild_pid, 'SIGKILL');
    }
    if (processExists(supervisor.pid)) {
      supervisor.kill('SIGKILL');
    }
    await fs.rm(temporaryDirectory, { recursive: true, force: true });
  });

  assert.deepEqual(await childOutcome(supervisor), { code: 7, signal: null });
  await waitForProcessExit(state.grandchild_pid);
});

test('finishes descendant cleanup when signaled after an observer failure', {
  skip: process.platform === 'win32',
  timeout: 10000,
}, async (context) => {
  const temporaryDirectory = await fs.mkdtemp(path.join(os.tmpdir(), 'hisle-observer-failure-signal.'));
  const fixtureSource = path.join(temporaryDirectory, 'failing-observer.mjs');
  const readyMarker = path.join(temporaryDirectory, 'grandchild-ready');
  const termMarker = path.join(temporaryDirectory, 'grandchild-term');
  await fs.writeFile(fixtureSource, `
import { spawn } from 'node:child_process';
import { existsSync, writeFileSync } from 'node:fs';
import process from 'node:process';

if (process.argv[2] === 'grandchild') {
  process.on('SIGTERM', () => writeFileSync(${JSON.stringify(termMarker)}, 'received'));
  writeFileSync(${JSON.stringify(readyMarker)}, 'ready');
  setInterval(() => {}, 1000);
} else {
  const grandchild = spawn(process.execPath, [process.argv[1], 'grandchild'], {
    detached: true,
    stdio: 'ignore',
  });
  const readyWatch = setInterval(() => {
    if (!existsSync(${JSON.stringify(readyMarker)})) return;
    clearInterval(readyWatch);
    process.stdout.write(JSON.stringify({ grandchild_pid: grandchild.pid }) + '\\n', () => process.exit(7));
  }, 10);
}
`, 'utf8');

  const supervisor = spawn(process.execPath, [supervisorSource, fixtureSource], {
    env: {
      ...process.env,
      HISLE_OBSERVER_SHUTDOWN_TIMEOUT_MS: '500',
      HISLE_WRAPPER_PID: String(process.pid),
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const state = await readJSONLine(supervisor.stdout);
  context.after(async () => {
    try {
      process.kill(-state.grandchild_pid, 'SIGKILL');
    } catch (error) {
      if (error?.code !== 'ESRCH') throw error;
    }
    if (processExists(supervisor.pid)) {
      supervisor.kill('SIGKILL');
    }
    await fs.rm(temporaryDirectory, { recursive: true, force: true });
  });

  await waitForPath(termMarker);
  const supervisorOutcome = childOutcome(supervisor);
  supervisor.kill('SIGTERM');
  assert.deepEqual(await supervisorOutcome, { code: null, signal: 'SIGTERM' });
  await waitForProcessExit(state.grandchild_pid);
});

test('mirrors a normal observer exit code', {
  skip: process.platform === 'win32',
  timeout: 5000,
}, async (context) => {
  const temporaryDirectory = await fs.mkdtemp(path.join(os.tmpdir(), 'hisle-observer-supervisor-exit.'));
  const fixtureSource = path.join(temporaryDirectory, 'exit-observer.mjs');
  await fs.writeFile(fixtureSource, 'process.exit(7);\n', 'utf8');
  context.after(() => fs.rm(temporaryDirectory, { recursive: true, force: true }));

  const supervisor = spawn(process.execPath, [supervisorSource, fixtureSource], {
    env: {
      ...process.env,
      HISLE_WRAPPER_PID: String(process.pid),
    },
    stdio: 'ignore',
  });
  assert.deepEqual(await childOutcome(supervisor), { code: 7, signal: null });
});

test('rejects a wrapper PID that is not the initial parent', {
  skip: process.platform === 'win32',
  timeout: 5000,
}, async () => {
  const supervisor = spawn(process.execPath, [supervisorSource, 'unused-observer.mjs'], {
    env: {
      ...process.env,
      HISLE_WRAPPER_PID: String(process.pid + 100000),
    },
    stdio: ['ignore', 'ignore', 'pipe'],
  });
  const stderr = collectText(supervisor.stderr);
  assert.deepEqual(await childOutcome(supervisor), { code: 1, signal: null });
  assert.match(await stderr, /is not the supervisor's initial parent/);
});

function childOutcome(child) {
  return new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('exit', (code, signal) => resolve({ code, signal }));
  });
}

function readJSONLine(stream) {
  return new Promise((resolve, reject) => {
    let text = '';
    const timeout = setTimeout(() => reject(new Error('Timed out waiting for fixture PID record.')), 3000);
    const onData = (chunk) => {
      text += chunk;
      const newline = text.indexOf('\n');
      if (newline === -1) {
        return;
      }
      clearTimeout(timeout);
      stream.off('data', onData);
      try {
        resolve(JSON.parse(text.slice(0, newline)));
      } catch (error) {
        reject(error);
      }
    };
    stream.on('data', onData);
    stream.once('error', reject);
  });
}

function collectText(stream) {
  return new Promise((resolve, reject) => {
    let text = '';
    stream.setEncoding('utf8');
    stream.on('data', (chunk) => {
      text += chunk;
    });
    stream.once('error', reject);
    stream.once('end', () => resolve(text));
  });
}

async function waitForProcessExit(pid) {
  const deadline = Date.now() + 3000;
  while (processExists(pid)) {
    if (Date.now() >= deadline) {
      throw new Error(`Process ${pid} did not exit.`);
    }
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
}

async function waitForPath(filePath) {
  const deadline = Date.now() + 3000;
  while (true) {
    try {
      await fs.access(filePath);
      return;
    } catch (error) {
      if (error?.code !== 'ENOENT') {
        throw error;
      }
    }
    if (Date.now() >= deadline) {
      throw new Error(`Path ${filePath} did not appear.`);
    }
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
}

function processExists(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    if (error?.code === 'ESRCH') {
      return false;
    }
    if (error?.code === 'EPERM') {
      return true;
    }
    throw error;
  }
}
