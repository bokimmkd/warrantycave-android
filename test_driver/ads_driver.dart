import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (String name, List<int> image, [Map<String, Object?>? args]) async {
      final folder = Directory('build/native-ad-previews');
      await folder.create(recursive: true);
      await File('${folder.path}/$name.png').writeAsBytes(image);
      return true;
    },
    responseDataCallback: (_) async {},
  );
}
