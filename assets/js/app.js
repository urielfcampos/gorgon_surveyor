// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/gorgon_survey"
import ScreenCapture from "./hooks/screen_capture"
import LogStreamer from "./hooks/log_streamer"
import OverlayCanvas from "./hooks/overlay_canvas"
import topbar from "../vendor/topbar"

const Hooks = { ...colocatedHooks, ScreenCapture, LogStreamer, OverlayCanvas }

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks,
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// Handle Tauri commands from LiveView events
window.addEventListener("phx:select_game_window", async (e) => {
  const sessionId = e.detail && e.detail.session_id || "default"
  if (window.__TAURI__) {
    try {
      const { invoke } = window.__TAURI__.core
      await invoke("create_overlay_window", { sessionId })
      console.log("[tauri] Overlay window created for session:", sessionId)
    } catch (err) {
      console.error("[tauri] Failed to create overlay:", err)
      alert("Failed to create overlay window: " + err)
    }
  } else {
    console.warn("Not running inside Tauri — overlay not available")
  }
})

window.addEventListener("phx:trigger_capture", async (e) => {
  if (window.__TAURI__) {
    try {
      const { invoke } = window.__TAURI__.core
      const detail = e.detail || {}
      const params = { sessionId: detail.session_id || "default" }

      // Pass detect zone if available
      if (detail.detect_zone) {
        params.zoneX1 = detail.detect_zone.x1
        params.zoneY1 = detail.detect_zone.y1
        params.zoneX2 = detail.detect_zone.x2
        params.zoneY2 = detail.detect_zone.y2
      }

      const result = await invoke("capture_and_detect", params)
      console.log("[tauri] Capture result:", result)
    } catch (err) {
      console.error("[tauri] Capture failed:", err)
    }
  }
})

window.addEventListener("phx:set_collect_hotkey", async (e) => {
  if (window.__TAURI__) {
    try {
      const { invoke } = window.__TAURI__.core;
      const key = e.detail && e.detail.key || "";
      await invoke("set_collect_hotkey", { key });
      console.log("[tauri] Collect hotkey set to:", key);
    } catch (err) {
      console.error("[tauri] Failed to set collect hotkey:", err);
    }
  }
});

// Force overlay window repaint — workaround for WebKitGTK transparent window bug (tauri#12800)
window.addEventListener("phx:refresh_overlay", async () => {
  console.log("[sidebar] phx:refresh_overlay event received, __TAURI__:", !!window.__TAURI__)
  if (window.__TAURI__) {
    try {
      const { invoke } = window.__TAURI__.core
      await invoke("refresh_overlay")
      console.log("[sidebar] refresh_overlay invoke completed")
    } catch (err) {
      console.error("[sidebar] Failed to refresh overlay:", err)
    }
  }
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

