import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// webview_flutter ships Android, iOS and macOS implementations only.
bool get platformViewerSupported => Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

Widget buildPlatformViewer({
  required String html,
  required void Function(String raw) onMessage,
  required void Function(void Function(String json) sink) attachSender,
  void Function(void Function(bool enabled) toggle)? attachPointerEventsToggle,
}) =>
    _WebViewViewer(html: html, onMessage: onMessage, attachSender: attachSender);

class _WebViewViewer extends StatefulWidget {
  const _WebViewViewer({required this.html, required this.onMessage, required this.attachSender});

  final String html;
  final void Function(String raw) onMessage;
  final void Function(void Function(String json) sink) attachSender;

  @override
  State<_WebViewViewer> createState() => _WebViewViewerState();
}

class _WebViewViewerState extends State<_WebViewViewer> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFEEF2FF))
      ..addJavaScriptChannel('CmmsBridge', onMessageReceived: (m) => widget.onMessage(m.message))
      // An https base URL gives the page a real origin, so CDN modules, WebAssembly and the
      // Storage download (CORS) behave as they do in a browser.
      ..loadHtmlString(widget.html, baseUrl: 'https://bim-viewer.cmms.local/');
    widget.attachSender((json) {
      // jsonEncode output is a valid JS object literal, so it can be passed straight in.
      _controller.runJavaScript('window.cmmsViewer && window.cmmsViewer.receive($json);');
    });
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(
      controller: _controller,
      // Let the page own every drag/pinch so orbiting the model isn't stolen by parent scrollables.
      gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer())},
    );
  }
}
