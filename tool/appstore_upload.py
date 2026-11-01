#!/usr/bin/env python3
"""Fill the App Store listing from docs/app-store-listing.md (App Store Connect API).

Key: ~/.config/heizungstrainer/AuthKey_ZXDVLH7252.p8 (team key, App Manager),
never in the repo. The privacy questionnaire, export compliance and contact
details for the review stay manual (not in the API / personal data).

  tool/appstore_upload.py --check                 # show state, change nothing
  tool/appstore_upload.py --version 1.2.9         # texts, categories, age rating, review notes
  tool/appstore_upload.py --version 1.2.9 --screenshots ~/Downloads/heizungstrainer-appstore
  tool/appstore_upload.py --version 1.2.9 --build 8   # attach a processed build

Only needs `requests` and `cryptography`.
"""
import argparse
import base64
import hashlib
import json
import os
import re
import sys
import time

import requests
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils

KEY_ID = 'ZXDVLH7252'
ISSUER_ID = '34aaa332-1ee2-43f8-9920-98ce5c0ec61d'
KEY_FILE = os.path.expanduser(f'~/.config/heizungstrainer/AuthKey_{KEY_ID}.p8')
APP_ID = '6829485327'
LOCALE = 'de-DE'
API = 'https://api.appstoreconnect.apple.com/v1'
LISTING = os.path.join(os.path.dirname(__file__), '..', 'docs', 'app-store-listing.md')
SCREENSHOT_TYPE = 'APP_IPHONE_67'  # 6.7"/6.9" iPhone, 1320 x 2868 accepted


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()


def token() -> str:
    with open(KEY_FILE, 'rb') as f:
        key = serialization.load_pem_private_key(f.read(), password=None)
    now = int(time.time())
    header = _b64(json.dumps({'alg': 'ES256', 'kid': KEY_ID, 'typ': 'JWT'}).encode())
    claims = _b64(json.dumps({'iss': ISSUER_ID, 'iat': now, 'exp': now + 1100, 'aud': 'appstoreconnect-v1'}).encode())
    r, s = utils.decode_dss_signature(key.sign(f'{header}.{claims}'.encode(), ec.ECDSA(hashes.SHA256())))
    return f'{header}.{claims}.{_b64(r.to_bytes(32, "big") + s.to_bytes(32, "big"))}'


class Asc:
    def __init__(self):
        self.s = requests.Session()
        self.s.headers['Authorization'] = f'Bearer {token()}'

    def _ok(self, r: requests.Response) -> dict:
        if not r.ok:
            sys.exit(f'{r.request.method} {r.url} → {r.status_code}: {r.text[:800]}')
        return r.json() if r.content else {}

    def get(self, path, **params):
        return self._ok(self.s.get(API + path, params=params, timeout=60))

    def patch(self, path, body):
        return self._ok(self.s.patch(API + path, json={'data': body}, timeout=60))

    def post(self, path, body):
        return self._ok(self.s.post(API + path, json={'data': body}, timeout=60))


def listing() -> dict:
    """Texts from docs/app-store-listing.md (one source for docs and upload)."""
    with open(LISTING, encoding='utf-8') as f:
        md = f.read()

    def block(label):
        m = re.search(rf'\*\*{label}\*\*.*?\n```\n(.*?)```', md, re.S)
        if not m:
            sys.exit(f'{label} not found in {LISTING}')
        return m.group(1).strip()

    def cell(label):
        m = re.search(rf'^\| {re.escape(label)}[^|]*\| (.+?) \|$', md, re.M)
        if not m:
            sys.exit(f'{label} not found in {LISTING}')
        return m.group(1).strip().strip('`')

    data = {
        'promotionalText': block('Werbetext'),
        'description': block('Beschreibung'),
        'keywords': block('Keywords'),
        'reviewNotes': block('Notizen'),
        'subtitle': cell('Untertitel'),
        'supportUrl': cell('Support-URL'),
        'marketingUrl': cell('Marketing-URL'),
        'privacyPolicyUrl': cell('Datenschutz-URL'),
        'copyright': cell('Copyright'),
    }
    for field, limit in [('promotionalText', 170), ('description', 4000), ('keywords', 100),
                         ('subtitle', 30), ('reviewNotes', 4000)]:
        if len(data[field]) > limit:
            sys.exit(f'{field}: {len(data[field])} > {limit} characters')
    return data


def editable_version(asc: Asc) -> dict:
    for v in asc.get(f'/apps/{APP_ID}/appStoreVersions', **{'filter[platform]': 'IOS'})['data']:
        if v['attributes']['appStoreState'] in ('PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED',
                                                'METADATA_REJECTED', 'INVALID_BINARY'):
            return v
    sys.exit('No editable App Store version (create one in App Store Connect first).')


