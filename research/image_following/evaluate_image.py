"""Headless CYOLO smoke/latency evaluation. Never trains or modifies weights.

External repositories are supplied by path; no upstream code or user media is
vendored. The saved filterbank is restored directly from the checkpoint so the
legacy madmom installation is unnecessary. Not an accuracy claim without GT.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import sys
import time
import types

import cv2
import numpy as np
import soundfile as sf
import torch
import torchaudio


def load_model(cyolo, checkpoint):
    state = torch.load(checkpoint, map_location='cpu', weights_only=True)
    state = {k.removeprefix('module.'): v for k, v in state.items()}
    saved_filter = state['spec_module.fbank'].numpy().copy()
    # Constructor compatibility only: use the actual saved filter, not a new or
    # approximated spectral representation. Strict restore checks all buffers.
    for name in ['madmom', 'madmom.audio', 'madmom.audio.stft', 'madmom.audio.spectrogram']:
        sys.modules[name] = types.ModuleType(name)
    sys.modules['madmom.audio.stft'].fft_frequencies = lambda *_: None
    sys.modules['madmom.audio.spectrogram'].LogarithmicFilterbank = lambda *_, **__: saved_filter.copy()
    if not hasattr(torchaudio, 'set_audio_backend'):
        torchaudio.set_audio_backend = lambda _: None
    sys.path.insert(0, str(cyolo))
    from cyolo_score_following.models.yolo import Model
    config = json.loads(checkpoint.with_name('net_config.json').read_text())
    model = Model(config)
    model.load_state_dict(state, strict=True)
    assert torch.equal(model.spec_module.fbank, state['spec_module.fbank'])
    model.eval()
    return model


def get_pages(args):
    if args.demo_npz:
        data = np.load(args.demo_npz, allow_pickle=True)
        return data['sheets'], list(data['coords'])
    import pymupdf
    document = pymupdf.open(args.pdf)
    pages = []
    for i in range(min(2, len(document))):
        pix = document[i].get_pixmap(colorspace=pymupdf.csGRAY, matrix=pymupdf.Matrix(2, 2))
        image = np.frombuffer(pix.samples, dtype=np.uint8).reshape(pix.height, pix.width)
        image = cv2.adaptiveThreshold(image, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 11, 5)
        pages.append(cv2.resize(image, (835, 1181), interpolation=cv2.INTER_AREA))
    return np.stack(pages), None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--cyolo', type=Path, required=True)
    parser.add_argument('--page-turner', type=Path, required=True)
    parser.add_argument('--audio', type=Path, required=True, help='Mono 22050Hz WAV')
    parser.add_argument('--pdf', type=Path)
    parser.add_argument('--demo-npz', type=Path)
    parser.add_argument('--seconds', type=float, default=20)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    torch.set_num_threads(1)
    started = time.perf_counter()
    model = load_model(args.cyolo, args.page_turner / 'models/test_model/best_model.pt')
    model_load_s = time.perf_counter()-started
    started = time.perf_counter()
    sheets, truth = get_pages(args)
    page_load_s = time.perf_counter()-started
    spec = importlib.util.spec_from_file_location('page_utils', args.page_turner / 'page_turner/utils.py')
    utils = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(utils)
    systems = [utils.find_system_ys(cv2.cvtColor(p.astype(np.float32)/255, cv2.COLOR_GRAY2BGR)) for p in sheets]
    height, width = sheets[0].shape
    pad = (height-width)//2
    scores = np.pad(sheets, ((0,0),(0,0),(pad,height-width-pad)), constant_values=255)
    scores = [torch.from_numpy(cv2.resize(1-p.astype(np.float32)/255,(416,416),interpolation=cv2.INTER_AREA))[None,None] for p in scores]
    signal, rate = sf.read(args.audio, dtype='float32')
    if rate != 22050 or signal.ndim != 1:
        raise ValueError('Convert evaluation input to mono 22050 Hz first')
    signal = signal[:round(args.seconds*rate)]
    rows, hidden, previous_y = [], None, None
    times = []
    scale = height/416
    # Fixed first page deliberately: isolates image localization from page policy.
    # Results must not be described as a validated automatic page-turn test.
    with torch.inference_mode():
        for start in range(0,len(signal)-2048+1,1102):
            begin = time.perf_counter()
            frame = torch.from_numpy(signal[start:start+2048])
            features = model.compute_spec([frame],tempo_aug=False)[0]
            z, hidden = model.conditioning_network.get_conditioning(features,hidden)
            candidates, _ = model.predict(scores[0],z)
            candidates = candidates[0,candidates[0,:,-1]==0].cpu().numpy()
            candidates = candidates[np.argsort(-candidates[:,4])]
            candidates[:,:4] *= scale
            candidates[:,0] -= pad
            if previous_y is None:
                mask = (candidates[:,1]>=systems[0][0,0]) & (candidates[:,1]<=systems[0][0,1]) & (candidates[:,0]<0.3*width)
            else:
                idx = int(np.argmin([abs(previous_y-(a+b)/2) for a,b in systems[0]]))
                lo, hi = systems[0][max(0,idx-1),0], systems[0][min(len(systems[0])-1,idx+1),1]
                mask = (candidates[:,1]>=lo) & (candidates[:,1]<=hi)
            allowed = candidates[mask]
            best = allowed[0] if len(allowed) else candidates[0]
            previous_y = float(best[1])
            elapsed = time.perf_counter()-begin
            times.append(elapsed)
            row = dict(t=(start+2048)/rate,x=float(best[0]),y=float(best[1]),confidence=float(best[4]),latency_ms=elapsed*1000)
            if truth:
                prior = [c for c in truth if c['onset']<=row['t']]
                if prior:
                    onset = prior[-1]['onset']
                    notes = [c for c in prior if c['onset']==onset]
                    gt = notes[0]
                    row.update(gt_page=int(gt['page_nr']),gt_x=float(np.mean([c['note_x'] for c in notes])),gt_y=float(gt['note_y']))
            rows.append(row)
    result = dict(model_load_s=model_load_s,two_page_preparation_s=page_load_s,
        parameters=sum(p.numel() for p in model.parameters()),threads=1,torch=torch.__version__,
        model_bytes=(args.page_turner/'models/test_model/best_model.pt').stat().st_size,
        sheet_systems=[s.tolist() for s in systems],frames=len(rows),audio_seconds=len(signal)/rate,
        inference_s=sum(times),median_latency_ms=float(np.median(times)*1000),p95_latency_ms=float(np.percentile(times,95)*1000),
        fixed_first_page=True,ground_truth=truth is not None,rows=rows)
    if truth:
        valid=[r for r in rows if r.get('gt_page')==0 and r['t']>1]
        # Membership in the system that contains the known annotated note.
        hits=[]
        for r in valid:
            expected=int(np.argmin([abs(r['gt_y']-(a+b)/2) for a,b in systems[0]]))
            a,b=systems[0][expected]
            hits.append(a<=r['y']<=b)
        result['system_hit_fraction']=float(np.mean(hits)) if hits else None
        result['median_x_error_px']=float(np.median([abs(r['x']-r['gt_x']) for r in valid])) if valid else None
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2))
    print(json.dumps({k:v for k,v in result.items() if k!='rows'},indent=2),flush=True)

if __name__=='__main__':
    main()
