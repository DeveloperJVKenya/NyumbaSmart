import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:logger/logger.dart';

import 'bim_viewer_platform_stub.dart'
    if (dart.library.js_interop) 'bim_viewer_platform_web.dart'
    if (dart.library.io) 'bim_viewer_platform_io.dart' as platform;

/// The viewer page (assets/bim_viewer/index.html) is loaded as an HTML string everywhere: an iframe
/// `srcdoc` on web and a WebView on Android/iOS/macOS. Windows/Linux have no embeddable WebView in
/// this app, so [bimViewerSupported] is false there and callers show a fallback.
bool get bimViewerSupported => platform.platformViewerSupported;

/// Two-way JSON channel to the viewer page. Messages sent before the page says it is ready are
/// queued and flushed once it does.
class BimViewerController {
  void Function(String json)? _sink;
  final List<String> _queue = [];
  bool _ready = false;

  void send(Map<String, Object?> message) {
    final json = jsonEncode(message);
    if (_ready && _sink != null) {
      _sink!(json);
    } else {
      _queue.add(json);
    }
  }

  void _attach(void Function(String json) sink) => _sink = sink;

  void _markReady() {
    _ready = true;
    for (final m in _queue) {
      _sink?.call(m);
    }
    _queue.clear();
  }
}

class BimViewerHost extends StatefulWidget {
  const BimViewerHost({super.key, required this.controller, required this.onMessage});

  final BimViewerController controller;

  /// Every message from the page except the internal 'ready' handshake.
  final ValueChanged<Map<String, dynamic>> onMessage;

  @override
  State<BimViewerHost> createState() => _BimViewerHostState();
}

final _hostLog = Logger();

class _BimViewerHostState extends State<BimViewerHost> {
  late final Future<String> _html = rootBundle.loadString('assets/bim_viewer/index.html');

  void _onRaw(String raw) {
    final Map<String, dynamic> msg;
    try {
      msg = (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (e) {
      _hostLog.e('BIM viewer sent invalid JSON', error: e);
      return;
    }
    if (msg['type'] == 'ready') {
      _hostLog.i('BIM viewer ready — flushing queued messages');
      widget.controller._markReady();
      return;
    }
    if (msg['type'] != 'progress') _hostLog.i('BIM viewer → ${msg['type']}');
    widget.onMessage(msg);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _html,
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.expand();
        return platform.buildPlatformViewer(
          html: snap.data!,
          onMessage: _onRaw,
          attachSender: widget.controller._attach,
        );
      },
    );
  }
}
