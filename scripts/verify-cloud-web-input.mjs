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
const document = { hasFocus: () => true, visibilityState: 'visible' };
const context = vm.createContext({ window, document, console: { info() {}, warn() {}, log() {} }, setTimeout });
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
// Focus changes cancel an already running hold; cleanup still works without focus.
const focusHold = run([command('keyDown', 'KeyA'), command('wait', 200), command('keyUp', 'KeyA')], 'new');
const focusRejection = assert.rejects(focusHold, /lost foreground focus/);
await new Promise(resolve => setTimeout(resolve, 40));
document.hasFocus = () => false;
await focusRejection;
const lostFocusCount = calls.length;
await assert.rejects(run([command('keyDown', 'KeyF')], 'new'), /lost foreground focus/);
assert.equal(calls.length, lostFocusCount);
await run([command('releaseAll')], 'new');
assert.deepEqual([...window.__ysInputInject.status().pressedKeys], []);
// Cleanup remains available after native suspension, and a partial transport failure cannot ACK.
window.__bgiMacInputEpoch = 'new';
document.hasFocus = () => true;
await run([command('keyDown', 'KeyW')], 'new');
window.__bgiMacInputEpoch = null;
core.rtcConnection.rtcDataChannel.readyState = 'closed';
await assert.rejects(run([command('releaseAll')], ''), /release failed/);
core.rtcConnection.rtcDataChannel.readyState = 'open';
await run([command('releaseAll')], '');
assert.deepEqual([...window.__ysInputInject.status().pressedKeys], []);
console.log('Cloud Web SDK focus, cancellation, deadline and owned-release checks passed.');

// Exercise the production DOM-to-video measurement used by screenshot cropping.
const host = readFileSync(root + 'MacGI/Sources/MacGI/Runtime/MacCloudWebViewHost.swift', 'utf8');
const statusScript = host.match(/private static let statusScript = #"""\n([\s\S]*?)\n    """#/)[1];
const video = {
  getBoundingClientRect: () => ({ x: 0, y: 0, width: 1280, height: 800 }),
  clientWidth: 1280, clientHeight: 800, videoWidth: 1920, videoHeight: 1080,
  paused: false, ended: false, readyState: 4, currentTime: 1,
  style: { visibility: 'visible', display: 'block', opacity: '1', objectFit: 'contain' },
};
document.querySelectorAll = () => [{ ...video, clientWidth: 2000, style: { ...video.style, visibility: 'hidden' } }, video];
context.getComputedStyle = v => v.style;
const measured = JSON.parse(vm.runInContext(`(() => {${statusScript}})()`, context)).video;
assert.deepEqual([measured.x, measured.y, measured.width, measured.height], [0, 40, 1280, 720]);
console.log('Cloud video visibility and letterbox measurement checks passed.');