def editable_app_info(asc: Asc) -> dict:
    infos = asc.get(f'/apps/{APP_ID}/appInfos')['data']
    for i in infos:
        if (i['attributes'].get('appStoreState') or i['attributes'].get('state')) != 'READY_FOR_SALE':
            return i
    return infos[0]


def localization(asc: Asc, path: str, kind: str, parent_rel: str, parent_type: str, parent_id: str) -> dict:
    for loc in asc.get(path)['data']:
        if loc['attributes']['locale'] == LOCALE:
            return loc
    return asc.post(f'/{kind}', {
        'type': kind, 'attributes': {'locale': LOCALE},
        'relationships': {parent_rel: {'data': {'type': parent_type, 'id': parent_id}}},
    })['data']


def check(asc: Asc) -> None:
    for v in asc.get(f'/apps/{APP_ID}/appStoreVersions')['data']:
        a = v['attributes']
        print(f"Version {a['versionString']:<8} {a['appStoreState']:<24} release={a.get('releaseType')}")
    builds = asc.get('/builds', **{'filter[app]': APP_ID, 'sort': '-uploadedDate', 'limit': 5})['data']
    for b in builds:
        a = b['attributes']
        print(f"Build {a['version']:<4} {a['processingState']:<10} Verschlüsselung={a.get('usesNonExemptEncryption')}"
              f" {a['uploadedDate']}")


def upload_texts(asc: Asc, version: dict, version_string: str) -> None:
    t = listing()
    asc.patch(f"/appStoreVersions/{version['id']}", {
        'type': 'appStoreVersions', 'id': version['id'],
        'attributes': {'versionString': version_string, 'copyright': t['copyright'], 'releaseType': 'MANUAL'},
    })
    loc = localization(asc, f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations",
                       'appStoreVersionLocalizations', 'appStoreVersion', 'appStoreVersions', version['id'])
    asc.patch(f"/appStoreVersionLocalizations/{loc['id']}", {
        'type': 'appStoreVersionLocalizations', 'id': loc['id'],
        'attributes': {k: t[k] for k in ('description', 'keywords', 'promotionalText', 'supportUrl', 'marketingUrl')},
    })
    info = editable_app_info(asc)
    info_loc = localization(asc, f"/appInfos/{info['id']}/appInfoLocalizations",
                            'appInfoLocalizations', 'appInfo', 'appInfos', info['id'])
    asc.patch(f"/appInfoLocalizations/{info_loc['id']}", {
        'type': 'appInfoLocalizations', 'id': info_loc['id'],
        'attributes': {'subtitle': t['subtitle'], 'privacyPolicyUrl': t['privacyPolicyUrl']},
    })
    asc.patch(f"/appInfos/{info['id']}", {
        'type': 'appInfos', 'id': info['id'],
        'relationships': {
            'primaryCategory': {'data': {'type': 'appCategories', 'id': 'UTILITIES'}},
            'secondaryCategory': {'data': {'type': 'appCategories', 'id': 'LIFESTYLE'}},
        },
    })
    set_age_rating(asc, info)
    # Review notes (contact person stays manual).
    detail = asc.get(f"/appStoreVersions/{version['id']}/appStoreReviewDetail").get('data')
    attrs = {'notes': t['reviewNotes'], 'demoAccountRequired': False}
    if detail and detail['attributes'].get('notes') == attrs['notes']:
        pass  # unchanged; Apple validates the contact fields on every PATCH
    elif detail:
        r = asc.s.patch(f"{API}/appStoreReviewDetails/{detail['id']}", timeout=60,
                        json={'data': {'type': 'appStoreReviewDetails', 'id': detail['id'], 'attributes': attrs}})
        if not r.ok and 'contact' in r.text:
            print('Prüfhinweise nicht geändert: erst den Kontakt für die App-Prüfung in App Store Connect eintragen.')
        else:
            asc._ok(r)
    else:
        asc.post('/appStoreReviewDetails', {
            'type': 'appStoreReviewDetails', 'attributes': attrs,
            'relationships': {'appStoreVersion': {'data': {'type': 'appStoreVersions', 'id': version['id']}}},
        })
    print(f'Texte, Kategorien, Altersfreigabe und Prüfhinweise für {version_string} gesetzt.')


