import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

bool get platformViewerSupported => true;

int _nextViewId = 0;

Widget buildPlatformViewer({
  required String html,
  required void Function(String raw) onMessage,
  required void Function(void Function(String json) sink) attachSender,
}) =>
    _IframeViewer(html: html, onMessage: onMessage, attachSender: attachSender);

class _IframeViewer extends StatefulWidget {
  const _IframeViewer({required this.html, required this.onMessage, required this.attachSender});

  final String html;
  final void Function(String raw) onMessage;
  final void Function(void Function(String json) sink) attachSender;

  @override
  State<_IframeViewer> createState() => _IframeViewerState();
}

class _IframeViewerState extends State<_IframeViewer> {
  late final String _viewType = 'cmms-bim-viewer-${_nextViewId++}';
  late final web.HTMLIFrameElement _iframe;
  StreamSubscription<web.MessageEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _iframe = web.HTMLIFrameElement()
      // srcdoc inherits this app's origin, so CDN modules and the Storage download work as on the page.
      ..srcdoc = widget.html.toJS
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) => _iframe);

    _sub = web.window.onMessage.listen((event) {
      if (event.source != _iframe.contentWindow) return;
      final data = event.data;
      if (data == null || !data.isA<JSObject>()) return;
      final obj = data as JSObject;
      if (!obj.has('cmmsViewer')) return;
      final payload = obj['payload'];
      if (payload != null && payload.isA<JSString>()) widget.onMessage((payload as JSString).toDart);
    });

    widget.attachSender((json) {
      final message = JSObject()
        ..['cmmsHost'] = true.toJS
        ..['payload'] = json.toJS;
      _iframe.contentWindow?.postMessage(message, '*'.toJS);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
