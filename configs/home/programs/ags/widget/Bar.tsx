import { App, Astal, Gtk, Gdk } from "astal/gtk4";
import { Variable, GLib, bind } from "astal";
import Hyprland from "gi://AstalHyprland";
import Battery from "gi://AstalBattery";
import Mpris from "gi://AstalMpris";
import Wp from "gi://AstalWp";
import Network from "gi://AstalNetwork";
import Tray from "gi://AstalTray";

const wm = GLib.getenv("XDG_CURRENT_DESKTOP")?.toLowerCase();

function SysTray() {
  const tray = Tray.get_default();

  return (
    <box cssName="SysTray">
      {bind(tray, "items").as((items) =>
        items.map((item) => (
          <menubutton
            tooltipMarkup={bind(item, "tooltipMarkup")}
            actionGroup={bind(item, "actionGroup").as((ag) => ["dbusmenu", ag])}
            menuModel={bind(item, "menuModel")}
          >
            <image gicon={bind(item, "gicon")} />
          </menubutton>
        ))
      )}
    </box>
  );
}

// function to get current application open name
function get_current_app() {
  const app = App.get_active_window();
  if (app) {
    return app.get_title();
  }
  return "No active window";
}

function FocusedClient() {
  const hypr = Hyprland.get_default();
  const focused = bind(hypr, "focusedClient");

  return (
    <box cssName="Focused" visible={focused.as(Boolean)}>
      {focused.as(
        (client) => client && <label label={bind(client, "title").as(String)} />
      )}
    </box>
  );
}

export default function Bar(monitor: Gdk.Monitor) {
  const { TOP, LEFT, RIGHT } = Astal.WindowAnchor;

  return (
    <window
      name={`Bar-${monitor.get_model()}`}
      cssClasses={["Bar"]}
      gdkmonitor={monitor}
      visible={true}
      exclusivity={Astal.Exclusivity.EXCLUSIVE}
      anchor={TOP | LEFT | RIGHT}
      application={App}
      // layer={Astal.Layer.TOP}
      // halign={Gtk.Align.FILL}
      // valign={Gtk.Align.FILL}
      // defaultHeight={1}
    >
      <centerbox halign={Gtk.Align.FILL}>
        <box hexpand halign={Gtk.Align.START}>
          <button>Hello</button>
        </box>
        <box hexpand halign={Gtk.Align.CENTER}>
          <FocusedClient />
        </box>
        <box hexpand halign={Gtk.Align.END}>
          <button>Hello3</button>
        </box>
      </centerbox>
    </window>
  );
}
