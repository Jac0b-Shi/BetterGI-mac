// Exercise the production WK bridge body with the vendored upstream SDK.
// Only the remote ClientCore transport is replaced; no browser or live account is used.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
const root = fileURLToPath(new URL('../', import.meta.url));
assert.deepEqual(readFileSync(root + "MacGI/Sources/MacGI/Resources/CloudGame/ys-input-inject.js"),
                 readFileSync(root + "BetterGenshinImpact/Resources/JavaScript/ys-input-inject.js"));
const native = readFileSync(root + 'MacGI/Sources/MacGI/Runtime/WKWebInputBridge.swift', 'utf8');
const script = native.match(/private static let executionScript = #"""\n([\s\S]*?)\n    """#/)[1];
const calls = [];
const core = {
  rtcConnection: { rtcDataChannel: { readyState: 'open' } }, gameDataChannel: { isStarted: true },
  keyboardKeyDown: e => calls.push(['down', e.code]), keyboardKeyUp: e => calls.push(['up', e.code]),
};
const window = { __ysWebpackRequire: () => ({ $: core }), __bgiMacInputEpoch: 'old', __bgiMacInputReadyUntil: Date.now() + 2000 };
const context = vm.createContext({ window, console: { info() {}, warn() {}, log() {} }, setTimeout });
vm.runInContext(readFileSync(root + 'MacGI/Sources/MacGI/Resources/CloudGame/ys-input-inject.js', 'utf8'), context);
const run = (commands, epoch, deadline = Date.now() + 2000) => {
  Object.assign(context, { commandsJSON: JSON.stringify(commands), epoch, deadline });
  return vm.runInContext(`(async (commandsJSON,epoch,deadline) => {${script}})(commandsJSON,epoch,deadline)`, context);
};
const command = (method, ...args) => ({ method, args });
// A cancelled hold must never emit a late KeyUp into a newer session using the same key.
const oldHold = run([command('keyDown', 'KeyW'), command('wait', 200), command('keyUp', 'KeyW')], 'old');
const rejection = assert.rejects(oldHold, /cancelled/);
await new Promise(resolve => setTimeout(resolve, 40));
window.__bgiMacInputEpoch = null;
window.__ysInputInject.releaseAll();
window.__bgiMacInputEpoch = 'new';
await run([command('keyDown', 'KeyW')], 'new');
await rejection;
assert.deepEqual(calls, [['down','KeyW'],['up','KeyW'],['down','KeyW']]);
assert.deepEqual([...window.__ysInputInject.status().pressedKeys], ['KeyW']);
await assert.rejects(run([command('keyDown', 'KeyF')], 'new', Date.now()-1), /expired/);
assert.equal(calls.length, 3);
window.__bgiMacInputReadyUntil = Date.now()-1;
await assert.rejects(run([command('keyDown', 'KeyF')], 'new'), /expired/);
window.__bgiMacInputReadyUntil = Date.now()+2000;
assert.equal(calls.length, 3);
// Cleanup remains available after native suspension, and a partial transport failure cannot ACK.
window.__bgiMacInputEpoch = null;
core.rtcConnection.rtcDataChannel.readyState = 'closed';
await assert.rejects(run([command('releaseAll')], ''), /release failed/);
core.rtcConnection.rtcDataChannel.readyState = 'open';
await run([command('releaseAll')], '');
assert.deepEqual([...window.__ysInputInject.status().pressedKeys], []);
console.log('Cloud Web SDK cancellation, deadline and owned-release checks passed.');
