/** The native JXA/AppKit bridge subset used by application-paths.js. */
interface JXAURL {
  path: unknown;
}
interface JXAApplication {
  bundleIdentifier: unknown;
  bundleURL: JXAURL | null;
  processIdentifier: number;
}
interface JXAArray<T> {
  count: number;
  objectAtIndex(index: number): T;
}
declare const ObjC: {
  import(name: string): void;
  unwrap(value: unknown): string;
};
declare const $: {
  NSWorkspace: {
    sharedWorkspace: {
      URLsForApplicationsWithBundleIdentifier(
        identifier: string,
      ): JXAArray<JXAURL> | null;
      runningApplications: JXAArray<JXAApplication>;
    };
  };
};
