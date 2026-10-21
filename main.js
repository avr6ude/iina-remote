const { mpv, core, event, ws, utils, menu, sidebar, console } = iina;

const HTTP_PORT = 8765;
const WS_PORTS = { first: 8766, last: 8781 };
const PROPS = new Set(["pause", "volume", "mute", "sid", "aid", "speed", "sub-delay", "audio-delay", "sub-visibility"]);
const PLAYLIST = new Set(["playlist-next", "playlist-prev"]);
const SEEK_MODES = new Set(["relative", "absolute"]);
const RECENT_LIMIT = 15;

const base = utils.resolvePath("~/Library/Application Support/com.colliderli.iina/plugins/com.avrdude.iina-remote");
const dir = [".iinaplugin-dev", ".iinaplugin"].map((ext) => base + ext).find((d) => utils.fileInPath(`${d}/main.js`));

const conns = new Set();
let port = WS_PORTS.first;
let sent = "";
let sentLibrary = "";
let ticks = 0;
const inbox = [];
let host = "";

function state() {
  return {
    kind: "state",
    host,
    title: mpv.getString("media-title") || "",
    pause: mpv.getFlag("pause"),
    time: mpv.getNumber("time-pos") || 0,
    duration: mpv.getNumber("duration") || 0,
    volume: mpv.getNumber("volume"),
    volumeMax: mpv.getNumber("volume-max"),
    mute: mpv.getFlag("mute"),
    speed: mpv.getNumber("speed"),
    sid: mpv.getString("sid"),
    aid: mpv.getString("aid"),
    subVisible: mpv.getFlag("sub-visibility"),
    subDelay: mpv.getNumber("sub-delay"),
    audioDelay: mpv.getNumber("audio-delay"),
    chapter: mpv.getNumber("chapter"),
    playlistPos: mpv.getNumber("playlist-pos"),
    tracks: (mpv.getNative("track-list") || [])
      .filter((t) => t.type === "audio" || t.type === "sub")
      .map((t) => ({ id: t.id, type: t.type, title: t.title || "", lang: t.lang || "" })),
  };
}

const fileTitle = (path) => decodeURIComponent(path.split("/").pop()).replace(/\.[^.]+$/, "");

function recent() {
  const current = mpv.getString("path");
  const seen = new Set();
  return (core.getHistory() || [])
    .sort((a, b) => new Date(b.date) - new Date(a.date))
    .filter((h) => {
      if (seen.has(h.url) || decodeURIComponent(h.url).replace(/^file:\/\//, "") === current) return false;
      seen.add(h.url);
      return true;
    })
    .slice(0, RECENT_LIMIT)
    .map((h) => ({ title: fileTitle(h.name), url: h.url, progress: h.progress || 0, duration: h.duration || 0 }));
}

function library() {
  return {
    kind: "library",
    playlist: (mpv.getNative("playlist") || []).map((e) => ({ title: fileTitle(e.filename), current: !!e.current })),
    chapters: (core.getChapters() || []).map((c) => ({ title: c.title || "", start: c.start })),
    recent: recent(),
  };
}

function handle({ set, value, cmd, args = [] }) {
  if (PROPS.has(set)) {
    mpv.set(set, value === true ? "yes" : value === false ? "no" : String(value));
  } else if (cmd === "seek" && isFinite(args[0]) && SEEK_MODES.has(args[1])) {
    mpv.command("seek", [String(args[0]), args[1]]);
  } else if (PLAYLIST.has(cmd)) {
    mpv.command(cmd, []);
  } else if (cmd === "playlist-play-index" && Number.isInteger(args[0])) {
    mpv.command("playlist-play-index", [String(args[0])]);
  } else if (cmd === "chapter" && Number.isInteger(args[0])) {
    mpv.set("chapter", String(args[0]));
  } else if (cmd === "open-recent" && recent().some((r) => r.url === args[0])) {
    core.open(args[0]);
  } else {
    return;
  }
  sent = sentLibrary = "";
}

function send(json) {
  for (const conn of conns) ws.sendText(conn, json).catch(() => conns.delete(conn));
}

function broadcast() {
  if (!conns.size) return;
  const json = JSON.stringify(state());
  if (json === sent) return;
  send((sent = json));
}

function broadcastLibrary() {
  if (!conns.size) return;
  const json = JSON.stringify(library());
  if (json === sentLibrary) return;
  send((sentLibrary = json));
}

function listen(p) {
  port = p;
  ws.createServer({ port });
  ws.startServer();
}

async function sendQR() {
  const r = await utils.exec("/usr/bin/osascript", ["-l", "JavaScript", `${dir}/qr.js`, String(HTTP_PORT), String(port)]);
  if (r.status) {
    console.log(`iina-remote: qr.js: ${r.stderr}`);
    return core.osd("Remote: couldn't create QR code");
  }
  sidebar.postMessage("qr", JSON.parse(r.stdout));
}

ws.onStateUpdate((s, err) => {
  if (s === "ready") return utils.exec("/bin/sh", [`${dir}/helper.sh`, String(port), String(HTTP_PORT), dir]);
  if (s !== "failed") return;
  if (port < WS_PORTS.last) return listen(port + 1);
  console.log(`iina-remote: no free port: ${err && err.message}`);
});
// These callbacks run on the WebSocket queue; IINA's core API blocks on the main thread,
// so they only record work and the main-thread timer below does it.
ws.onConnectionStateUpdate((conn, s) => {
  if (s === "ready") {
    conns.add(conn);
    sent = sentLibrary = "";
  } else if (s === "failed" || s === "cancelled") {
    conns.delete(conn);
  }
});
ws.onMessage((conn, message) => {
  try {
    inbox.push(JSON.parse(message.text()));
  } catch (e) {
    console.log(`iina-remote: bad message: ${e}`);
  }
});

function tick() {
  while (inbox.length) handle(inbox.shift());
  ticks += 1;
  if (sent === "" || ticks % 10 === 0) broadcast();
  if (sentLibrary === "" || ticks % 40 === 0) broadcastLibrary();
}

function loadSidebar() {
  sidebar.loadFile("sidebar.html");
  sidebar.onMessage("ready", sendQR);
}

event.on("iina.window-loaded", loadSidebar);
menu.addItem(menu.item("Show Remote QR Code", () => {
  loadSidebar();
  sidebar.show();
}));
utils.exec("/usr/sbin/scutil", ["--get", "ComputerName"]).then((r) => (host = r.stdout.trim()));
listen(WS_PORTS.first);
setInterval(tick, 50);
