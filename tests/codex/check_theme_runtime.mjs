/**
 * Check a disposable Codex window with its own validators, CSS and Shiki worker.
 * Usage: node check_theme_runtime.mjs CDP_URL EXTRACTED_ASSETS SETTINGS_JSON
 * Start a separate app with CODEX_HOME and CODEX_ELECTRON_USER_DATA_PATH pointing
 * at private temporary directories, plus --user-data-dir and --remote-debugging-port.
 * CODEX_THEME_COLORS_ONLY=1 skips controls unavailable at the sign-in screen.
 * Never point this at a working session. No messages or menu actions are submitted.
 */
import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import { join } from "node:path";

const [endpoint, assets, configPath] = process.argv.slice(2);
assert.ok(
  configPath,
  "Expected CDP URL, extracted assets and generated settings",
);
const colorsOnly = process.env.CODEX_THEME_COLORS_ONLY === "1";
const config = JSON.parse(await readFile(configPath, "utf8")).desktop;
assert.equal(
  config.appearanceDarkCodeThemeId,
  "codex",
  "This fixture checks the selected Codex syntax preset",
);
const files = await readdir(assets);
const initial = files.find((name) => /^app-initial-.*\.js$/.test(name));
const source = await readFile(join(assets, initial), "utf8");
function exported(name) {
  const entry = source
    .slice(source.lastIndexOf("export{"))
    .split(",")
    .find((entry) => entry.replace(/^export\{/, "").startsWith(`${name} as `));
  assert.ok(
    entry,
    `Missing app export for ${name}; review this build's adapter`,
  );
  return entry.split(" as ")[1].replace(/[};].*$/, "");
}
const settingsName = source.match(
  /([\w$]+)=\{theme:[\w$]+\(\{agentAccess:`read-write`,default:`system`,description:`Preferred app appearance mode`/,
)[1];
const applyName = source.match(
  /function ([\w$]+)\(e,t,n,r,i=!0\)\{e\.classList\.toggle\(`electron-dark`/,
)[1];
const pages = await (
  await fetch(`${endpoint}/json/list`, { signal: AbortSignal.timeout(15000) })
).json();
const page = pages.find(
  (page) => page.type === "page" && page.url === "app://-/index.html",
);
assert.ok(page, "Expected isolated Codex application window");
const socket = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  const timeout = setTimeout(
    () => finish(new Error("CDP WebSocket connection timed out")),
    15000,
  );
  const opened = () => finish();
  const failed = () => finish(new Error("CDP WebSocket connection failed"));
  function finish(error) {
    clearTimeout(timeout);
    socket.removeEventListener("open", opened);
    socket.removeEventListener("error", failed);
    socket.removeEventListener("close", failed);
    if (error) {
      socket.close();
      reject(error);
    } else resolve();
  }
  socket.addEventListener("open", opened, { once: true });
  socket.addEventListener("error", failed, { once: true });
  socket.addEventListener("close", failed, { once: true });
});
let sequence = 0;
const pending = new Map();
socket.addEventListener("message", (event) => {
  const message = JSON.parse(event.data);
  if (!pending.has(message.id)) return;
  pending.get(message.id)(message);
  pending.delete(message.id);
});
function call(method, params = {}) {
  return new Promise((resolve, reject) => {
    const id = ++sequence;
    const timeout = setTimeout(() => {
      pending.delete(id);
      reject(Error(`${method} timed out`));
    }, 30000);
    pending.set(id, (message) => {
      clearTimeout(timeout);
      if (message.error) reject(Error(JSON.stringify(message.error)));
      else resolve(message.result);
    });
    socket.send(JSON.stringify({ id, method, params }));
  });
}
async function evaluate(expression) {
  const response = await call("Runtime.evaluate", {
    expression,
    awaitPromise: true,
    returnByValue: true,
  });
  assert.ok(
    !response.exceptionDetails,
    JSON.stringify(response.exceptionDetails),
  );
  return response.result.value;
}
const failures = [];
try {
  const schema = await evaluate(`(async()=>{
    const app=await import('./assets/${initial}');
    const settings=app[${JSON.stringify(exported(settingsName))}];
    const wanted=${JSON.stringify(config)};
    const errors=[];const checked=[];
    for(const [key,value] of Object.entries(wanted)){
      const descriptor=Object.values(settings).find(s=>s.key===key);
      if(!descriptor || !descriptor.schema.safeParse(value).success)errors.push(key);
      else checked.push(key);
    }
    const dark=settings.darkChromeTheme.schema;
    const bad=[{...wanted.appearanceDarkChromeTheme,contrast:101},
      {...wanted.appearanceDarkChromeTheme,accent:'#fff'},
      {...wanted.appearanceDarkChromeTheme,accentSource:'automatic'}];
    const rejected=bad.filter(x=>!dark.safeParse(x).success).length;
    globalThis.codexThemeAudit={apply:app[${JSON.stringify(exported(applyName))}],
      theme:wanted.appearanceDarkChromeTheme,
      style:document.documentElement.getAttribute('style'),
      classes:document.documentElement.className};
    const colors=codexThemeAudit.apply(document.documentElement,codexThemeAudit.theme,'dark');
    return {checked:checked.length,errors,rejected,derivedColors:Object.keys(colors).length,colors};
  })()`);
  assert.deepEqual(schema.errors, []);
  assert.equal(schema.rejected, 3);
  const { colors, ...schemaSummary } = schema;
  console.log(JSON.stringify({ schema: schemaSummary }));
  if (process.env.CODEX_THEME_COLOR_OUTPUT) {
    const { writeFile } = await import("node:fs/promises");
    await writeFile(
      process.env.CODEX_THEME_COLOR_OUTPUT,
      JSON.stringify(colors, null, 2),
    );
  }

  const contrast = await evaluate(`(()=>{
    const canvas=document.createElement('canvas');canvas.width=canvas.height=1;
    const context=canvas.getContext('2d');
    const rgba=color=>{context.clearRect(0,0,1,1);context.fillStyle=color;context.fillRect(0,0,1,1);return [...context.getImageData(0,0,1,1).data]};
    const blend=(fg,bg)=>fg.slice(0,3).map((v,i)=>v*fg[3]/255+bg[i]*(1-fg[3]/255));
    const luminance=rgb=>rgb.map(v=>v/255).map(v=>v<=.04045?v/12.92:((v+.055)/1.055)**2.4).reduce((s,v,i)=>s+v*[.2126,.7152,.0722][i],0);
    const ratio=(fg,bg)=>{const a=luminance(fg),b=luminance(bg);return (Math.max(a,b)+.05)/(Math.min(a,b)+.05)};
    const measure=element=>{const backgrounds=[];for(let p=element;p;p=p.parentElement)backgrounds.unshift(getComputedStyle(p).backgroundColor);let bg=[0,0,0];for(const c of backgrounds)bg=blend(rgba(c),bg);return ratio(blend(rgba(getComputedStyle(element).color),bg),bg)};
    codexThemeAudit.measure=measure;
    const results=[];
    for(const label of ${JSON.stringify(colorsOnly ? [] : ["File", "Edit", "View", "Help", "Choose project"])}){
      const element=[...document.querySelectorAll('button')].find(e=>e.textContent.trim()===label && e.getBoundingClientRect().width);
      if(!element)throw Error('Missing UI fixture: '+label);
      results.push({name:label,ratio:measure(element)});
    }
    const sample=document.createElement('span');sample.textContent='Popup description';
    sample.style.color='var(--color-text-foreground-tertiary)';
    sample.style.backgroundColor='var(--color-background-elevated-primary-opaque)';
    document.body.append(sample);results.push({name:'elevated description',ratio:measure(sample)});sample.remove();
    return results.map(r=>({...r,ratio:+r.ratio.toFixed(2),pass:r.ratio>=4.5}));
  })()`);
  for (const result of contrast) {
    console.log(JSON.stringify(result));
    if (!result.pass) failures.push(result.name);
  }

  // Force CSS states on a real control so compositor focus cannot hide :hover.
  // This verifies its shipped styles; it does not test pointer event delivery.
  if (!colorsOnly) {
    await call("DOM.enable");
    await call("CSS.enable");
    const { root } = await call("DOM.getDocument");
    const { nodeId } = await call("DOM.querySelector", {
      nodeId: root.nodeId,
      selector: 'button[role="menuitem"]',
    });
    const before = await evaluate(
      "getComputedStyle(document.querySelector('button[role=menuitem]')).backgroundColor",
    );
    for (const state of ["hover", "focus-visible"]) {
      await call("CSS.forcePseudoState", {
        nodeId,
        forcedPseudoClasses: [state],
      });
      const after = await evaluate(
        "getComputedStyle(document.querySelector('button[role=menuitem]')).backgroundColor",
      );
      assert.notEqual(before, after, `${state} must change the control fill`);
      console.log(JSON.stringify({ state, before, after, pass: true }));
    }
    await call("CSS.forcePseudoState", { nodeId, forcedPseudoClasses: [] });
  }

  // Exercise the app's actual rich-Markdown style extension in CodeMirror.
  // The fixture supplies tags directly; Markdown parsing is tested separately
  // by the source-highlighting worker below.
  const richModule = files.find((name) =>
    /^file-editor-theme-.*\.js$/.test(name),
  );
  const rich = await evaluate(`(async()=>{
    const m=await import('./assets/${richModule}');m.r();
    const root=document.createElement('div');document.body.append(root);
    const view=new m.I({doc:'',parent:root,extensions:[m.n,m.t]});
    try{
      const highlighter=m.t.find(x=>x.value?.specs).value;
      const results=[];
      for(const spec of highlighter.specs.filter(s=>s.fontWeight||s.fontStyle||s.textDecoration)){
        const span=document.createElement('span');span.textContent='Markdown style';
        span.className=highlighter.style(Array.isArray(spec.tag)?spec.tag:[spec.tag]);
        view.contentDOM.append(span);const style=getComputedStyle(span);
        results.push({weight:style.fontWeight,fontStyle:style.fontStyle,decoration:style.textDecorationLine});
      }
      return {strong:results.some(s=>Number(s.weight)>=600),emphasis:results.some(s=>s.fontStyle==='italic'),
        link:results.some(s=>s.decoration.includes('underline')),deleted:results.some(s=>s.decoration.includes('line-through'))};
    }finally{view.destroy();root.remove()}
  })()`);
  assert.ok(
    Object.values(rich).every(Boolean),
    "Rich Markdown must preserve text semantics",
  );
  console.log(JSON.stringify({ richMarkdown: rich }));

  const languageFixtures = [
    [
      "typescript",
      "example.ts",
      "// comment\ninterface Person { name: string; }\nconst pattern = /hello+/gi;\nconst count = 42;",
    ],
    [
      "javascript",
      "example.js",
      '// comment\nfunction greet(name) { return "Hello " + name; }',
    ],
    [
      "python",
      "example.py",
      '# comment\n@dataclass\nclass Person:\n    age: int = 42\n    name = "Ada"',
    ],
    ["nix", "example.nix", '# comment\nlet count = 42; in "hello"'],
    ["json", "example.json", '{"name": "Ada", "age": 42}'],
    ["yaml", "example.yaml", '# comment\nname: "Ada"\nage: 42'],
    ["html", "example.html", '<div class="card">Hello</div>'],
    ["css", "example.css", ".card { color: #80cbc4; margin: 1rem; }"],
    ["cpp", "example.cpp", "// comment\nnamespace Shapes { class Point {}; }"],
    [
      "java",
      "example.java",
      '// comment\nclass Person { String name = "Ada"; int age = 42; }',
    ],
    ["shellscript", "example.sh", '# comment\necho "hello"'],
    [
      "markdown",
      "example.md",
      "# Heading\n**bold** and *italic* with `code` and [link](https://example.org).",
    ],
  ];
  const modules = {};
  for (const [language] of languageFixtures) {
    const candidates = files.filter(
      (name) => name.startsWith(`${language}-`) && name.endsWith(".js"),
    );
    for (const file of candidates) {
      if ((await readFile(join(assets, file), "utf8")).includes("as default")) {
        modules[language] = file;
        break;
      }
    }
    assert.ok(modules[language], `Missing bundled grammar for ${language}`);
  }
  const themeModule = files.find((name) => /^codex-dark-.*\.js$/.test(name));
  let workerModule;
  for (const name of files.filter((name) => /^worker-.*\.js$/.test(name))) {
    const workerSource = await readFile(join(assets, name), "utf8");
    if (
      workerSource.includes("preferredHighlighter") &&
      workerSource.includes("`shiki-js`")
    ) {
      workerModule = name;
      break;
    }
  }
  assert.ok(
    workerModule,
    "Missing native Shiki worker; review this build's adapter",
  );
  const syntax = await evaluate(`(async()=>{
    const theme=(await import('./assets/${themeModule}')).default;
    const modules=${JSON.stringify(modules)};
    const grammars=[];
    for(const [name,file] of Object.entries(modules))grammars.push({name,data:(await import('./assets/'+file)).default});
    const worker=new Worker('./assets/${workerModule}',{type:'module'});
    let id=0;const pending=new Map();worker.onmessage=e=>{const entry=pending.get(e.data.id);if(entry){pending.delete(e.data.id);e.data.type==='error'?entry.reject(Error(e.data.error)):entry.resolve(e.data)}};
    const send=body=>new Promise((resolve,reject)=>{const n=++id;pending.set(n,{resolve,reject});worker.postMessage({id:n,...body})});
    try{
      await send({type:'initialize',preferredHighlighter:'shiki-js',renderOptions:{theme:theme.name},resolvedThemes:[theme],resolvedLanguages:grammars});
      const results=[];
      for(const [lang,name,contents] of ${JSON.stringify(languageFixtures)}){
        const response=await send({type:'file',file:{name,lang,contents}});
        const container=document.createElement('div');container.style.cssText=response.result.themeStyles;
        const spans=[];const text=[];
        const render=(node,parent)=>{if(node.type==='text'){parent.append(document.createTextNode(node.value));text.push(node.value);return}const el=document.createElement(node.tagName);el.style.cssText=node.properties?.style??'';parent.append(el);if(node.tagName==='span')spans.push(el);for(const child of node.children??[])render(child,el)};
        for(const node of response.result.code)render(node,container);
        document.body.append(container);
        const colored=spans.filter(el=>el.textContent.trim());
        const minimum=Math.min(...colored.map(codexThemeAudit.measure));
        const distinct=new Set(colored.map(el=>getComputedStyle(el).color)).size;
        const styles=colored.map(el=>({text:el.textContent,weight:getComputedStyle(el).fontWeight,style:getComputedStyle(el).fontStyle,color:getComputedStyle(el).color}));
        results.push({language:lang,spans:colored.length,colors:distinct,minimumContrast:+minimum.toFixed(2),pass:minimum>=4.5&&distinct>=2,
          ...(lang==='markdown'?{boldDifferentiated:styles.some(s=>s.text.includes('bold')&&s.color!==getComputedStyle(container).color),italic:styles.some(s=>s.text.includes('italic')&&s.style==='italic')}: {})});
        container.remove();
      }
      return results;
    }finally{worker.terminate()}
  })()`);
  for (const result of syntax) {
    console.log(JSON.stringify(result));
    if (
      !result.pass ||
      result.boldDifferentiated === false ||
      result.italic === false
    )
      failures.push(result.language);
  }
  assert.deepEqual(
    failures,
    [],
    "Theme must retain readable controls and syntax",
  );
} finally {
  await evaluate(
    `(()=>{const a=globalThis.codexThemeAudit;if(a){document.documentElement.className=a.classes;if(a.style===null)document.documentElement.removeAttribute('style');else document.documentElement.setAttribute('style',a.style);delete globalThis.codexThemeAudit}})()`,
  ).catch(() => {});
  socket.close();
}
