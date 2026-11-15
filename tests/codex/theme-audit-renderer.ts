/** Browser adapter for the bundled theme validators, Markdown editor and worker. */
interface CodexAuditState {
  apply(element: HTMLElement, theme: unknown, mode: string): unknown;
  theme: unknown;
  style: string | null;
  classes: string;
  measure?: (element: Element) => number;
}
interface Window {
  codexThemeAudit?: CodexAuditState;
}
function codexAuditRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
function codexAuditCallable(
  value: unknown,
): value is (...args: unknown[]) => unknown {
  return typeof value === "function";
}
function codexAuditRequired<T>(value: T | undefined, name: string): T {
  if (value === undefined) throw Error(`Missing renderer argument: ${name}`);
  return value;
}
function codexAuditConstructor(
  value: unknown,
): value is new (options: {
  doc: string;
  parent: HTMLElement;
  extensions: unknown[];
}) => unknown {
  return typeof value === "function";
}
// oxlint-disable-next-line no-unused-vars -- CDP invokes this declaration from emitted source.
async function codexThemeRenderer(
  action: "schema" | "contrast" | "rich" | "syntax" | "cleanup",
  options: {
    initial?: string;
    settingsExport?: string;
    applyExport?: string;
    wanted?: Record<string, unknown>;
    labels?: string[];
    richModule?: string;
    themeModule?: string;
    workerModule?: string;
    modules?: Record<string, string>;
    fixtures?: Array<[string, string, string]>;
  },
): Promise<unknown> {
  const auditWindow: Window = window;
  async function bundle(file: string): Promise<Record<string, unknown>> {
    const value: unknown = await import("./assets/" + file);
    if (!codexAuditRecord(value)) throw Error(`Invalid bundle export: ${file}`);
    return value;
  }
  function safeParse(schema: unknown, value: unknown): boolean {
    if (!codexAuditRecord(schema) || !codexAuditCallable(schema["safeParse"]))
      throw Error("Missing schema validator");
    const result = schema["safeParse"](value);
    if (!codexAuditRecord(result) || typeof result["success"] !== "boolean")
      throw Error("Invalid schema validator response");
    return result["success"];
  }
  if (action === "schema") {
    const app = await bundle(codexAuditRequired(options.initial, "initial"));
    const settings =
      app[codexAuditRequired(options.settingsExport, "settingsExport")];
    if (!codexAuditRecord(settings))
      throw Error("Missing settings descriptors");
    const wanted = codexAuditRequired(options.wanted, "wanted");
    const errors: string[] = [];
    const checked: string[] = [];
    for (const [key, value] of Object.entries(wanted)) {
      const descriptor = Object.values(settings).find(
        (entry) => codexAuditRecord(entry) && entry["key"] === key,
      );
      if (
        !codexAuditRecord(descriptor) ||
        !safeParse(descriptor["schema"], value)
      )
        errors.push(key);
      else checked.push(key);
    }
    const dark = settings["darkChromeTheme"];
    const theme = wanted["appearanceDarkChromeTheme"];
    if (!codexAuditRecord(dark) || !codexAuditRecord(theme))
      throw Error("Missing dark theme schema");
    const bad = [
      { ...theme, contrast: 101 },
      { ...theme, accent: "#fff" },
      { ...theme, accentSource: "automatic" },
    ];
    const rejected = bad.filter(
      (value) => !safeParse(dark["schema"], value),
    ).length;
    const apply = app[codexAuditRequired(options.applyExport, "applyExport")];
    if (!codexAuditCallable(apply))
      throw Error("Missing theme application function");
    auditWindow.codexThemeAudit = {
      apply,
      theme,
      style: document.documentElement.getAttribute("style"),
      classes: document.documentElement.className,
    };
    const colors = auditWindow.codexThemeAudit.apply(
      document.documentElement,
      theme,
      "dark",
    );
    if (!codexAuditRecord(colors)) throw Error("Invalid derived theme colors");
    return {
      checked: checked.length,
      errors,
      rejected,
      derivedColors: Object.keys(colors).length,
      colors,
    };
  }
  const audit = codexAuditRequired(
    auditWindow.codexThemeAudit,
    "theme audit state",
  );
  if (action === "cleanup") {
    document.documentElement.className = audit.classes;
    if (audit.style === null) document.documentElement.removeAttribute("style");
    else document.documentElement.setAttribute("style", audit.style);
    delete auditWindow.codexThemeAudit;
    return undefined;
  }
  if (action === "contrast") {
    const canvas = document.createElement("canvas");
    canvas.width = canvas.height = 1;
    const context = canvas.getContext("2d");
    if (!context) throw Error("Missing canvas color parser");
    const rgba = (color: string): [number, number, number, number] => {
      context.clearRect(0, 0, 1, 1);
      context.fillStyle = color;
      context.fillRect(0, 0, 1, 1);
      const data = context.getImageData(0, 0, 1, 1).data;
      return [data[0] ?? 0, data[1] ?? 0, data[2] ?? 0, data[3] ?? 0];
    };
    const blend = (
      fg: [number, number, number, number],
      bg: number[],
    ): number[] =>
      fg
        .slice(0, 3)
        .map(
          (value, index) =>
            (value * fg[3]) / 255 +
            codexAuditRequired(bg[index], "background channel") *
              (1 - fg[3] / 255),
        );
    const luminance = (rgb: number[]): number =>
      rgb
        .map((value) => value / 255)
        .map((value) =>
          value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4,
        )
        .reduce(
          (sum, value, index) =>
            sum +
            value *
              codexAuditRequired(
                [0.2126, 0.7152, 0.0722][index],
                "luminance weight",
              ),
          0,
        );
    const ratio = (fg: number[], bg: number[]): number => {
      const a = luminance(fg),
        b = luminance(bg);
      return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
    };
    const measure = (element: Element): number => {
      const backgrounds: string[] = [];
      for (
        let parent: Element | null = element;
        parent;
        parent = parent.parentElement
      )
        backgrounds.unshift(getComputedStyle(parent).backgroundColor);
      let background = [0, 0, 0];
      for (const color of backgrounds)
        background = blend(rgba(color), background);
      return ratio(
        blend(rgba(getComputedStyle(element).color), background),
        background,
      );
    };
    audit.measure = measure;
    const results: Array<{ name: string; ratio: number }> = [];
    for (const label of options.labels ?? []) {
      const element = [...document.querySelectorAll("button")].find(
        (button) =>
          button.textContent.trim() === label &&
          button.getBoundingClientRect().width,
      );
      if (!element) throw Error("Missing UI fixture: " + label);
      results.push({ name: label, ratio: measure(element) });
    }
    const sample = document.createElement("span");
    sample.textContent = "Popup description";
    sample.style.color = "var(--color-text-foreground-tertiary)";
    sample.style.backgroundColor =
      "var(--color-background-elevated-primary-opaque)";
    document.body.append(sample);
    try {
      results.push({ name: "elevated description", ratio: measure(sample) });
    } finally {
      sample.remove();
    }
    return results.map((result) => ({
      name: result.name,
      ratio: +result.ratio.toFixed(2),
      pass: result.ratio >= 4.5,
    }));
  }
  if (action === "rich") {
    const module = await bundle(
      codexAuditRequired(options.richModule, "richModule"),
    );
    if (!codexAuditCallable(module["r"]))
      throw Error("Missing Markdown initialization");
    module["r"]();
    const editor = module["I"];
    if (!codexAuditConstructor(editor)) throw Error("Missing Markdown editor");
    const extension = module["t"];
    if (!Array.isArray(extension)) throw Error("Missing Markdown extensions");
    const root = document.createElement("div");
    document.body.append(root);
    const view = new editor({
      doc: "",
      parent: root,
      extensions: [module["n"], extension],
    });
    if (
      !codexAuditRecord(view) ||
      !(view["contentDOM"] instanceof HTMLElement) ||
      !codexAuditCallable(view["destroy"])
    ) {
      root.remove();
      throw Error("Invalid Markdown editor view");
    }
    try {
      const holder: unknown = extension.find(
        (entry: unknown) =>
          codexAuditRecord(entry) &&
          codexAuditRecord(entry["value"]) &&
          Array.isArray(entry["value"]["specs"]),
      );
      if (!codexAuditRecord(holder) || !codexAuditRecord(holder["value"]))
        throw Error("Missing Markdown highlighter");
      const highlighter = holder["value"];
      const specs: unknown = highlighter["specs"];
      if (!Array.isArray(specs) || !codexAuditCallable(highlighter["style"]))
        throw Error("Invalid Markdown highlighter");
      const results: Array<{
        weight: string;
        fontStyle: string;
        decoration: string;
      }> = [];
      for (const spec of specs as unknown[]) {
        if (!codexAuditRecord(spec))
          throw Error("Invalid Markdown style specification");
        if (!(
          spec["fontWeight"] ||
          spec["fontStyle"] ||
          spec["textDecoration"]
        ))
          continue;
        const span = document.createElement("span");
        span.textContent = "Markdown style";
        const tag = spec["tag"];
        const className = highlighter["style"](
          Array.isArray(tag) ? tag : [tag],
        );
        if (typeof className !== "string")
          throw Error("Invalid Markdown style class");
        span.className = className;
        view["contentDOM"].append(span);
        const style = getComputedStyle(span);
        results.push({
          weight: style.fontWeight,
          fontStyle: style.fontStyle,
          decoration: style.textDecorationLine,
        });
      }
      return {
        strong: results.some((style) => Number(style.weight) >= 600),
        emphasis: results.some((style) => style.fontStyle === "italic"),
        link: results.some((style) => style.decoration.includes("underline")),
        deleted: results.some((style) =>
          style.decoration.includes("line-through"),
        ),
      };
    } finally {
      view["destroy"]();
      root.remove();
    }
  }
  const theme = (
    await bundle(codexAuditRequired(options.themeModule, "themeModule"))
  )["default"];
  if (!codexAuditRecord(theme) || typeof theme["name"] !== "string")
    throw Error("Invalid Shiki theme");
  const grammars: Array<{ name: string; data: unknown }> = [];
  for (const [name, file] of Object.entries(
    codexAuditRequired(options.modules, "modules"),
  ))
    grammars.push({ name, data: (await bundle(file))["default"] });
  const worker = new Worker(
    "./assets/" + codexAuditRequired(options.workerModule, "workerModule"),
    { type: "module" },
  );
  let id = 0;
  const pending = new Map<
    number,
    {
      resolve(value: Record<string, unknown>): void;
      reject(error: Error): void;
    }
  >();
  worker.addEventListener("message", (event: MessageEvent<unknown>) => {
    const data = event.data;
    if (!codexAuditRecord(data) || typeof data["id"] !== "number") return;
    const entry = pending.get(data["id"]);
    if (!entry) return;
    pending.delete(data["id"]);
    if (data["type"] === "error") entry.reject(Error(String(data["error"])));
    else entry.resolve(data);
  });
  const send = (
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> =>
    new Promise((resolve, reject) => {
      const next = ++id;
      pending.set(next, { resolve, reject });
      // oxlint-disable-next-line unicorn/require-post-message-target-origin -- Worker messages have no window targetOrigin parameter.
      worker.postMessage({ id: next, ...body });
    });
  try {
    await send({
      type: "initialize",
      preferredHighlighter: "shiki-js",
      renderOptions: { theme: theme["name"] },
      resolvedThemes: [theme],
      resolvedLanguages: grammars,
    });
    const results = [];
    for (const [language, name, contents] of codexAuditRequired(
      options.fixtures,
      "fixtures",
    )) {
      const response = await send({
        type: "file",
        file: { name, lang: language, contents },
      });
      const result = response["result"];
      if (
        !codexAuditRecord(result) ||
        typeof result["themeStyles"] !== "string" ||
        !Array.isArray(result["code"])
      )
        throw Error("Invalid worker highlight result");
      const container = document.createElement("div");
      container.style.cssText = result["themeStyles"];
      const spans: HTMLElement[] = [];
      const render = (node: unknown, parent: HTMLElement): void => {
        if (!codexAuditRecord(node))
          throw Error("Invalid highlighted syntax node");
        if (node["type"] === "text") {
          if (typeof node["value"] !== "string")
            throw Error("Invalid highlighted text");
          parent.append(document.createTextNode(node["value"]));
          return;
        }
        if (typeof node["tagName"] !== "string")
          throw Error("Invalid highlighted tag");
        const element = document.createElement(node["tagName"]);
        const properties = node["properties"];
        if (properties !== undefined && !codexAuditRecord(properties))
          throw Error("Invalid highlighted properties");
        const style = codexAuditRecord(properties)
          ? properties["style"]
          : undefined;
        if (style !== undefined && typeof style !== "string")
          throw Error("Invalid highlighted style");
        element.style.cssText = style ?? "";
        parent.append(element);
        if (node["tagName"] === "span") spans.push(element);
        const children = node["children"] ?? [];
        if (!Array.isArray(children))
          throw Error("Invalid highlighted children");
        for (const child of children as unknown[]) render(child, element);
      };
      for (const node of result["code"] as unknown[]) render(node, container);
      document.body.append(container);
      try {
        const colored = spans.filter((element) => element.textContent.trim());
        const measure = codexAuditRequired(
          audit.measure,
          "contrast measurement",
        );
        const minimum = Math.min(...colored.map(measure));
        const distinct = new Set(
          colored.map((element) => getComputedStyle(element).color),
        ).size;
        const styles = colored.map((element) => ({
          text: element.textContent,
          weight: getComputedStyle(element).fontWeight,
          style: getComputedStyle(element).fontStyle,
          color: getComputedStyle(element).color,
        }));
        results.push({
          language,
          spans: colored.length,
          colors: distinct,
          minimumContrast: +minimum.toFixed(2),
          pass: minimum >= 4.5 && distinct >= 2,
          ...(language === "markdown"
            ? {
                boldDifferentiated: styles.some(
                  (style) =>
                    style.text.includes("bold") &&
                    style.color !== getComputedStyle(container).color,
                ),
                italic: styles.some(
                  (style) =>
                    style.text.includes("italic") && style.style === "italic",
                ),
              }
            : {}),
        });
      } finally {
        container.remove();
      }
    }
    return results;
  } finally {
    worker.terminate();
  }
}
