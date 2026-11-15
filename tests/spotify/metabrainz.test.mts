import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { runInNewContext } from "node:vm";

const extension = process.env["METABRAINZ_EXTENSION"];
assert.ok(
  extension,
  "Pass the compiled extension through METABRAINZ_EXTENSION",
);
const source = readFileSync(extension, "utf8");

type Predicate = (uris: unknown) => boolean;
type Click = (uris: unknown) => void | Promise<void>;
type Opened = [url: string, target: string, features: string];

function loadExtension(
  response: unknown,
  options: { ready?: boolean; capabilities?: boolean } = {},
) {
  const opened: Opened[] = [];
  const requested: string[] = [];
  const notifications: string[] = [];
  let menu: Pick<SubMenu, "name" | "items" | "shouldAdd"> | undefined;
  let registrations = 0;
  let ready = options.ready ?? true;
  const readyCallbacks = new Set<() => void>();

  class Item {
    name: string;
    onClick: Click;
    shouldAdd: Predicate;

    constructor(name: string, onClick: Click, shouldAdd: Predicate) {
      this.name = name;
      this.onClick = onClick;
      this.shouldAdd = shouldAdd;
    }
  }
  class SubMenu {
    name: string;
    items: Item[];
    shouldAdd: Predicate;

    constructor(name: string, items: Item[], shouldAdd: Predicate) {
      this.name = name;
      this.items = items;
      this.shouldAdd = shouldAdd;
    }

    register(): void {
      registrations += 1;
      menu = { name: this.name, items: this.items, shouldAdd: this.shouldAdd };
    }
  }

  const context = {
    URL,
    console: { warn() {} },
    Spicetify: {
      Events: {
        webpackLoaded: {
          on(callback: () => void) {
            readyCallbacks.add(callback);
            if (ready) callback();
          },
        },
      },
      ContextMenu: { Item, SubMenu },
      URI: {
        Type: { TRACK: "track" },
        fromString(uri: string) {
          const [, type, id] = uri.split(":");
          return { type, id };
        },
      },
      CosmosAsync: {
        async get(url: string): Promise<unknown> {
          requested.push(url);
          if (response instanceof Error) throw response;
          return response;
        },
      },
      showNotification(message: string) {
        notifications.push(message);
      },
    },
    setTimeout() {
      throw new Error("Extension readiness must not poll");
    },
    window: {
      open(...args: Opened) {
        opened.push(args);
      },
    },
  };
  const capabilities = {
    URI: context.Spicetify.URI,
    CosmosAsync: context.Spicetify.CosmosAsync,
  };
  if (options.capabilities === false) {
    Reflect.deleteProperty(context.Spicetify, "URI");
    Reflect.deleteProperty(context.Spicetify, "CosmosAsync");
  }
  runInNewContext(source, context);
  return {
    get menu() {
      assert.ok(menu, "Extension must register its context menu");
      return menu;
    },
    get registrations() {
      return registrations;
    },
    opened,
    requested,
    notifications,
    ready() {
      ready = true;
      for (const callback of readyCallbacks) callback();
    },
    restoreCapabilities() {
      Object.assign(context.Spicetify, capabilities);
    },
    removeLookup() {
      Reflect.deleteProperty(context.Spicetify, "CosmosAsync");
    },
  };
}

function item(app: ReturnType<typeof loadExtension>, index: number): Click {
  const selected = app.menu.items[index];
  assert.ok(selected, `Expected menu item ${index}`);
  return selected.onClick;
}

function openedAt(
  app: ReturnType<typeof loadExtension>,
  index: number,
): Opened {
  const entry = app.opened[index];
  assert.ok(entry, `Expected opened window ${index}`);
  return entry;
}

const track = {
  name: "Song & Dance",
  artists: [{ name: "Artist One" }],
  album: { name: "Album / Vol. 2", artists: [{ name: "Artist One" }] },
};
const trackUri = ["spotify:track:abc123"];

void test("searches the selected track and encodes MusicBrainz queries", async () => {
  const app = loadExtension(track);
  assert.equal(app.menu.name, "MetaBrainz");
  assert.equal(app.menu.shouldAdd(trackUri), true);
  assert.equal(app.menu.shouldAdd(["spotify:album:abc123"]), false);
  assert.equal(app.menu.shouldAdd(undefined), false);

  await item(app, 0)(trackUri);
  assert.deepEqual(app.requested, ["https://api.spotify.com/v1/tracks/abc123"]);
  const [url, target, features] = openedAt(app, 0);
  assert.equal(target, "_blank");
  assert.equal(features, "noopener,noreferrer");
  assert.equal(new URL(url).searchParams.get("type"), "recording");
  assert.equal(
    new URL(url).searchParams.get("query"),
    "Song & Dance Artist One",
  );

  await item(app, 1)(trackUri);
  assert.equal(
    new URL(openedAt(app, 1)[0]).searchParams.get("query"),
    "Album / Vol. 2 Artist One",
  );
});

void test("rejects other item types and handles Spotify lookup failure", async () => {
  const app = loadExtension(new Error("unavailable"));
  await item(app, 0)(["spotify:album:abc123"]);
  assert.equal(app.requested.length, 0);

  await item(app, 0)(trackUri);
  assert.equal(app.opened.length, 0);
  assert.equal(app.notifications.length, 1);

  await item(app, 3)(trackUri);
  assert.equal(
    openedAt(app, 0)[0],
    "https://listenbrainz.org/settings/music-services/details/",
  );
  assert.equal(app.requested.length, 1);
});

void test("rejects a Spotify response without searchable metadata", async () => {
  const app = loadExtension({ artists: [{ name: 42 }] });
  await item(app, 2)(trackUri);
  assert.equal(app.opened.length, 0);
  assert.deepEqual(app.notifications, [
    "Could not look up this track on MusicBrainz",
  ]);
});

void test("registers from replayable readiness and observes later capabilities", async () => {
  const app = loadExtension(track, { ready: false, capabilities: false });
  assert.equal(app.registrations, 0);
  app.ready();
  assert.equal(app.registrations, 1);
  assert.equal(app.menu.shouldAdd(trackUri), false);
  app.restoreCapabilities();
  assert.equal(app.menu.shouldAdd(trackUri), true);
  await item(app, 0)(trackUri);
  assert.equal(app.opened.length, 1);
  app.ready();
  assert.equal(app.registrations, 1);
});

void test("reports unavailable lookup and uses it when it becomes ready", async () => {
  const app = loadExtension(track);
  app.removeLookup();
  await item(app, 0)(trackUri);
  assert.equal(app.notifications.length, 1);
  assert.equal(app.opened.length, 0);
  app.restoreCapabilities();
  await item(app, 0)(trackUri);
  assert.equal(app.opened.length, 1);
});
