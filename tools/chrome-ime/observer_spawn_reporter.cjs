const childProcess = require('node:child_process');
const { syncBuiltinESMExports } = require('node:module');

const originalSpawn = childProcess.spawn;

childProcess.spawn = function reportedSpawn(command, args, options) {
  const child = originalSpawn.apply(this, arguments);
  const spawnOptions = Array.isArray(args) ? options : args;
  if (spawnOptions?.detached === true && child.pid && process.connected) {
    try {
      process.send?.({
        type: 'hisle-detached-child',
        pid: child.pid,
      });
    } catch {
      // The supervisor also polls the process tree while the observer is alive.
    }
  }
  return child;
};

syncBuiltinESMExports();
