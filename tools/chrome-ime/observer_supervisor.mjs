import { execFile, spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import process from 'node:process';
import { promisify } from 'node:util';

const DEFAULT_SHUTDOWN_TIMEOUT_MILLISECONDS = 8000;
const GROUP_POLL_INTERVAL_MILLISECONDS = 25;
const POST_KILL_TIMEOUT_MILLISECONDS = 5000;
const FORWARDED_SIGNALS = ['SIGINT', 'SIGTERM', 'SIGHUP'];
const execFileAsync = promisify(execFile);
const spawnReporterSource = fileURLToPath(new URL('./observer_spawn_reporter.cjs', import.meta.url));

await main().catch((error) => {
  console.error(error?.stack ?? String(error));
  process.exit(1);
});

async function main() {
  if (process.platform === 'win32') {
    throw new Error('observer_supervisor.mjs requires POSIX process groups.');
  }

  const observerSource = process.argv[2];
  if (!observerSource) {
    throw new Error('Usage: node observer_supervisor.mjs <observer-source> [observer-arguments...]');
  }

  const shutdownTimeoutMilliseconds = parseNonnegativeInteger(
    process.env.HISLE_OBSERVER_SHUTDOWN_TIMEOUT_MS,
    DEFAULT_SHUTDOWN_TIMEOUT_MILLISECONDS,
    'HISLE_OBSERVER_SHUTDOWN_TIMEOUT_MS',
  );
  const keepOpenRequested = [
    process.env.HISLE_CHROME_KEEP_OPEN,
    process.env.HISLE_FIREFOX_KEEP_OPEN,
    process.env.HISLE_ATLASSIAN_KEEP_OPEN,
  ].includes('1');
  const wrapperPID = validateInitialWrapperPID(process.env.HISLE_WRAPPER_PID);

  let child;
  let firstShutdownSignal = null;
  let resolveShutdownRequest;
  const shutdownRequest = new Promise((resolve) => {
    resolveShutdownRequest = resolve;
  });

  const requestShutdown = (signal) => {
    if (!firstShutdownSignal) {
      firstShutdownSignal = signal;
      resolveShutdownRequest(signal);
    }
  };
  const signalHandlers = new Map(FORWARDED_SIGNALS.map((signal) => {
    const handler = () => requestShutdown(signal);
    process.on(signal, handler);
    return [signal, handler];
  }));

  try {
    child = spawn(
      process.execPath,
      ['--require', spawnReporterSource, observerSource, ...process.argv.slice(3)],
      {
        detached: true,
        env: {
          ...process.env,
          HISLE_SUPERVISOR_PID: String(process.pid),
        },
        stdio: ['inherit', 'inherit', 'inherit', 'ipc'],
      },
    );
  } catch (error) {
    removeSignalHandlers(signalHandlers);
    throw error;
  }

  const childOutcome = new Promise((resolve) => {
    let settled = false;
    const finish = (outcome) => {
      if (!settled) {
        settled = true;
        resolve(outcome);
      }
    };
    child.once('error', (error) => finish({ error }));
    child.once('exit', (code, signal) => finish({ code, signal }));
  });
  const ownedProcessGroups = new Set(child.pid ? [child.pid] : []);
  child.on('message', (message) => {
    if (
      message?.type === 'hisle-detached-child' &&
      Number.isSafeInteger(message.pid) &&
      message.pid > 0
    ) {
      ownedProcessGroups.add(message.pid);
    }
  });
  let refreshInFlight = null;
  const refreshOwnedProcessGroups = () => {
    if (refreshInFlight) {
      return refreshInFlight;
    }
    if (!child.pid || !processExists(child.pid)) {
      return Promise.resolve();
    }
    refreshInFlight = recordDescendantProcessGroups(child.pid, ownedProcessGroups)
      .finally(() => {
        refreshInFlight = null;
      });
    return refreshInFlight;
  };
  await refreshOwnedProcessGroups();
  const descendantWatch = setInterval(() => {
    void refreshOwnedProcessGroups().catch((error) => {
      console.error(`Failed to inspect observer descendants: ${error?.stack ?? error}`);
    });
  }, 50);
  descendantWatch.unref();

  const wrapperWatch = wrapperPID == null ? null : setInterval(() => {
    if (process.ppid !== wrapperPID || !processExists(wrapperPID)) {
      requestShutdown('SIGTERM');
    }
  }, 100);
  wrapperWatch?.unref();

  const winner = await Promise.race([
    childOutcome.then((outcome) => ({ type: 'child-exit', outcome })),
    shutdownRequest.then((signal) => ({ type: 'shutdown', signal })),
  ]);

  if (wrapperWatch) {
    clearInterval(wrapperWatch);
  }

  if (winner.type === 'child-exit') {
    clearInterval(descendantWatch);
    await refreshOwnedProcessGroups().catch(() => {});
    const shouldTransferOwnership = (
      !winner.outcome.error &&
      winner.outcome.code === 0 &&
      keepOpenRequested &&
      !firstShutdownSignal
    );
    if (!shouldTransferOwnership && processGroupsExist(ownedProcessGroups)) {
      await shutdownProcessGroups({
        child,
        childOutcome,
        processGroupIDs: ownedProcessGroups,
        refreshProcessGroups: refreshOwnedProcessGroups,
        initialSignal: firstShutdownSignal ?? 'SIGTERM',
        timeoutMilliseconds: shutdownTimeoutMilliseconds,
      });
    }
    const exitSignal = firstShutdownSignal;
    removeSignalHandlers(signalHandlers);
    if (exitSignal) {
      await exitWithSignal(exitSignal);
      return;
    }
    if (winner.outcome.error) {
      throw winner.outcome.error;
    }
    await mirrorChildExit(winner.outcome.code, winner.outcome.signal);
    return;
  }

  await shutdownProcessGroups({
    child,
    childOutcome,
    processGroupIDs: ownedProcessGroups,
    refreshProcessGroups: refreshOwnedProcessGroups,
    initialSignal: winner.signal,
    timeoutMilliseconds: shutdownTimeoutMilliseconds,
  });
  clearInterval(descendantWatch);
  removeSignalHandlers(signalHandlers);
  await exitWithSignal(winner.signal);
}

async function shutdownProcessGroups({
  child,
  childOutcome,
  processGroupIDs,
  refreshProcessGroups,
  initialSignal,
  timeoutMilliseconds,
}) {
  if (!child.pid) {
    await childOutcome;
    return;
  }

  await refreshProcessGroups();
  signalProcessGroups(processGroupIDs, initialSignal);
  const exitedGracefully = await waitForProcessGroupsExit(
    processGroupIDs,
    timeoutMilliseconds,
    refreshProcessGroups,
  );
  if (!exitedGracefully) {
    signalProcessGroups(processGroupIDs, 'SIGKILL');
  }

  await childOutcome;

  if (!exitedGracefully) {
    const killed = await waitForProcessGroupsExit(
      processGroupIDs,
      POST_KILL_TIMEOUT_MILLISECONDS,
      refreshProcessGroups,
    );
    if (!killed) {
      throw new Error(`Observer process groups ${[...processGroupIDs].join(', ')} survived SIGKILL.`);
    }
  }
}

async function waitForProcessGroupsExit(processGroupIDs, timeoutMilliseconds, refreshProcessGroups) {
  const deadline = Date.now() + timeoutMilliseconds;
  while (processGroupsExist(processGroupIDs)) {
    if (Date.now() >= deadline) {
      return false;
    }
    await refreshProcessGroups();
    await delay(Math.min(GROUP_POLL_INTERVAL_MILLISECONDS, Math.max(1, deadline - Date.now())));
  }
  return true;
}

function signalProcessGroups(processGroupIDs, signal) {
  for (const processGroupID of processGroupIDs) {
    signalProcessGroup(processGroupID, signal);
  }
}

function processGroupsExist(processGroupIDs) {
  return [...processGroupIDs].some(processGroupExists);
}

function signalProcessGroup(processGroupID, signal) {
  try {
    process.kill(-processGroupID, signal);
    return true;
  } catch (error) {
    if (error?.code === 'ESRCH') {
      return false;
    }
    throw error;
  }
}

function processGroupExists(processGroupID) {
  try {
    process.kill(-processGroupID, 0);
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

async function recordDescendantProcessGroups(rootPID, processGroupIDs) {
  const { stdout } = await execFileAsync('/bin/ps', ['-axo', 'pid=,ppid=,pgid=']);
  const childrenByParent = new Map();
  for (const line of stdout.split('\n')) {
    const [pidText, parentPIDText, processGroupIDText] = line.trim().split(/\s+/);
    const pid = Number(pidText);
    const parentPID = Number(parentPIDText);
    const processGroupID = Number(processGroupIDText);
    if (![pid, parentPID, processGroupID].every(Number.isInteger)) {
      continue;
    }
    const children = childrenByParent.get(parentPID) ?? [];
    children.push({ pid, processGroupID });
    childrenByParent.set(parentPID, children);
  }

  const pendingParents = [rootPID];
  const visited = new Set(pendingParents);
  while (pendingParents.length > 0) {
    const parentPID = pendingParents.pop();
    for (const child of childrenByParent.get(parentPID) ?? []) {
      if (child.processGroupID > 0) {
        processGroupIDs.add(child.processGroupID);
      }
      if (!visited.has(child.pid)) {
        visited.add(child.pid);
        pendingParents.push(child.pid);
      }
    }
  }
}

function validateInitialWrapperPID(text) {
  if (text == null || text === '') {
    return null;
  }
  if (!/^[1-9][0-9]*$/.test(text)) {
    throw new Error(`Invalid HISLE_WRAPPER_PID: ${text}`);
  }

  const wrapperPID = Number(text);
  if (!Number.isSafeInteger(wrapperPID) || process.ppid !== wrapperPID) {
    throw new Error(
      `HISLE_WRAPPER_PID ${text} is not the supervisor's initial parent ${process.ppid}.`,
    );
  }
  if (!processExists(wrapperPID)) {
    throw new Error(`HISLE_WRAPPER_PID ${text} is not running.`);
  }
  return wrapperPID;
}

function parseNonnegativeInteger(text, fallback, name) {
  if (text == null || text === '') {
    return fallback;
  }
  if (!/^(0|[1-9][0-9]*)$/.test(text)) {
    throw new Error(`${name} must be a nonnegative integer.`);
  }
  const value = Number(text);
  if (!Number.isSafeInteger(value)) {
    throw new Error(`${name} is too large.`);
  }
  return value;
}

async function mirrorChildExit(code, signal) {
  if (signal) {
    await exitWithSignal(signal);
    return;
  }
  process.exit(code ?? 1);
}

async function exitWithSignal(signal) {
  process.kill(process.pid, signal);
  await delay(1000);
  throw new Error(`Failed to terminate supervisor with ${signal}.`);
}

function removeSignalHandlers(signalHandlers) {
  for (const [signal, handler] of signalHandlers) {
    process.off(signal, handler);
  }
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}
