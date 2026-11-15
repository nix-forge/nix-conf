import type { NativeRequire } from "../../../tests/typescript/native-require.mts";
declare const require: NativeRequire;
type Appearance = {
  verticalPosition?: number;
  textSize?: string;
  textColor?: string;
};
type Settings = {
  currentUserId: string;
  getSubtitleAppearanceSettings(user?: string): Appearance;
  setSubtitleAppearanceSettings(value: Appearance, user?: string): void;
};
// Exercise the actual upstream getter and setter, with only storage stubbed.
const assert: typeof import("node:assert/strict") = require("node:assert/strict");
const fs: typeof import("node:fs") = require("node:fs");
const vm: typeof import("node:vm") = require("node:vm");
const sourcePath = process.argv[2];
assert.ok(sourcePath, "Expected upstream settings source path");
const source = fs
  .readFileSync(sourcePath, "utf8")
  .replace(/^import .*;\r?\n/gm, "")
  .replace(/^export /gm, "");
const saved: Map<string, unknown> = new Map();
const context = {
  appSettings: {
    /** @param {string} key @param {string} user */
    get: (key: string, user: string) => saved.get(`${user}/${key}`),
    /** @param {string} key @param {unknown} value @param {string} user */
    set: (key: string, value: unknown, user: string) =>
      saved.set(`${user}/${key}`, value),
  },
  Events: { trigger() {} },
};
// The VM boundary loads the actual upstream implementation exercised below.
const SettingsConstructor: unknown = vm.runInNewContext(
  `${source}\nUserSettings;`,
  context,
);
assert.ok(typeof SettingsConstructor === "function");
const instance: unknown = Reflect.construct(SettingsConstructor, []);
function isSettings(value: unknown): value is Settings {
  return (
    value !== null &&
    typeof value === "object" &&
    "getSubtitleAppearanceSettings" in value &&
    typeof value.getSubtitleAppearanceSettings === "function" &&
    "setSubtitleAppearanceSettings" in value &&
    typeof value.setSubtitleAppearanceSettings === "function"
  );
}
assert.ok(isSettings(instance), "Invalid upstream settings contract");
const settings = instance;
settings.currentUserId = "first";
const defaults = JSON.stringify(settings.getSubtitleAppearanceSettings());
const original = settings.getSubtitleAppearanceSettings();
const defaultTextColor = original.textColor;
original.verticalPosition = 42;
assert.equal(settings.getSubtitleAppearanceSettings().verticalPosition, -3);
settings.setSubtitleAppearanceSettings({
  textSize: "larger",
  textColor: "#ffff00",
});
assert.equal(settings.getSubtitleAppearanceSettings().textSize, "larger");
assert.equal(settings.getSubtitleAppearanceSettings().textColor, "#ffff00");
settings.currentUserId = "second";
assert.equal(
  JSON.stringify(settings.getSubtitleAppearanceSettings()),
  defaults,
);
settings.currentUserId = "first";
assert.equal(settings.getSubtitleAppearanceSettings().textSize, "larger");
settings.setSubtitleAppearanceSettings(
  { textColor: "#00ff00" },
  "another-profile",
);
assert.equal(
  settings.getSubtitleAppearanceSettings("another-profile").textColor,
  "#00ff00",
);
assert.equal(settings.getSubtitleAppearanceSettings().textColor, "#ffff00");
settings.currentUserId = "second";
assert.equal(
  settings.getSubtitleAppearanceSettings("another-profile").textColor,
  defaultTextColor,
);
console.log(
  "Caption settings preserve local edits and isolate account defaults.",
);
