"""Upload a project image to the scratch project (DevOps Mobile App) so the
app's project tile can be checked with a real image. Scratch project only."""
import base64, io, os, sys
sys.path.insert(0, 'research/spikes')
from lib import ORG_URL, call, get
from PIL import Image, ImageDraw
PID = '98720989-0195-48cb-ae2e-0e58ec1bb9a9'
s, h, p = get(f'{ORG_URL}/_apis/projects/{PID}?api-version=7.1')
assert p['name'] == 'DevOps Mobile App', p['name']
im = Image.new('RGB', (256, 256), (245, 158, 11))
d = ImageDraw.Draw(im)
d.polygon([(0, 256), (256, 0), (256, 256)], fill=(217, 119, 6))
d.ellipse((64, 64, 192, 192), fill=(255, 251, 235))
d.polygon([(104, 88), (176, 128), (104, 168)], fill=(180, 83, 9))
buf = io.BytesIO(); im.save(buf, 'PNG')
s, h, r = call('PUT', f'{ORG_URL}/_apis/projects/{PID}/avatar?api-version=7.1-preview.1', {'image': base64.b64encode(buf.getvalue()).decode()})
print('PUT avatar:', s, str(r)[:200])
import urllib.request, lib
req = urllib.request.Request(f'{ORG_URL}/_apis/GraphProfile/MemberAvatars/8c08e1e1-7afd-411e-b414-4f9e1d14d8d6?overrideDisplayName=DevOps%20Mobile%20App&size=2', headers={'Authorization': lib._AUTH})
b = urllib.request.urlopen(req).read(); print('MemberAvatars now:', len(b), 'bytes')
open(os.path.join(os.environ['SPIKE_OUT'], 'scratch_after_upload.png'), 'wb').write(b)
