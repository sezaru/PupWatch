// WebRTC with go2rtc, signaled through the LiveView socket (go2rtc's API stays on
// localhost). The audio transceiver is sendrecv from the start so go2rtc wires the
// camera's backchannel; the mic track is only attached on the first talk press.
const RETRY_MS = 3000
// Firefox with media.peerconnection.ice.no_host only offers STUN-derived candidates.
const ICE_SERVERS = [{urls: "stun:stun.l.google.com:19302"}]
// WebRTC that hasn't produced video by then falls back to the relayed MP4 (no talk).
const WEBRTC_TIMEOUT_MS = 8000

export const LiveVideo = {
  mounted() {
    this.video = this.el.querySelector("video")
    this.connecting = this.el.querySelector("[data-connecting]")
    this.talkBtn = this.el.querySelector("[data-talk]")
    this.talkLabel = this.el.querySelector("[data-talk-label]")
    this.speakerBtn = this.el.querySelector("[data-speaker]")

    this.speakerBtn.addEventListener("click", () => this.toggleSpeaker())
    this.talkBtn.addEventListener("pointerdown", e => { e.preventDefault(); this.startTalk() })
    for (const ev of ["pointerup", "pointerleave", "pointercancel"]) {
      this.talkBtn.addEventListener(ev, () => this.stopTalk())
    }
    this.talkBtn.addEventListener("contextmenu", e => e.preventDefault())

    this.setupOverlay()
    this.handleEvent("detection", ({box}) => this.drawBox(box))

    this.connect()

    if (new URLSearchParams(location.search).has("debug")) {
      this.statsTimer = setInterval(() => this.reportStats(), 2000)
    }
  },

  // ?debug: ship receive stats to the server log, for browsers whose about:webrtc hides them
  async reportStats() {
    if (!this.pc) return
    const out = {t: Math.round(performance.now())}
    ;(await this.pc.getStats()).forEach(s => {
      if (s.type === "inbound-rtp") {
        out[s.kind] = Object.fromEntries(Object.entries(s).filter(([k, v]) => typeof v === "number" && !/timestamp/i.test(k)))
      } else if (s.type === "candidate-pair" && s.selected) {
        out.pair = {rtt: s.currentRoundTripTime, received: s.packetsReceived}
      }
    })
    const q = this.video.getVideoPlaybackQuality?.()
    if (q) out.playback = {total: q.totalVideoFrames, dropped: q.droppedVideoFrames}
    this.pushEvent("rtc_stats", out)
  },

  destroyed() {
    this.resizeObserver?.disconnect()
    clearTimeout(this.boxTimer)
    this.closed = true
    clearTimeout(this.retry)
    clearTimeout(this.fallbackTimer)
    clearInterval(this.statsTimer)
    this.pc?.close()
    this.micTrack?.stop()
  },

  async connect() {
    if (this.closed) return
    this.pc?.close()
    this.micTrack = null
    this.connecting.hidden = false

    const pc = new RTCPeerConnection({iceServers: ICE_SERVERS})
    this.pc = pc
    const stream = new MediaStream()
    this.video.srcObject = stream

    pc.addTransceiver("video", {direction: "recvonly"})
    this.audio = pc.addTransceiver("audio", {direction: "sendrecv"})
    pc.ontrack = e => stream.addTrack(e.track)
    pc.onconnectionstatechange = () => {
      if (pc !== this.pc) return
      if (pc.connectionState === "connected") {
        clearTimeout(this.fallbackTimer)
        this.connecting.hidden = true
      } else if (pc.connectionState === "failed") {
        this.fallback()
      } else if (["disconnected", "closed"].includes(pc.connectionState)) {
        this.scheduleRetry()
      }
    }
    clearTimeout(this.fallbackTimer)
    this.fallbackTimer = setTimeout(() => pc === this.pc && this.fallback(), WEBRTC_TIMEOUT_MS)

    await pc.setLocalDescription(await pc.createOffer())
    await gatheringDone(pc)

    this.pushEvent("webrtc_offer", {sdp: pc.localDescription.sdp}, async reply => {
      if (pc !== this.pc) return
      if (reply.sdp) {
        await pc.setRemoteDescription({type: "answer", sdp: reply.sdp})
      } else {
        console.warn("go2rtc:", reply.error)
        this.connecting.textContent = "Camera unavailable — retrying…"
        this.scheduleRetry()
      }
    })
  },

  fallback() {
    clearTimeout(this.fallbackTimer)
    this.pc?.close()
    this.pc = null
    this.mp4 = true
    this.video.srcObject = null
    this.video.src = "/live.mp4"
    this.video.play().catch(() => {})
    this.video.onplaying = () => { this.connecting.hidden = true }
    this.video.onerror = () => {
      this.connecting.hidden = false
      setTimeout(() => { this.video.src = "/live.mp4" }, RETRY_MS)
    }
  },

  // Boxes arrive as [x, y, w, h] fractions of the frame; the video is letterboxed
  // (object-contain), so the overlay tracks the rectangle the picture really fills.
  setupOverlay() {
    this.overlay = document.createElement("div")
    this.overlay.className = "absolute pointer-events-none"
    this.box = document.createElement("div")
    this.box.className = "absolute border-2 border-warning rounded-sm shadow-[0_0_0_1px_rgba(0,0,0,.5)] transition-all duration-300 ease-linear"
    this.box.hidden = true
    this.overlay.appendChild(this.box)
    this.el.appendChild(this.overlay)
    this.resizeObserver = new ResizeObserver(() => this.fitOverlay())
    this.resizeObserver.observe(this.video)
    this.video.addEventListener("loadedmetadata", () => this.fitOverlay())
  },

  fitOverlay() {
    const {clientWidth: cw, clientHeight: ch, videoWidth: vw, videoHeight: vh} = this.video
    if (!vw || !vh) return
    const scale = Math.min(cw / vw, ch / vh)
    const w = vw * scale, h = vh * scale
    Object.assign(this.overlay.style, {
      left: `${this.video.offsetLeft + (cw - w) / 2}px`,
      top: `${this.video.offsetTop + (ch - h) / 2}px`,
      width: `${w}px`,
      height: `${h}px`,
    })
  },

  drawBox(box) {
    clearTimeout(this.boxTimer)
    if (!box) { this.box.hidden = true; return }
    this.fitOverlay()
    const [x, y, w, h] = box.map(v => `${(v * 100).toFixed(2)}%`)
    Object.assign(this.box.style, {left: x, top: y, width: w, height: h})
    this.box.hidden = false
    // the detector only reports changes, so a silent stream shouldn't leave a stale box
    this.boxTimer = setTimeout(() => { this.box.hidden = true }, 4000)
  },

  scheduleRetry() {
    clearTimeout(this.retry)
    this.connecting.hidden = false
    this.retry = setTimeout(() => this.connect(), RETRY_MS)
  },

  toggleSpeaker() {
    this.video.muted = !this.video.muted
    const icon = this.speakerBtn.querySelector("span")
    icon.className = (this.video.muted ? "hero-speaker-x-mark" : "hero-speaker-wave") + " size-5"
  },

  async startTalk() {
    this.talking = true
    if (this.mp4) {
      this.pushEvent("talk_needs_webrtc", {})
      return
    }
    if (!window.isSecureContext || !navigator.mediaDevices) {
      this.pushEvent("talk_unavailable", {})
      return
    }
    try {
      if (!this.micTrack) {
        const media = await navigator.mediaDevices.getUserMedia({
          audio: {echoCancellation: true, noiseSuppression: true, autoGainControl: true},
        })
        this.micTrack = media.getAudioTracks()[0]
        await this.audio.sender.replaceTrack(this.micTrack)
      }
    } catch (_e) {
      this.pushEvent("mic_denied", {})
      return
    }
    // released while the permission prompt was up
    if (!this.talking) return
    this.micTrack.enabled = true
    this.talkBtn.classList.add("btn-error")
    this.talkLabel.textContent = "Talking…"
  },

  stopTalk() {
    this.talking = false
    if (this.micTrack) this.micTrack.enabled = false
    this.talkBtn.classList.remove("btn-error")
    this.talkLabel.textContent = "Hold to talk"
  },
}

function gatheringDone(pc) {
  if (pc.iceGatheringState === "complete") return Promise.resolve()
  return new Promise(resolve => {
    const done = () => pc.iceGatheringState === "complete" && resolve()
    pc.addEventListener("icegatheringstatechange", done)
    // LAN host candidates arrive almost at once; don't wait on unreachable STUN
    setTimeout(resolve, 1500)
  })
}

export const Elapsed = {
  mounted() { this.tick(); this.timer = setInterval(() => this.tick(), 1000) },
  updated() { this.tick() },
  destroyed() { clearInterval(this.timer) },
  tick() {
    const secs = Math.max(0, Math.floor((Date.now() - Date.parse(this.el.dataset.since)) / 1000))
    this.el.textContent = `${Math.floor(secs / 60)}:${String(secs % 60).padStart(2, "0")}`
  },
}
