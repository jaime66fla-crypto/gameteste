"""Generate operator animation assets via PixelLab; never expose the API key to the game."""
import concurrent.futures
import threading
import argparse
import base64
import io
import json
import os
from pathlib import Path
import sys
import time
import urllib.error
import urllib.request
from PIL import Image

API = 'https://api.pixellab.ai/v2'
# Same directional order and source bounds as public/player-art.js.
DIRECTIONS = ['east', 'south-east', 'south', 'south-west', 'west', 'north-west', 'north', 'north-east']
BOUNDS = [(110,28,254,398),(547,32,244,390),(996,19,226,382),(1427,32,239,390),
          (119,471,246,397),(555,472,238,381),(990,470,238,373),(1425,473,234,379)]
SIZE = 96
FRAME_COUNT = 8


def encode_image(image):
    buffer = io.BytesIO()
    image.save(buffer, format='PNG')
    return {'type': 'base64', 'base64': base64.b64encode(buffer.getvalue()).decode(), 'format': 'png'}


def decode_image(value):
    if not isinstance(value, dict) or not value.get('base64'):
        raise RuntimeError('PixelLab returned an unsupported image representation.')
    encoded = value['base64'].split(',', 1)[-1]
    data = base64.b64decode(encoded, validate=True)
    image = Image.open(io.BytesIO(data))
    if image.width > 4096 or image.height > 4096:
        raise RuntimeError('Unexpected oversized image from PixelLab.')
    return image.convert('RGBA')


def api_request(token, path, payload=None, _attempt=0):
    # Only the fixed official API receives the credential. It never enters a URL or logs.
    request = urllib.request.Request(API + path,
        data=None if payload is None else json.dumps(payload).encode(),
        headers={'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'},
        method='GET' if payload is None else 'POST')
    try:
        with urllib.request.urlopen(request, timeout=90) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        if exc.code==429 and _attempt<60:
            print('Waiting for an available PixelLab generation slot...',flush=True)
            time.sleep(10)
            return api_request(token,path,payload,_attempt+1)
        labels = {401:'PixelLab rejected PIXELLAB_API_KEY. Check the repository secret.',
                  402:'PixelLab requires more subscription generations or credits.',
                  403:'This PixelLab account does not have access to this API operation.',
                  422:'PixelLab rejected the image or request parameters.',
                  429:'PixelLab concurrency limit reached; no automatic generation retry was made.'}
        # Do not dump response bodies, headers or request images into public Action logs.
        raise RuntimeError(labels.get(exc.code, 'PixelLab API failed with HTTP ' + str(exc.code))) from None
    except (urllib.error.URLError, TimeoutError):
        raise RuntimeError('PixelLab API connection failed. No generation request was retried.') from None


def poll_job(token, job_id, timeout=900):
    import re
    if not re.fullmatch(r'[a-zA-Z0-9_-]{1,128}', str(job_id)):
        raise RuntimeError('PixelLab returned an invalid job identifier.')
    start = time.monotonic()
    while time.monotonic() - start < timeout:
        response = api_request(token, '/background-jobs/' + job_id)
        state = response.get('status')
        if state == 'completed':
            return response.get('last_response') or {}
        if state == 'failed':
            raise RuntimeError('PixelLab reported that the animation job failed.')
        print('PixelLab job processing...', flush=True)
        time.sleep(10)
    raise RuntimeError('PixelLab job timed out; it was not resubmitted.')