def set_age_rating(asc: Asc, info: dict) -> None:
    """Nothing objectionable → 4+: every content level NONE, every yes/no
    question false. Apple adds questions over time and the API doesn't say
    which are yes/no, so the type is taken from Apple's error and retried."""
    rating = asc.get(f"/appInfos/{info['id']}/ageRatingDeclaration")['data']
    skip = {'kidsAgeBand', 'ageRatingOverride', 'ageRatingOverrideV2', 'koreaAgeRatingOverride',
            'gracRatingClassificationNumber', 'developerAgeRatingInfoUrl'}
    attrs = {k: (False if isinstance(v, bool) else 'NONE') for k, v in rating['attributes'].items() if k not in skip}
    for _ in range(5):
        r = asc.s.patch(f"{API}/ageRatingDeclarations/{rating['id']}", timeout=60,
                        json={'data': {'type': 'ageRatingDeclarations', 'id': rating['id'], 'attributes': attrs}})
        if r.ok:
            return
        fixed = False
        for err in r.json().get('errors', []):
            field = err.get('source', {}).get('pointer', '').rsplit('/', 1)[-1]
            if field in attrs and 'Expected a BOOLEAN' in err.get('detail', ''):
                attrs[field], fixed = False, True
            elif field in attrs and attrs[field] is False:
                attrs[field], fixed = 'NONE', True
        if not fixed:
            asc._ok(r)
    asc._ok(r)


def upload_screenshots(asc: Asc, version: dict, folder: str) -> None:
    files = sorted(f for f in os.listdir(folder) if f.lower().endswith('.png'))
    if not files:
        sys.exit(f'No PNGs in {folder}')
    loc = localization(asc, f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations",
                       'appStoreVersionLocalizations', 'appStoreVersion', 'appStoreVersions', version['id'])
    sets = asc.get(f"/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")['data']
    shot_set = next((s for s in sets if s['attributes']['screenshotDisplayType'] == SCREENSHOT_TYPE), None)
    if shot_set:
        # Replace: remove what is there, so the order matches the files.
        for old in asc.get(f"/appScreenshotSets/{shot_set['id']}/appScreenshots")['data']:
            asc._ok(asc.s.delete(f"{API}/appScreenshots/{old['id']}", timeout=60))
    else:
        shot_set = asc.post('/appScreenshotSets', {
            'type': 'appScreenshotSets', 'attributes': {'screenshotDisplayType': SCREENSHOT_TYPE},
            'relationships': {'appStoreVersionLocalization': {'data': {'type': 'appStoreVersionLocalizations', 'id': loc['id']}}},
        })['data']
    for name in files:
        path = os.path.join(folder, name)
        with open(path, 'rb') as f:
            data = f.read()
        shot = asc.post('/appScreenshots', {
            'type': 'appScreenshots', 'attributes': {'fileName': name, 'fileSize': len(data)},
            'relationships': {'appScreenshotSet': {'data': {'type': 'appScreenshotSets', 'id': shot_set['id']}}},
        })['data']
        for op in shot['attributes']['uploadOperations']:
            part = data[op['offset']:op['offset'] + op['length']]
            headers = {h['name']: h['value'] for h in op.get('requestHeaders', [])}
            r = requests.request(op['method'], op['url'], data=part, headers=headers, timeout=120)
            if not r.ok:
                sys.exit(f'Upload {name}: {r.status_code} {r.text[:300]}')
        asc.patch(f"/appScreenshots/{shot['id']}", {
            'type': 'appScreenshots', 'id': shot['id'],
            'attributes': {'uploaded': True, 'sourceFileChecksum': hashlib.md5(data).hexdigest()},
        })
        print(f'Screenshot {name} hochgeladen.')


def attach_build(asc: Asc, version: dict, build_number: str) -> None:
    builds = asc.get('/builds', **{'filter[app]': APP_ID, 'filter[version]': build_number})['data']
    if not builds:
        sys.exit(f'Build {build_number} not found')
    build = builds[0]
    if build['attributes']['processingState'] != 'VALID':
        sys.exit(f"Build {build_number} is {build['attributes']['processingState']}")
    asc._ok(asc.s.patch(f"{API}/appStoreVersions/{version['id']}/relationships/build",
                        json={'data': {'type': 'builds', 'id': build['id']}}, timeout=60))
    print(f'Build {build_number} an die Version gehängt.')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--version', help='version string, e.g. 1.2.9 (must match the build)')
    parser.add_argument('--screenshots', help='folder with 1320 x 2868 PNGs, uploaded in name order')
    parser.add_argument('--build', help='build number to attach, e.g. 8')
    args = parser.parse_args()
    asc = Asc()
    if args.check or not args.version:
        check(asc)
        return
    version = editable_version(asc)
    upload_texts(asc, version, args.version)
    if args.screenshots:
        upload_screenshots(asc, version, os.path.expanduser(args.screenshots))
    if args.build:
        attach_build(asc, version, args.build)


if __name__ == '__main__':
    main()
