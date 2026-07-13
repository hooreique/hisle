import assert from 'node:assert/strict';
import http from 'node:http';
import test from 'node:test';

import {
  AsyncCleanupStack,
  ObserverLifecycle,
  closeConnectedChromium,
  closeFirefoxSession,
  closeHttpServer,
} from './observer_lifecycle.mjs';

test('runs cleanup in LIFO order, continues after errors, and memoizes disposal', async () => {
  const lifecycle = new AsyncCleanupStack();
  const calls = [];
  const failure = new Error('trace stop failed');

  lifecycle.defer('http-server', async () => calls.push('http-server'));
  lifecycle.defer('trace', async () => {
    calls.push('trace');
    throw failure;
  });
  lifecycle.defer('browser', async () => calls.push('browser'));

  const firstDisposal = lifecycle.dispose();
  const secondDisposal = lifecycle.dispose();
  assert.strictEqual(firstDisposal, secondDisposal);

  const result = await firstDisposal;
  assert.deepEqual(calls, ['browser', 'trace', 'http-server']);
  assert.deepEqual(result.errors, [{ label: 'trace', error: failure }]);
  assert.equal(lifecycle.disposeRequested, true);
  assert.strictEqual(ObserverLifecycle, AsyncCleanupStack);
});

test('waits for a pending acquisition and closes the late-acquired resource', async () => {
  const lifecycle = new AsyncCleanupStack();
  const resource = { name: 'late browser' };
  const calls = [];
  let resolveAcquisition;

  const acquisition = lifecycle.acquire(
    'chromium-context',
    () => new Promise((resolve) => {
      resolveAcquisition = resolve;
    }),
    async (acquired) => calls.push(acquired.name),
  );
  const disposal = lifecycle.dispose();

  let disposalSettled = false;
  disposal.then(() => {
    disposalSettled = true;
  });
  await Promise.resolve();
  assert.equal(disposalSettled, false);

  resolveAcquisition(resource);
  assert.strictEqual(await acquisition, resource);
  assert.deepEqual(await disposal, { errors: [] });
  assert.deepEqual(calls, ['late browser']);

  await assert.rejects(
    lifecycle.acquire('too-late', async () => ({}), async () => {}),
    /after disposal was requested/,
  );
  assert.throws(
    () => lifecycle.defer('too-late', async () => {}),
    /after disposal was requested/,
  );
});

test('closeHttpServer releases a listening port and tolerates repeated cleanup', async () => {
  const server = http.createServer((_request, response) => response.end('ok'));
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      server.off('error', reject);
      resolve();
    });
  });
  const address = server.address();
  assert.ok(address && typeof address === 'object');

  await closeHttpServer(server);
  await closeHttpServer(server);

  const replacement = http.createServer();
  await new Promise((resolve, reject) => {
    replacement.once('error', reject);
    replacement.listen(address.port, '127.0.0.1', () => {
      replacement.off('error', reject);
      resolve();
    });
  });
  await closeHttpServer(replacement);
});

test('closeHttpServer accepts promise-based and already-stopped test doubles', async () => {
  let promiseCloseCount = 0;
  await closeHttpServer({
    listening: true,
    async close() {
      promiseCloseCount += 1;
    },
  });
  assert.equal(promiseCloseCount, 1);

  let stoppedCloseCount = 0;
  await closeHttpServer({
    listening: false,
    close() {
      stoppedCloseCount += 1;
    },
  });
  assert.equal(stoppedCloseCount, 0);
});

test('closeFirefoxSession kills geckodriver even when driver quit fails', async () => {
  const calls = [];
  const quitFailure = new Error('Firefox quit failed');

  await assert.rejects(
    closeFirefoxSession({
      driver: {
        async quit() {
          calls.push('driver.quit');
          throw quitFailure;
        },
      },
      service: {
        async kill() {
          calls.push('service.kill');
        },
      },
    }),
    (error) => {
      assert.ok(error instanceof AggregateError);
      assert.deepEqual(error.cleanupErrors, [
        { label: 'firefox-driver', error: quitFailure },
      ]);
      return true;
    },
  );
  assert.deepEqual(calls, ['driver.quit', 'service.kill']);
});

test('closeFirefoxSession reports both driver and geckodriver errors', async () => {
  const driverFailure = new Error('driver');
  const serviceFailure = new Error('service');

  await assert.rejects(
    closeFirefoxSession({
      driver: { quit: async () => { throw driverFailure; } },
      service: { kill: async () => { throw serviceFailure; } },
    }),
    (error) => {
      assert.deepEqual(error.cleanupErrors, [
        { label: 'firefox-driver', error: driverFailure },
        { label: 'geckodriver-service', error: serviceFailure },
      ]);
      return true;
    },
  );
});

test('owned connected Chromium receives Browser.close before disconnect and process cleanup', async () => {
  const calls = [];
  const session = {
    async send(command) {
      calls.push(`send:${command}`);
    },
  };
  const browser = {
    async newBrowserCDPSession() {
      calls.push('new-session');
      return session;
    },
    async close() {
      calls.push('disconnect');
    },
  };

  await closeConnectedChromium({
    browser,
    owned: true,
    ensureOwnedProcessStopped: async () => calls.push('ensure-process-stopped'),
  });

  assert.deepEqual(calls, [
    'new-session',
    'send:Browser.close',
    'disconnect',
    'ensure-process-stopped',
  ]);
});

test('reused connected Chromium is only disconnected', async () => {
  const calls = [];
  const browser = {
    async newBrowserCDPSession() {
      calls.push('unexpected-session');
    },
    async close() {
      calls.push('disconnect');
    },
  };

  await closeConnectedChromium({
    browser,
    owned: false,
    ensureOwnedProcessStopped: async () => calls.push('unexpected-process-stop'),
  });
  assert.deepEqual(calls, ['disconnect']);
});

test('owned Chromium cleanup continues through CDP and disconnect errors', async () => {
  const calls = [];
  const cdpFailure = new Error('CDP close failed');
  const disconnectFailure = new Error('disconnect failed');

  await assert.rejects(
    closeConnectedChromium({
      owned: true,
      browser: {
        async newBrowserCDPSession() {
          return {
            async send(command) {
              calls.push(command);
              throw cdpFailure;
            },
          };
        },
        async close() {
          calls.push('disconnect');
          throw disconnectFailure;
        },
      },
      ensureOwnedProcessStopped: async () => calls.push('process-stopped'),
    }),
    (error) => {
      assert.deepEqual(error.cleanupErrors, [
        { label: 'chromium-browser-close', error: cdpFailure },
        { label: 'chromium-disconnect', error: disconnectFailure },
      ]);
      return true;
    },
  );
  assert.deepEqual(calls, ['Browser.close', 'disconnect', 'process-stopped']);
});
