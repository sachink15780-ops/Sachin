# ClipForge AI

A mobile-first video clipping web app. Upload a video or submit an accessible YouTube URL to generate vertical short clips. This implementation is an independent starter, not a copy of the referenced project.

## Run locally

Install Python 3.10–3.12, FFmpeg, then:
```bash
cd clipforge/backend
python -m venv .venv
# Windows: .venv\\Scripts\\activate | macOS/Linux: source .venv/bin/activate
pip install -r requirements.txt
uvicorn app:app --host 0.0.0.0 --port 8000
```
Open `http://localhost:8000`. Processing uses FFmpeg and Whisper; first Whisper run downloads its model. YouTube sources must be publicly accessible and you must have permission to use them. Never use this to bypass access controls.

## Status
This repo contains an initial functional upload/link processing backend and UI. Run it on a machine/server with FFmpeg installed. No hosting is configured yet.
