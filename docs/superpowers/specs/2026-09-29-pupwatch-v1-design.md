# PupWatch v1 — design

Supersedes `2026-09-02-pupwatch-design.md` (zones + "doing its business" state machine).
v1 is simpler: **detect the dog, record a clip while it's there, keep a history, and give
a live page with talk + pan/tilt.**

## Goals

- Watch the Tapo C200 24/7 on snorlax; whenever a dog is in frame, record an mp4 clip.
- Browse/play/delete past clips.
- Live page: low-latency stream, hold-to-talk through the camera speaker, pan/tilt pad.
- Built on **Ash Framework** so the actions can later back a JSON API for a DMS widget.

## Non-goals (v1)

DMS widget / JSON API, desktop notifications, pee-vs-poop, detection zones, pre-roll,
automatic retention, app-level login (LAN-only).

## Architecture (all on snorlax)

```
Tapo C200 ──tapo:// (video + 2-way audio)──► go2rtc (services.go2rtc, 127.0.0.1:1984 API,
    ▲                                          │                 127.0.0.1:8554 RTSP)
    │ ONVIF :2020 (PTZ)                        │ RTSP restream        :8555 WebRTC media (LAN)
    │                                          ▼
    └────────────────── PupWatch (Phoenix + Ash + LiveView, :30030)
                          ├─ FrameReader  ffmpeg → raw BGR frames (~3 fps) from the substream
                          ├─ Detector     YOLOX-nano via Evision DNN, COCO class 16 (dog)
                          ├─ Presence     pure arrive/leave state machine
                          ├─ Recorder     ffmpeg -c copy of the HD stream per visit
                          ├─ Camera.Onvif SOAP RelativeMove / GotoHomePosition
                          └─ Ash domain   PupWatch.Monitor (Recording, Camera)
```

- **go2rtc** owns the only camera session (`tapo://<cloud-password>@<ip>` for HD +
  backchannel audio; `…?subtype=1` for the substream). Everything else consumes it.
- **WebRTC signaling goes through Phoenix**: the browser builds an `RTCPeerConnection`
  (recvonly video+audio, sendrecv audio for talk), pushes the SDP offer over the
  LiveView socket, the server POSTs it to go2rtc's `127.0.0.1:1984/api/webrtc?src=…`
  and returns the answer. go2rtc's API never leaves localhost; only the media port 8555
  is opened.
- **FrameReader uses an ffmpeg Port** (`-vf fps=3,scale=… -f rawvideo -pix_fmt bgr24 -`)
  rather than OpenCV's videoio — fewer native surprises, same ffmpeg the Recorder uses.
  Evision is only used for DNN inference, drawing the bbox, and JPEG encoding.

## Data (Ash + AshSqlite)

SQLite file at `/mnt/main/apps/data/pupwatch/pupwatch.db` (WAL), clips + thumbs beside it.

`PupWatch.Monitor.Recording`

| attribute | type | notes |
|---|---|---|
| id | uuid | |
| started_at / ended_at | utc_datetime_usec | ended_at nil while recording |
| status | atom | `:recording \| :complete \| :failed` |
| clip_path / thumbnail_path | string | relative to the storage root |
| peak_confidence | float | |
| duration_seconds | calculation | |

Actions: `:start`, `:finish`, `:fail`, `:history` (newest first, keyset-paginated),
`:destroy` (after-action change deletes files). `Ash.Notifier.PubSub` broadcasts
create/update/destroy.

`PupWatch.Monitor.Camera` — no data layer, generic actions: `move(direction)`, `home()`,
`status()` (detector state: `:watching | :dog_present | :offline`, current recording id).

## Detection & recording

- Detector runs YOLOX-nano (416×416 letterbox, grid/stride decode, NMS) on the latest
  frame ~3×/s; keeps dogs with score ≥ 0.5; whole frame (no zone — PTZ would break it).
- `Presence` (pure, timestamps passed in): `:idle` → dog in 2 of last 3 frames →
  `:present` (emit `{:dog_arrived, frame, bbox, score}`); track peak; 10 s without a
  dog → emit `:dog_left` → `:idle`.
- Recorder on arrival: thumbnail JPEG (bbox drawn) → `Recording.start` → ffmpeg Port
  `-rtsp_transport tcp -i rtsp://127.0.0.1:8554/tapo -c copy -movflags +faststart`.
  On leave: `q` to stdin, await exit, `Recording.finish`. 5-minute cap rolls into a new clip.

### Errors

- Stream down → FrameReader restarts ffmpeg with backoff (1 s → 30 s); status `:offline`;
  an in-progress clip is finished as-is.
- ffmpeg recorder dies early / non-zero → `Recording.fail` (keep non-empty file).
- Boot: any `:recording` row → `:failed`.
- ONVIF failure → action error → flash. No retries.
- Supervisor `one_for_one` over FrameReader / Detector / Recorder.

## Pages (LiveView)

- `/` — live video (WebRTC via hook), status badge (Watching / Dog detected + REC timer /
  Camera offline), PTZ pad (arrows + home), hold-to-talk, strip of latest 6 clips.
- `/recordings` — thumbnail grid, infinite scroll (LiveView streams over `:history`),
  modal player; mp4 served by `/clips/:id` with Range support; delete.
- Default Phoenix 1.8 + daisyUI, dark, mobile-friendly.

## Deployment

`flake/nixos/pupwatch/` in the nixos repo, listed in `flake/hosts/snorlax.nix`:
- `services.go2rtc` with the Tapo source (cloud password via sops, rendered into config
  at start), `webrtc.listen :8555`, candidates `<snorlax-ip>:8555`.
- `pupwatch` systemd service running the mix release (packaged with `mixRelease`),
  `PHX_SERVER=true`, `PORT=30030`, storage `/mnt/main/apps/data/pupwatch`.
- Firewall: TCP 30030, TCP+UDP 8555. pfSense HAProxy provides the `*.home.sezdm.com`
  HTTPS name — **required for talk** (browsers only grant the mic on secure origins);
  video and PTZ work over plain HTTP.
- Secrets: Tapo cloud password (go2rtc), camera account user/password (ONVIF),
  `SECRET_KEY_BASE`.

## Testing

- Unit: `Presence`, YOLOX decode on fixture frames, ONVIF SOAP/digest builder.
- Integration: Detector over a fixture mp4 (FrameReader reads files like RTSP); Recorder
  against a local file source (`-re`), checking ffprobe-valid mp4 + row lifecycle + fail
  + boot recovery; Ash resource tests on SQLite; LiveView PubSub/delete tests.
- Manual on snorlax: live feed, PTZ, talk, walk the dog → clip → play → delete.
