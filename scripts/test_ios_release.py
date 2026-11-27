import base64
import unittest
import tempfile
import plistlib
from pathlib import Path
from check_ios_release import validate


class ArchiveConfigurationTest(unittest.TestCase):
    def environment(self, **changes):
        # Synthetic IDs exercise validation; these are not production settings.
        values = {'IOS_LOCAL_ONLY': 'false', 'IOS_DISABLE_ADS': 'false',
                  'IOS_APPLE_BILLING_ENABLED': 'true', 'IOS_APP_STORE_ID': '1234567890',
                  'IOS_ADMOB_BANNER_ID': 'ca-app-pub-1111111111111111/1111111111',
                  'IOS_ADMOB_INLINE_BANNER_ID': 'ca-app-pub-1111111111111111/2222222222'}
        values.update(changes)
        return {'DART_DEFINES': ','.join(base64.b64encode(f'{key}={value}'.encode()).decode()
                                        for key, value in values.items())}

    def test_matching_release_configuration(self):
        validate(self.environment())

    def test_missing_or_local_configuration_cannot_archive(self):
        for environment in [{}, self.environment(IOS_LOCAL_ONLY='true'),
                            self.environment(IOS_APPLE_BILLING_ENABLED='false')]:
            with self.assertRaises(ValueError):
                validate(environment)

    def test_android_or_sample_ad_units_cannot_archive(self):
        for banner in ['ca-app-pub-1171723950608276/9463569777',
                       'ca-app-pub-3940256099942544/2934735716']:
            with self.assertRaises(ValueError):
                validate(self.environment(IOS_ADMOB_BANNER_ID=banner))

    def test_internal_build_requires_internal_only_export_and_disabled_commerce(self):
        with tempfile.TemporaryDirectory() as folder:
            options = Path(folder) / 'ExportOptions.plist'
            environment = self.environment(IOS_INTERNAL_TESTING='true', IOS_DISABLE_ADS='true',
                IOS_APPLE_BILLING_ENABLED='false', IOS_APP_STORE_ID='6840100351')
            environment.update(IOS_CONFIGURATION_KIND='internal', IOS_EXPORT_OPTIONS=str(options))
            options.write_bytes(plistlib.dumps({'method':'app-store-connect', 'testFlightInternalTestingOnly':True}))
            validate(environment)
            options.write_bytes(plistlib.dumps({'method':'app-store-connect', 'testFlightInternalTestingOnly':False}))
            with self.assertRaises(ValueError):
                validate(environment)
            options.write_bytes(plistlib.dumps({'method':'app-store-connect', 'testFlightInternalTestingOnly':True}))
            environment.update(self.environment(IOS_INTERNAL_TESTING='true', IOS_DISABLE_ADS='false',
                IOS_APPLE_BILLING_ENABLED='false', IOS_APP_STORE_ID='6840100351'))
            with self.assertRaises(ValueError):
                validate(environment)

    def test_internal_flag_cannot_be_used_for_public_release(self):
        for flag in ('IOS_INTERNAL_TESTING', 'IOS_APPLE_BILLING_SANDBOX'):
            with self.assertRaises(ValueError):
                validate(self.environment(**{flag: 'true'}))

    def test_sandbox_billing_requires_matching_internal_archive(self):
        with tempfile.TemporaryDirectory() as folder:
            options = Path(folder) / 'ExportOptions.plist'
            options.write_bytes(plistlib.dumps({
                'method': 'app-store-connect', 'testFlightInternalTestingOnly': True,
            }))
            environment = self.environment(
                IOS_INTERNAL_TESTING='true', IOS_DISABLE_ADS='true',
                IOS_APPLE_BILLING_ENABLED='true', IOS_APPLE_BILLING_SANDBOX='true',
                IOS_APP_STORE_ID='6840100351',
            )
            environment.update(IOS_CONFIGURATION_KIND='internal-sandbox', IOS_EXPORT_OPTIONS=str(options))
            validate(environment)
            with self.assertRaises(ValueError):
                validate(dict(environment, IOS_CONFIGURATION_KIND='internal'))


if __name__ == '__main__':
    unittest.main()
