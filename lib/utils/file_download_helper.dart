import 'dart:io';
//import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:logger/logger.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class FileDownloadHelper {
  static final Logger _logger = Logger(printer: PrettyPrinter());

  /// Downloads a file using appropriate method based on platform and file type
  static Future<void> downloadFile({
    required BuildContext context,
    required String url,
    required String fileName,
    required Function(String) showSnackBar,
  }) async {
    if (!context.mounted) return;

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Downloading...', style: GoogleFonts.poppins()),
          ],
        ),
      ),
    );

    try {
      if (kIsWeb || Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        // For web and desktop platforms, use URL launcher
        await _downloadForWebAndDesktop(context, url, fileName, showSnackBar);
      } else if (Platform.isAndroid || Platform.isIOS) {
        // For mobile platforms, use appropriate storage method
        await _downloadForMobile(context, url, fileName, showSnackBar);
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        showSnackBar('Error downloading file: $e');
      }
      _logger.e('Error downloading file: $e');
    }
  }

  static Future<void> _downloadForWebAndDesktop(
    BuildContext context,
    String url,
    String fileName,
    Function(String) showSnackBar,
  ) async {
    Navigator.pop(context);
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      throw 'Could not download file';
    }
  }

  static Future<void> _downloadForMobile(
    BuildContext context,
    String url,
    String fileName,
    Function(String) showSnackBar,
  ) async {
    try {
      // Check if it's a media file
      final extension = fileName.toLowerCase().split('.').last;
      final isMediaFile = ['jpg', 'jpeg', 'png', 'gif', 'mp4', 'mp3', 'wav'].contains(extension);

      if (isMediaFile) {
        // Use MediaStore API for media files (Android 10+)
        await _downloadMediaFile(context, url, fileName, showSnackBar);
      } else {
        // For non-media files, use app-specific directory
        await _downloadToAppDirectory(context, url, fileName, showSnackBar);
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        showSnackBar('Error downloading file: $e');
      }
      _logger.e('Error downloading mobile file: $e');
    }
  }

  static Future<void> _downloadMediaFile(
    BuildContext context,
    String url,
    String fileName,
    Function(String) showSnackBar,
  ) async {
    // Request only necessary permissions for media files
    bool permissionGranted = await _requestMediaPermission();
    
    if (!permissionGranted) {
      if (context.mounted) {
        Navigator.pop(context);
        showSnackBar('Permission denied. Cannot download media file.');
      }
      return;
    }

    try {
      // Download to Downloads directory using standard approach
      Directory? downloadsDir;
      
      if (Platform.isAndroid) {
        // Use external storage directory for Android
        downloadsDir = await getExternalStorageDirectory();
        if (downloadsDir != null) {
          // Create Downloads subfolder
          final downloadPath = Directory('${downloadsDir.path}/Download');
          if (!await downloadPath.exists()) {
            await downloadPath.create(recursive: true);
          }
          downloadsDir = downloadPath;
        }
      } else {
        // Use documents directory for iOS
        downloadsDir = await getApplicationDocumentsDirectory();
      }

      if (downloadsDir == null) {
        throw 'Could not access download directory';
      }

      final filePath = '${downloadsDir.path}/$fileName';
      await Dio().download(url, filePath);

      final file = File(filePath);
      if (await file.exists()) {
        if (context.mounted) {
          Navigator.pop(context);
          showSnackBar('File downloaded successfully');
        }
        _logger.i('Downloaded file: $fileName to $filePath');
      } else {
        throw 'Failed to download file';
      }
    } catch (e) {
      throw 'Download failed: $e';
    }
  }

  static Future<void> _downloadToAppDirectory(
    BuildContext context,
    String url,
    String fileName,
    Function(String) showSnackBar,
  ) async {
    try {
      // Use app-specific directory (no special permissions needed)
      final appDir = await getApplicationDocumentsDirectory();
      final filePath = '${appDir.path}/$fileName';
      
      await Dio().download(url, filePath);

      final file = File(filePath);
      if (await file.exists()) {
        if (context.mounted) {
          Navigator.pop(context);
          showSnackBar('File saved to app documents');
          
          // Show option to share or open the file
          _showFileActionDialog(context, filePath, fileName);
        }
        _logger.i('Downloaded file: $fileName to $filePath');
      } else {
        throw 'Failed to download file';
      }
    } catch (e) {
      throw 'Download failed: $e';
    }
  }

  static Future<bool> _requestMediaPermission() async {
    if (Platform.isAndroid) {
      // For Android 13+ (API 33+), request specific media permissions
      if (await _isAndroid13OrHigher()) {
        var status = await Permission.photos.status;
        if (!status.isGranted) {
          status = await Permission.photos.request();
        }
        return status.isGranted;
      } else {
        // For older Android versions, request storage permission
        var status = await Permission.storage.status;
        if (!status.isGranted) {
          status = await Permission.storage.request();
        }
        return status.isGranted;
      }
    }
    return true; // iOS doesn't need special permissions for app documents
  }

  static Future<bool> _isAndroid13OrHigher() async {
    if (Platform.isAndroid) {
      // You can implement version checking here
      // For now, assume we're targeting newer versions
      return true;
    }
    return false;
  }

  static void _showFileActionDialog(BuildContext context, String filePath, String fileName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('File Downloaded', style: GoogleFonts.poppins()),
        content: Text(
          'File saved to app documents. What would you like to do?',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: GoogleFonts.poppins()),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              // Try to open the file with system apps
              final uri = Uri.file(filePath);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              }
            },
            child: Text('Open', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
  }
}
