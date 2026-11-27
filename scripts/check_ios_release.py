#!/usr/bin/env python3
"""Reject archives built without the matching iOS Dart service configuration."""
import base64
import os
import re
import sys
import plistlib
from pathlib import Path


def validate(environment):
    defines = {}
    for encoded in environment.get('DART_DEFINES', '').split(','):
        if not encoded:
            continue
        key, value = base64.b64decode(encoded, validate=True).decode().split('=', 1)
        defines[key] = value
    if environment.get('IOS_CONFIGURATION_KIND') == 'internal':
        for key, expected in {'IOS_LOCAL_ONLY': 'false', 'IOS_DISABLE_ADS': 'true',
                              'IOS_APPLE_BILLING_ENABLED': 'false',
                              'IOS_INTERNAL_TESTING': 'true'}.items():
            if defines.get(key) != expected:
                raise ValueError(f'Internal archive requires {key}={expected}.')
        if defines.get('IOS_APP_STORE_ID') != '6840100351':
            raise ValueError('Internal archive requires the registered WarrantyCave app.')
        options = plistlib.loads(Path(environment.get('IOS_EXPORT_OPTIONS', '')).read_bytes())
        if options.get('testFlightInternalTestingOnly') is not True or options.get('method') != 'app-store-connect':
            raise ValueError('Internal archives must export for TestFlight internal testing only.')
        return
    if defines.get('IOS_INTERNAL_TESTING') == 'true':
        raise ValueError('Internal testing defines cannot be used for a public release.')
    for key, expected in {'IOS_LOCAL_ONLY': 'false', 'IOS_DISABLE_ADS': 'false',
                          'IOS_APPLE_BILLING_ENABLED': 'true'}.items():
        if defines.get(key) != expected:
            raise ValueError(f'Archive requires {key}={expected}. Use --dart-define-from-file=.ios-dart-defines.json.')
    if not re.fullmatch(r'[1-9]\d{5,15}', defines.get('IOS_APP_STORE_ID', '')):
        raise ValueError('Archive requires the real IOS_APP_STORE_ID.')
    for key in ['IOS_ADMOB_BANNER_ID', 'IOS_ADMOB_INLINE_BANNER_ID']:
        value = defines.get(key, '')
        if (not re.fullmatch(r'ca-app-pub-\d{16}/\d{10}', value) or
                value.startswith('ca-app-pub-3940256099942544') or
                value in {'ca-app-pub-1171723950608276/9463569777',
                          'ca-app-pub-1171723950608276/9035972595'}):
            raise ValueError(f'Archive requires the real iOS {key}.')


if __name__ == '__main__':
    try:
        validate(os.environ)
    except (ValueError, UnicodeError, OSError) as error:
        sys.exit(f'error: {error}')
