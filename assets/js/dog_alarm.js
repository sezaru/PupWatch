// Per-device, so the phone can ring while the desktop stays quiet.
const KEY = "pupwatch:dog-alarm"

export const DogAlarm = {
  mounted() {
    this.toggleBtn = this.el.querySelector("[data-toggle]")
    this.stopBtn = this.el.querySelector("[data-stop]")
    this.on = localStorage.getItem(KEY) === "on"

    // Browsers only let audio start from a user gesture; after a reload any tap unlocks it.
    this.unlock = () => this.on && this.audio().resume()
    document.addEventListener("pointerdown", this.unlock)

    this.toggleBtn.addEventListener("click", () => {
      this.on = !this.on
      localStorage.setItem(KEY, this.on ? "on" : "off")
      if (!this.on) this.stop()
      this.render()
    })
    this.stopBtn.addEventListener("click", () => this.stop())

    this.handleEvent("dog_arrived", () => this.on && this.ring())
    this.handleEvent("dog_left", () => this.stop())
    this.render()
  },

  destroyed() {
    this.stop()
    document.removeEventListener("pointerdown", this.unlock)
    this.ctx?.close()
  },

  audio() {
    this.ctx ||= new AudioContext()
    return this.ctx
  },

  ring() {
    if (this.timer) return
    const ctx = this.audio()
    ctx.resume()
    let high = true

    const beep = () => {
      const t = ctx.currentTime
      const osc = ctx.createOscillator()
      const gain = ctx.createGain()
      osc.type = "square"
      osc.frequency.value = high ? 880 : 660
      gain.gain.setValueAtTime(0.2, t)
      gain.gain.setValueAtTime(0, t + 0.35)
      osc.connect(gain).connect(ctx.destination)
      osc.start(t)
      osc.stop(t + 0.36)
      high = !high
      navigator.vibrate?.(300)
    }

    beep()
    this.timer = setInterval(beep, 400)
    this.render()
  },

  stop() {
    clearInterval(this.timer)
    this.timer = null
    navigator.vibrate?.(0)
    this.render()
  },

  render() {
    this.toggleBtn.className = `btn btn-sm ${this.on ? "btn-primary" : "btn-soft"}`
    this.toggleBtn.innerHTML = this.on
      ? `<span class="hero-bell-alert size-4"></span> Dog alarm on`
      : `<span class="hero-bell-slash size-4"></span> Dog alarm off`
    this.stopBtn.classList.toggle("hidden", !this.timer)
  },
}
