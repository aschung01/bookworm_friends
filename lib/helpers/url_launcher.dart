import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

class UrlLauncher {
  static ChromeSafariBrowser webView = ChromeSafariBrowser();

  static Future<void> launchInBrowser(String url,
      {String nativeUrl = ''}) async {
    if (await canLaunchUrl(Uri.parse(nativeUrl))) {
      await launchUrl(Uri.parse(nativeUrl));
    } else if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(
        Uri.parse(url),
      );
    } else {
      print('Could not launch $url');
    }
  }

  static Future<void> launchInApp(String url, {String nativeUrl = ''}) async {
    try {
      if (await canLaunchUrl(Uri.parse(nativeUrl))) {
        await launchUrl(Uri.parse(nativeUrl));
      } else if (await canLaunchUrl(Uri.parse(url))) {
        if (webView.isOpened()) {
          await webView.close();
        }
        await webView.open(
          url: Uri.parse(url),
        );

        // await custom_tabs.launch(url);

        // await launch(
        //   url,
        //   forceSafariVC: true,
        //   forceWebView: true,
        //   enableJavaScript: true,
        // );
      } else {
        print('Could not launch $url');
      }
    } catch (e) {
      print(e);
    }
  }
}
