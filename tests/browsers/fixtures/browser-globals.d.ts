// Narrow contracts for APIs provided by privileged Firefox and uBlock contexts.
declare const ChromeUtils: {
  importESModule(uri: string): {
    Troubleshoot: { snapshot(): Promise<{ graphics: unknown }> };
  };
};
declare const Services: { prefs: { getStringPref(name: string): string } };
declare const vAPI: {
  messaging: {
    send(
      channel: string,
      message: { what: string; toImport?: string },
    ): Promise<unknown>;
  };
};
declare const browser: {
  storage: { local: { get(key: string): Promise<Record<string, unknown>> } };
};