def source_frame(sheet, index):
    x,y,w,h = BOUNDS[index]
    crop = sheet.crop((x,y,x+w,y+h))
    canvas = Image.new('RGBA', (512,512))
    canvas.alpha_composite(crop, ((512-w)//2, 484-h))
    return canvas


def prepare_reference(token, image):
    # Official recommendation: recover the native pixel grid before animation.
    response = api_request(token, '/unzoom', {'image': encode_image(image), 'quantize': -1})
    result = decode_image(response.get('image'))
    # /unzoom composites onto white. Restore the original aligned alpha silhouette.
    alpha = image.getchannel('A').resize(result.size, Image.Resampling.LANCZOS)
    result.putalpha(alpha)
    result.thumbnail((SIZE,SIZE), Image.Resampling.NEAREST)
    reference = Image.new('RGBA', (SIZE,SIZE))
    reference.alpha_composite(result, ((SIZE-result.width)//2, SIZE-result.height))
    return reference


def build_sheet(frames):
    # v3 includes the original input frame before the requested generated frames.
    if len(frames) == FRAME_COUNT + 1:
        frames = frames[1:]
    if len(frames) != FRAME_COUNT:
        raise RuntimeError('PixelLab returned an unexpected animation frame count.')
    # Keep the generated canvas and anchors intact across every frame.
    if any(im.size != frames[0].size for im in frames):
        raise RuntimeError('Animation frames have inconsistent canvas sizes.')
    sheet = Image.new('RGBA', (SIZE*FRAME_COUNT, SIZE))
    for index, image in enumerate(frames):
        if image.getchannel('A').getextrema() == (255,255):
            raise RuntimeError('PixelLab returned opaque frames; refusing to integrate a background.')
        if image.getchannel('A').getbbox() is None:
            raise RuntimeError('PixelLab returned an empty animation frame.')
        frame = image.resize((SIZE,SIZE), Image.Resampling.NEAREST)
        sheet.alpha_composite(frame, (index*SIZE,0))
    return sheet


def save_preview(frames, path, fps):
    # GIFs are for review; PNG sheets remain the authoritative transparent assets.
    previews=[]
    for frame in frames:
        bg=Image.new('RGBA', frame.size, '#26322c')
        bg.alpha_composite(frame)
        previews.append(bg.convert('RGB').resize((288,288), Image.Resampling.NEAREST))
    previews[0].save(path, save_all=True, append_images=previews[1:], duration=round(1000/fps), loop=0)


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--mode', choices=['preview','all','check'], default='preview')
    parser.add_argument('--resume-job', default='')
    parser.add_argument('--reuse-walk-job', default='')
    parser.add_argument('--output', type=Path, default=Path('pixellab-output'))
    args=parser.parse_args()
    token=os.environ.get('PIXELLAB_API_KEY','').strip()
    if not token:
        raise RuntimeError('PIXELLAB_API_KEY is missing from the repository Actions secrets.')
    balance=api_request(token, '/balance')
    subscription=balance.get('subscription') or {}
    print('PixelLab authentication succeeded.', flush=True)
    print('Subscription generations remaining: ' + str(subscription.get('generations','unknown')), flush=True)
    args.output.mkdir(parents=True, exist_ok=True)
    if args.resume_job:
        result=poll_job(token,args.resume_job)
        (args.output/'recovered-response.json').write_text(json.dumps(result))
        def shape(value):
            if isinstance(value,dict):return {k:shape(v) for k,v in value.items()}
            if isinstance(value,list):return {'count':len(value),'item':shape(value[0]) if value else None}
            return type(value).__name__
        print('Recovered result structure: '+json.dumps(shape(result)),flush=True)
        return
    if args.mode == 'check':
        return
    # Refuse to buy anything or silently continue using funded credit balances.
    if float(subscription.get('generations') or 0) < (3 if args.mode=='preview' else 32):
        raise RuntimeError('Not enough included generations for this batch. No new generation was started.')
    sheet=Image.open('public/assets/player/operator-directions.png').convert('RGBA')
    indices=[1] if args.mode=='preview' else range(8)
    manifest={'version':1,'frameSize':SIZE,'frameCount':FRAME_COUNT,'directions':DIRECTIONS,'animations':{}}
    manifest_path=args.output/'manifest.json'
    lock=threading.Lock()
    recovered=poll_job(token,args.reuse_walk_job) if args.reuse_walk_job else None
    def process_direction(index):
        direction=DIRECTIONS[index]
        print('Preparing reference: ' + direction, flush=True)
        reference=(decode_image(recovered['images'][0]) if recovered and index==1 else prepare_reference(token,source_frame(sheet,index)))
        reference.save(args.output/(direction+'-reference.png'))
        for motion,fps in [('walk',10),('run',14)]:
            action=(('Walk naturally in place with a steady alternating heel-to-toe leg cycle, gentle knee bend and weight transfer. '
                     'Keep both hands holding the rifle, with subtle shoulder and backpack motion. ')
                    if motion=='walk' else
                    ('Run naturally in place with alternating long strides, bent knees and a small forward torso lean. '
                     'Keep the rifle stable in both hands, with restrained backpack bounce. '))
            action += ('Face '+direction+' throughout. Fixed isometric camera. Preserve this exact tactical soldier, outfit, '
                       'rifle, proportions and silhouette. Smooth seamless loop. No camera motion, rotation, sliding, '
                       'extra limbs, changing gear, shadows or background. Keep the feet anchored to the same ground baseline.')
            print('Generating '+motion+' / '+direction, flush=True)
            if recovered and index==1 and motion=='walk':
                result=recovered
                job={'background_job_id':args.reuse_walk_job}
            else:
                job=api_request(token,'/animate-with-text-v3',{'first_frame':encode_image(reference),
                'action':action,'frame_count':FRAME_COUNT,'no_background':True,'seed':3611+index,'enhance_prompt':False})
            # Preserve job IDs for recovery; these identifiers never authorize API access.
            checkpoint=args.output/(motion+'-'+direction+'-job.json')
            checkpoint.write_text(json.dumps({'background_job_id':job['background_job_id']}))
            if not (recovered and index==1 and motion=='walk'):
                result=poll_job(token,job['background_job_id'])
            frames=[decode_image(value) for value in result.get('images',[])]
            sprite=build_sheet(frames)
            name=motion+'-'+direction+'.png'
            sprite.save(args.output/name)
            save_preview([sprite.crop((i*SIZE,0,(i+1)*SIZE,SIZE)) for i in range(FRAME_COUNT)],
                         args.output/(motion+'-'+direction+'.gif'),fps)
            with lock:
                manifest['animations'].setdefault(motion,{})[str(index)]={'file':name,'fps':fps}
                manifest_path.write_text(json.dumps(manifest,indent=2)+'\n')
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        list(pool.map(process_direction, indices))
    print('Animation assets completed. Review the PNG sheets and GIFs before publishing.', flush=True)


if __name__ == '__main__':
    try:
        main()
    except RuntimeError as exc:
        print('::error::'+str(exc),file=sys.stderr)
        sys.exit(1)
