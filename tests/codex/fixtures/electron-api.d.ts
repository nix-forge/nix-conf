// Minimal host contract for the disposable Electron startup probe.
declare module "electron" {
  export const app: {
    getPath(name: "userData"): string;
    exit(code: number): void;
  };
}
