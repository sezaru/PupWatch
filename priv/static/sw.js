// Only page loads go through here, so the app never serves stale LiveView pages; when
// the server can't be reached the installed app shows a hint instead of the browser's error.
self.addEventListener("install", () => self.skipWaiting())
self.addEventListener("activate", (e) => e.waitUntil(self.clients.claim()))

self.addEventListener("fetch", (e) => {
  if (e.request.mode !== "navigate") return

  e.respondWith(
    fetch(e.request).catch(
      () =>
        new Response(
          `<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
<body style="margin:0;display:grid;place-items:center;height:100vh;background:#ff8a3d;color:#fff;font:16px system-ui">
<div style="text-align:center"><p>PupWatch is unreachable.</p><button onclick="location.reload()">Retry</button></div>`,
          {headers: {"content-type": "text/html; charset=utf-8"}},
        ),
    ),
  )
})
