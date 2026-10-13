"""Check the actual merged Android manifest, including transitive SDK providers."""
from pathlib import Path
import xml.etree.ElementTree as ET

ns = '{http://schemas.android.com/apk/res/android}'
files = list(Path('build/app/intermediates').rglob('AndroidManifest.xml'))
files = [p for p in files if 'merged_manifests/debug' in str(p)]
assert files, 'Merged debug manifest not found'
root = ET.parse(files[0]).getroot()
app = root.find('application')
assert app is not None
assert not any(p.get(ns+'name') == 'com.facebook.internal.FacebookInitProvider'
               for p in app.findall('provider')), 'SDK would start before consent'
metadata = {m.get(ns+'name'): m.get(ns+'value') for m in app.findall('meta-data')}
for name in ['AutoInitEnabled', 'AutoLogAppEventsEnabled', 'AdvertiserIDCollectionEnabled']:
    assert metadata.get('com.facebook.sdk.'+name) == 'false', name
assert metadata.get('com.facebook.sdk.ApplicationId') == '@string/facebook_app_id'
assert metadata.get('com.facebook.sdk.ClientToken') == '@string/facebook_client_token'
print('Merged manifest: Meta provider absent; initialization, automatic events and AD ID default off.')
