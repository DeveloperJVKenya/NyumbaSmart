import 'dart:typed_data';

/// Mobile/desktop stub — web downloads are handled by path_provider + open_file
/// on non-web platforms. This function should never be called on mobile.
void triggerWebDownload(Uint8List bytes, String fileName, String mime) {
  throw UnsupportedError('triggerWebDownload is only available on the web platform.');
}
