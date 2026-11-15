// Only the VS Code host API used by the two disposable probe extensions.
// The extensions are copied as raw CommonJS, so keep these declarations separate.
declare module "vscode" {
  export const Range: new (
    startLine: number,
    startCharacter: number,
    endLine: number,
    endCharacter: number,
  ) => {
    readonly start: { line: number; character: number };
    readonly end: { line: number; character: number };
  };
  export interface CodeLens {
    range: InstanceType<typeof Range>;
    command?: { title: string; command: string };
  }
  export const CodeLens: new (
    range: InstanceType<typeof Range>,
    command: { title: string; command: string },
  ) => CodeLens;
  export const languages: {
    registerCodeLensProvider(
      selector: { scheme: string },
      provider: { provideCodeLenses(): CodeLens[] },
    ): { dispose(): void };
  };
  export interface Uri {
    readonly scheme: string;
  }
  export const Uri: { parse(value: string): Uri };
  export const workspace: { fs: { readFile(uri: Uri): Thenable<Uint8Array> } };
  export const version: string;
  interface Thenable<T> extends PromiseLike<T> {}
}
