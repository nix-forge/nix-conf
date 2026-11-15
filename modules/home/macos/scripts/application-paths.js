/// <reference path="./jxa.d.ts" />
/* global ObjC, $ */

// osascript calls this entry point; return JSON without localized display names.
/** @param {string[]} identifiers @returns {string} */
// eslint-disable-next-line no-unused-vars
function run(identifiers) {
  ObjC.import("AppKit");
  const workspace = $.NSWorkspace.sharedWorkspace;
  /** @type {Record<string, {available: string[], running: {pid: number, path: string}[]}>} */
  const result = {};
  for (const identifier of identifiers) {
    const available = [];
    const urls = workspace.URLsForApplicationsWithBundleIdentifier(identifier);
    if (urls) {
      for (let i = 0; i < urls.count; i++) {
        available.push(ObjC.unwrap(urls.objectAtIndex(i).path));
      }
    }
    result[identifier] = { available, running: [] };
  }
  const running = workspace.runningApplications;
  for (let i = 0; i < running.count; i++) {
    const app = running.objectAtIndex(i);
    const identifier = ObjC.unwrap(app.bundleIdentifier);
    const entry = result[identifier];
    if (Object.hasOwn(result, identifier) && entry && app.bundleURL) {
      entry.running.push({
        pid: app.processIdentifier,
        path: ObjC.unwrap(app.bundleURL.path),
      });
    }
  }
  return JSON.stringify(result);
}
