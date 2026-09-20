library webview_flutter_wkwebview;

import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class WebKitWebViewPlatform extends WebViewPlatform {}

class WebKitWebViewController extends PlatformWebViewController {
  WebKitWebViewController(PlatformWebViewControllerCreationParams params)
      : super.implementation(params);

  int get webViewIdentifier => 0;
}
