import base64
import unittest
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


if __name__ == '__main__':
    unittest.main()
