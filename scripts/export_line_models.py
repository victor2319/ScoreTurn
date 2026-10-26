"""Export the MIT CYOLO checkpoint for offline mobile inference.
Usage: python scripts/export_line_models.py /path/to/cyolo_score_following
Requires torch, torchaudio, onnx, onnxruntime and evaluate_image.py dependencies.
The compatibility loader restores the checkpoint's exact spectral filterbank.
"""
import hashlib,json,sys
from pathlib import Path
import numpy as np
import torch
import onnxruntime as ort
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'research/image_following'))
from evaluate_image import load_model

torch.set_num_threads(1)
source=Path(sys.argv[1]).resolve()
checkpoint=source/'trained_models/cyolo_sb_a/best_model.pt'
assert hashlib.sha256(checkpoint.read_bytes()).hexdigest()=='904db3167fa58245eeee6e533e4eaf64ec2190d699b9a58b2710378c624d4490'
model=load_model(source,checkpoint)
# Legacy code passes bool as ELU alpha. Preserve its numeric value explicitly;
# current TorchScript exporter rejects boolean Scalar arguments.
for module in model.modules():
 if isinstance(module,torch.nn.ELU):
  module.alpha=float(module.alpha)
  module.inplace=False
out=ROOT/'assets/line_model';out.mkdir(parents=True,exist_ok=True)
class ImagePredictor(torch.nn.Module):
 def __init__(self,m):super().__init__();self.network=m
 def forward(self,image,audio_context):
  predictions=self.network.predict(image,audio_context)[0]
  positions=predictions[:,:predictions.shape[1]//3,:5]
  _,indices=torch.topk(positions[:,:,4],64,dim=1)
  return torch.gather(positions,1,indices.unsqueeze(-1).expand(-1,-1,5))
class AudioContext(torch.nn.Module):
 def __init__(self,c):super().__init__();self.conditioning=c
 def forward(self,history,h,c):
  last=self.conditioning.enc(history)
  z=self.conditioning.z_enc(torch.cat((h[-1],last),-1))
  _,(next_h,next_c)=self.conditioning.seq_model(last.unsqueeze(0),(h,c))
  return z,next_h,next_c
image=ImagePredictor(model).eval();context=AudioContext(model.conditioning_network).eval()
x=torch.zeros(1,1,416,416);z=torch.zeros(1,128)
history=torch.zeros(1,1,40,78)
with torch.inference_mode():
 _,(initial_h,initial_c)=model.conditioning_network.seq_model(torch.zeros(1,1,32))
 torch.onnx.export(image,(x,z),str(out/'image.onnx'),input_names=['image','audio_context'],output_names=['boxes'],dynamo=False,opset_version=17)
 torch.onnx.export(context,(history,initial_h,initial_c),str(out/'context.onnx'),input_names=['history','h','c'],output_names=['audio_context','next_h','next_c'],dynamo=False,opset_version=17)
 fbank=model.spec_module.fbank.cpu().numpy().astype('<f4')
 (out/'filterbank.f32').write_bytes(fbank.tobytes())
 metadata={'version':1,'sampleRate':22050,'frameSize':2048,'hopSize':1102,'bands':78,'historyFrames':40,'imageSize':416,'initialH':initial_h.flatten().tolist(),'initialC':initial_c.flatten().tolist(),'source':'https://github.com/CPJKU/cyolo_score_following','commit':'4b34947a9b7cc19a139ce3768eac6079aaff5cfe','checkpointSha256':hashlib.sha256(checkpoint.read_bytes()).hexdigest()}
 (out/'metadata.json').write_text(json.dumps(metadata))
 (out/'LICENSE').write_text((source/'LICENSE').read_text())
 options=ort.SessionOptions();options.intra_op_num_threads=1;options.inter_op_num_threads=1
 ctx=ort.InferenceSession(str(out/'context.onnx'),sess_options=options,providers=['CPUExecutionProvider'])
 img=ort.InferenceSession(str(out/'image.onnx'),sess_options=options,providers=['CPUExecutionProvider'])
 # Verify streaming history and LSTM update schedule, not only isolated zero input.
 torch.manual_seed(17)
 h,c=initial_h.clone(),initial_c.clone();hist=[];hidden=None
 for i in range(90):
  feature=torch.rand(1,78);hist.append(feature);hist=hist[-40:]
  expected,hidden=model.conditioning_network.get_conditioning(feature,hidden)
  padded=torch.cat([torch.zeros(max(0,40-len(hist)),78),torch.cat(hist)])[None,None]
  actual=ctx.run(None,{'history':padded.numpy(),'h':h.numpy(),'c':c.numpy()})
  np.testing.assert_allclose(actual[0],expected.numpy(),rtol=2e-4,atol=2e-4)
  if (i+1)%40==0:h=torch.from_numpy(actual[1]);c=torch.from_numpy(actual[2])
 for _ in range(3):
  pixels=torch.rand_like(x);condition=torch.randn_like(z)
  expected=image(pixels,condition).numpy();actual=img.run(None,{'image':pixels.numpy(),'audio_context':condition.numpy()})[0]
  # Top-K order can differ for near-ties; sorted score distributions must agree.
  np.testing.assert_allclose(np.sort(actual[:,:,4]),np.sort(expected[:,:,4]),rtol=1e-3,atol=1e-4)
 print('PASS: 90-frame streaming ONNX context parity; random image predictor parity')
 print(json.dumps({p.name:p.stat().st_size for p in out.iterdir()}))
