from fastapi import FastAPI, UploadFile, File, Form, BackgroundTasks, HTTPException
from fastapi.responses import FileResponse, HTMLResponse
from pathlib import Path
import uuid, subprocess, shutil, json, os, re, threading

ROOT=Path(__file__).resolve().parent
DATA=ROOT/'data'; DATA.mkdir(exist_ok=True)
JOBS={}; LOCK=threading.Lock()
app=FastAPI(title='ClipForge AI',version='0.1')

@app.get('/',response_class=HTMLResponse)
def home():
    return (ROOT/'index.html').read_text(encoding='utf-8')

@app.get('/api/jobs/{job_id}')
def job_status(job_id:str):
    if job_id not in JOBS: raise HTTPException(404,'Job not found')
    return JOBS[job_id]
@app.get('/api/jobs/{job_id}/clips')
def job_clips(job_id:str):
    if job_id not in JOBS: raise HTTPException(404,'Job not found')
    return JOBS[job_id].get('clips',[])
@app.get('/api/clips/{job_id}/{filename}')
def download_clip(job_id:str,filename:str):
    p=DATA/job_id/'clips'/filename
    if not p.is_file() or p.parent.resolve() != (DATA/job_id/'clips').resolve(): raise HTTPException(404)
    return FileResponse(p,media_type='video/mp4',filename=filename)

def start_job(source:Path,job_id:str,count:int,clip_len:int):
    job_dir=DATA/job_id; clips_dir=job_dir/'clips'; clips_dir.mkdir(parents=True,exist_ok=True)
    JOBS[job_id]={'id':job_id,'status':'processing','progress':5,'message':'Preparing video…','clips':[]}
    try:
        if not shutil.which('ffmpeg'): raise RuntimeError('FFmpeg is not installed on the server')
        probe=subprocess.run(['ffprobe','-v','error','-show_entries','format=duration','-of','json',str(source)],capture_output=True,text=True,check=True)
        duration=float(json.loads(probe.stdout)['format']['duration'])
        if duration<8: raise RuntimeError('Video is too short to make clips (minimum 8 seconds).')
        JOBS[job_id].update(progress=15,message='Transcribing audio…')
        try:
            from faster_whisper import WhisperModel
            model=WhisperModel('small',device='cpu',compute_type='int8')
            segments,info=model.transcribe(str(source),language=None,word_timestamps=False,vad_filter=True)
            segs=[{'start':float(s.start),'end':float(s.end),'text':s.text.strip()} for s in segments]
        except Exception as e:
            raise RuntimeError('Transcription failed: '+str(e))
        JOBS[job_id].update(progress=45,message='Ranking moments and rendering clips…')
        # Candidate windows use speech segments, favouring dense, emphatic text; fallback evenly spaced cuts.
        candidates=[]
        for s in segs:
            a=max(0,s['start']-clip_len*0.35); b=min(duration,a+clip_len)
            words=len(re.findall(r'\\w+',s['text']))
            score=min(99,35+words*3+min(20,len(s['text'])//8))
            candidates.append((score,a,b,s['text']))
        if not candidates:
            candidates=[(50,max(0,min(duration-clip_len,i*duration/max(1,count))),min(duration,max(0,min(duration-clip_len,i*duration/max(1,count)))+clip_len),'') for i in range(count)]
        candidates.sort(key=lambda x:x[0],reverse=True)
        picked=[]
        for c in candidates:
            if all(abs(c[1]-p[1])>clip_len*0.6 for p in picked): picked.append(c)
            if len(picked)>=count: break
        picked.sort(key=lambda x:x[1]); out=[]
        for i,(score,a,b,txt) in enumerate(picked,1):
            name=f'clip_{i:02d}.mp4'; target=clips_dir/name
            # Portrait crop: center crop, safe fallback if video is landscape.
            cmd=['ffmpeg','-y','-ss',str(a),'-i',str(source),'-t',str(b-a),'-vf','scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920','-c:v','libx264','-preset','veryfast','-crf','23','-c:a','aac','-b:a','128k','-movflags','+faststart',str(target)]
            subprocess.run(cmd,capture_output=True,check=True)
            out.append({'index':i,'filename':name,'url':f'/api/clips/{job_id}/{name}','start':round(a,2),'end':round(b,2),'score':score,'title':(txt[:65] or f'Highlight {i}'),'transcript':txt})
            JOBS[job_id].update(progress=45+int(50*i/max(1,len(picked))),message=f'Rendering clip {i}/{len(picked)}…')
        JOBS[job_id].update(status='done',progress=100,message='Finished',clips=out)
    except Exception as e:
        JOBS[job_id].update(status='error',progress=100,message=str(e))

@app.post('/api/process/upload')
async def upload(background:BackgroundTasks,file:UploadFile=File(...),count:int=Form(10),clip_len:int=30):
    ext=Path(file.filename or 'video.mp4').suffix.lower()
    if ext not in ['.mp4','.mov','.mkv','.webm','.avi']: raise HTTPException(400,'Unsupported video format')
    jid=uuid.uuid4().hex[:12]; d=DATA/jid; d.mkdir(parents=True,exist_ok=True); p=d/('source'+ext)
    size=0
    with p.open('wb') as f:
        while chunk:=await file.read(1024*1024):
            size+=len(chunk)
            if size>1_000_000_000: p.unlink(missing_ok=True); raise HTTPException(413,'Video exceeds 1 GB upload limit')
            f.write(chunk)
    JOBS[jid]={'id':jid,'status':'queued','progress':0,'message':'Queued','clips':[]}
    background.add_task(start_job,p,jid,max(1,min(count,20)),max(10,min(clip_len,90)))
    return {'job_id':jid}
@app.post('/api/process/url')
def process_url(background:BackgroundTasks,url:str=Form(...),count:int=Form(10),clip_len:int=Form(30)):
    if not re.match(r'^https?://(www\\.)?(youtube\\.com|youtu\\.be)/',url): raise HTTPException(400,'Only YouTube links are supported')
    jid=uuid.uuid4().hex[:12]; d=DATA/jid; d.mkdir(parents=True,exist_ok=True); p=d/'source.mp4'
    JOBS[jid]={'id':jid,'status':'queued','progress':0,'message':'Downloading video…','clips':[]}
    def download_then_process():
        try:
            subprocess.run(['yt-dlp','-f','bestvideo[height<=1080]+bestaudio/best[height<=1080]','--merge-output-format','mp4','-o',str(p),url],capture_output=True,check=True)
            start_job(p,jid,max(1,min(count,20)),max(10,min(clip_len,90)))
        except Exception as e: JOBS[jid].update(status='error',progress=100,message='Download failed: '+str(e))
    background.add_task(download_then_process)
    return {'job_id':jid}
