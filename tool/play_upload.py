#!/usr/bin/env python3
"""Upload an AAB to Google Play (Android Publisher API v3).

Uses the service account play-publisher@heizungstrainer-play.iam.gserviceaccount.com
(key: ~/.config/heizungstrainer/play-service-account.json, never in the repo).
The account must be invited in the Play Console (Nutzer und Berechtigungen)
with release rights for the app.

  # check access only (nothing changes):
  tool/play_upload.py --check
  # upload as a draft to production (finish the rollout in the Play Console):
  tool/play_upload.py build/app/outputs/bundle/playRelease/app-play-release.aab \
      --track production --notes-file notes.txt
  # publish right away (sent to review):
  ... --status completed

Only needs `requests` and `cryptography`.
"""
import argparse
import base64
import json
import os
import sys
import time

import requests
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding

PACKAGE = 'com.heizungstrainer.heizungstrainer'
KEY_FILE = os.path.expanduser('~/.config/heizungstrainer/play-service-account.json')
API = f'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PACKAGE}'
UPLOAD_API = f'https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/{PACKAGE}'
SCOPE = 'https://www.googleapis.com/auth/androidpublisher'


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()


def access_token(key_file: str) -> str:
    with open(key_file) as f:
        key = json.load(f)
    now = int(time.time())
    header = _b64(json.dumps({'alg': 'RS256', 'typ': 'JWT'}).encode())
    claims = _b64(json.dumps({
        'iss': key['client_email'], 'scope': SCOPE, 'aud': key['token_uri'],
        'iat': now, 'exp': now + 3600,
    }).encode())
    private_key = serialization.load_pem_private_key(key['private_key'].encode(), password=None)
    signature = private_key.sign(f'{header}.{claims}'.encode(), padding.PKCS1v15(), hashes.SHA256())
    response = requests.post(key['token_uri'], data={
        'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        'assertion': f'{header}.{claims}.{_b64(signature)}',
    }, timeout=30)
    response.raise_for_status()
    return response.json()['access_token']


def _check(response: requests.Response) -> dict:
    if not response.ok:
        sys.exit(f'Play API {response.status_code}: {response.text}')
    return response.json() if response.content else {}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('aab', nargs='?', help='path to the .aab')
    parser.add_argument('--check', action='store_true', help='only verify access and show the tracks')
    parser.add_argument('--track', default='internal', choices=['internal', 'alpha', 'beta', 'production'])
    parser.add_argument('--status', default='draft', choices=['draft', 'completed'],
                        help='draft: finish in the Play Console (default); completed: send to review now')
    parser.add_argument('--notes-file', help='release notes (de-DE, max. 500 characters)')
    parser.add_argument('--key', default=KEY_FILE)
    args = parser.parse_args()
    if not args.check and not args.aab:
        parser.error('path to the .aab is required (or --check)')

    session = requests.Session()
    session.headers['Authorization'] = f'Bearer {access_token(args.key)}'
    edit_id = _check(session.post(f'{API}/edits', timeout=30))['id']

    if args.check:
        for track in _check(session.get(f'{API}/edits/{edit_id}/tracks', timeout=30)).get('tracks', []):
            releases = ', '.join(
                f"{r.get('name', '?')} [{r.get('status')}] {r.get('versionCodes', [])}" for r in track.get('releases', []))
            print(f"{track['track']:<12} {releases or '–'}")
        session.delete(f'{API}/edits/{edit_id}', timeout=30)
        print('Zugriff OK (nichts geändert).')
        return

    notes = None
    if args.notes_file:
        with open(args.notes_file, encoding='utf-8') as f:
            notes = f.read().strip()
        if len(notes) > 500:
            sys.exit(f'Versionshinweise zu lang: {len(notes)} > 500 Zeichen')

    print(f'Lade {args.aab} hoch …')
    with open(args.aab, 'rb') as f:
        bundle = _check(session.post(
            f'{UPLOAD_API}/edits/{edit_id}/bundles', params={'uploadType': 'media'},
            data=f, headers={'Content-Type': 'application/octet-stream'}, timeout=900))
    version_code = bundle['versionCode']
    print(f'versionCode {version_code}, SHA-256 {bundle.get("sha256")}')

    release = {'versionCodes': [str(version_code)], 'status': args.status}
    if notes:
        release['releaseNotes'] = [{'language': 'de-DE', 'text': notes}]
    _check(session.put(f'{API}/edits/{edit_id}/tracks/{args.track}',
                       json={'track': args.track, 'releases': [release]}, timeout=30))
    _check(session.post(f'{API}/edits/{edit_id}:commit', timeout=60))
    print(f'Fertig: versionCode {version_code} im Track „{args.track}“ ({args.status}).')


if __name__ == '__main__':
    main()
