import 'package:flutter/widgets.dart';

bool get platformViewerSupported => false;

Widget buildPlatformViewer({
  required String html,
  required void Function(String raw) onMessage,
  required void Function(void Function(String json) sink) attachSender,
  void Function(void Function(bool enabled) toggle)? attachPointerEventsToggle,
}) =>
    const SizedBox.shrink();
