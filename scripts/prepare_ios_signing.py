#!/usr/bin/env python3
"""Prepare an ephemeral CI keychain and internal-only App Store export."""
import base64
import json
import os
from pathlib import Path
import plistlib
import secrets
import shlex
import subprocess
import time
import urllib.request

import jwt

ROOT = Path(__file__).resolve().parent.parent
TEAM = 'QJ63494GZJ'
BUNDLE = 'com.warrantycave.app'
PROFILE_ID = 'W5LWBP6YU9'


def run(*args):
    return subprocess.check_output(args, stderr=subprocess.PIPE)


def main():
    os.umask(0o077)
    folder = Path(os.environ['RUNNER_TEMP']) / 'warrantycave-signing'
    folder.mkdir(exist_ok=True)
    api = json.loads(os.environ['APP_STORE_CONNECT_API_KEY_JSON'])
    token = jwt.encode({'iss': api['issuer_id'], 'iat': int(time.time()) - 10,
                        'exp': int(time.time()) + 300, 'aud': 'appstoreconnect-v1'},
                       api['key'], algorithm='ES256', headers={'kid': api['key_id'], 'typ': 'JWT'})
    request = urllib.request.Request(
        f'https://api.appstoreconnect.apple.com/v1/profiles/{PROFILE_ID}',
        headers={'Authorization': f'Bearer {token}'})
    with urllib.request.urlopen(request, timeout=30) as response:
        attributes = json.load(response)['data']['attributes']
    profile_bytes = base64.b64decode(attributes['profileContent'], validate=True)
    profile_file = folder / 'WarrantyCave.mobileprovision'
    profile_file.write_bytes(profile_bytes)
    profile = plistlib.loads(run('security', 'cms', '-D', '-i', str(profile_file)))
    assert profile['TeamIdentifier'] == [TEAM]
    assert profile['Entitlements']['application-identifier'] == f'{TEAM}.{BUNDLE}'
    assert profile['Entitlements']['get-task-allow'] is False
    certificate = folder / 'distribution.cer'
    certificate.write_bytes(profile['DeveloperCertificates'][0])
    pem = folder / 'distribution.pem'
    run('openssl', 'x509', '-inform', 'DER', '-in', str(certificate), '-out', str(pem))
    key_der = folder / 'distribution.der'
    key_der.write_bytes(base64.b64decode(os.environ['IOS_DISTRIBUTION_PRIVATE_KEY_BASE64'], validate=True))
    key = folder / 'distribution.key'
    run('openssl', 'pkey', '-inform', 'DER', '-in', str(key_der), '-out', str(key))
    assert run('openssl', 'pkey', '-in', str(key), '-pubout') == run(
        'openssl', 'x509', '-in', str(pem), '-pubkey', '-noout')
    password = secrets.token_urlsafe(32)
    p12 = folder / 'distribution.p12'
    run('openssl', 'pkcs12', '-export', '-inkey', str(key), '-in', str(pem),
        '-out', str(p12), '-passout', f'pass:{password}')
    keychain = folder / 'signing.keychain-db'
    previous = shlex.split(run('security', 'list-keychains', '-d', 'user').decode())
    (folder / 'previous-keychains.json').write_text(json.dumps(previous))
    run('security', 'create-keychain', '-p', password, str(keychain))
    run('security', 'set-keychain-settings', '-lut', '21600', str(keychain))
    run('security', 'unlock-keychain', '-p', password, str(keychain))
    run('security', 'import', str(p12), '-P', password, '-A', '-t', 'cert', '-f', 'pkcs12', '-k', str(keychain))
    run('security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:', '-s', '-k', password, str(keychain))
    run('security', 'list-keychains', '-d', 'user', '-s', str(keychain), *previous)
    profiles = Path.home() / 'Library/MobileDevice/Provisioning Profiles'
    profiles.mkdir(parents=True, exist_ok=True)
    (profiles / f"{profile['UUID']}.mobileprovision").write_bytes(profile_bytes)
    options = folder / 'ExportOptions.plist'
    options.write_bytes(plistlib.dumps({
        'method': 'app-store-connect', 'destination': 'export', 'signingStyle': 'manual',
        'teamID': TEAM, 'signingCertificate': 'Apple Distribution',
        'provisioningProfiles': {BUNDLE: profile['Name']},
        'testFlightInternalTestingOnly': True, 'manageAppVersionAndBuildNumber': False,
        'uploadSymbols': True,
    }))
    config = ROOT / 'ios/Flutter/ServiceConfig.xcconfig'
    with config.open('a') as output:
        output.write(f'CODE_SIGN_STYLE = Manual\nCODE_SIGN_IDENTITY = Apple Distribution\n'
                     f"PROVISIONING_PROFILE_SPECIFIER = {profile['Name']}\n"
                     f'IOS_EXPORT_OPTIONS = {options}\n')
    with open(os.environ['GITHUB_ENV'], 'a') as output:
        output.write(f'IOS_EXPORT_OPTIONS={options}\n')
    # Altool expects an AuthKey_<id>.p8 file in its supported private-key directory.
    api_dir = Path.home() / 'private_keys'
    api_dir.mkdir(mode=0o700, exist_ok=True)
    (api_dir / f"AuthKey_{api['key_id']}.p8").write_text(api['key'])
    (folder / 'api-identifiers.json').write_text(json.dumps({k: api[k] for k in ['key_id', 'issuer_id']}))
    print('Verified Apple signing certificate, profile, team, bundle and matching private key.')


if __name__ == '__main__':
    main()
