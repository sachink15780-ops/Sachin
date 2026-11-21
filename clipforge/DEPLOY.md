# ClipForge AI (FastAPI + FFmpeg)

ClipForge AI extracts highlight clips from an uploaded video or an authorized YouTube URL.

## Run locally
Install Python 3.11+, FFmpeg, then:
```bash
cd clipforge/backend
pip install -r requirements.txt
uvicorn app:app --host 0.0.0.0 --port 8000
```

Open http://localhost:8000.

## Hugging Face Spaces (Docker) deployment
This project includes a Dockerfile and listens on port 10000. To deploy it to Hugging Face Spaces:
1. Create a new Space and select **Docker** as the SDK.
2. Add the contents of `clipforge/backend` to the Space repository root (Dockerfile, app.py, index.html, requirements.txt).
3. Wait for the Space to build. The first processing run downloads the Whisper model.
4. Note: free Spaces may sleep, have limited CPU/RAM, and temporary storage is not persistent. Large uploads and lengthy jobs may fail. Never upload copyrighted videos you do not have permission to process.

This GitHub repository branch is not itself a live public app; deployment requires a hosting account and Space creation.
