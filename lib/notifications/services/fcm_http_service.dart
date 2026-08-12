import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class FCMHttpService {
  static final FCMHttpService _instance = FCMHttpService._internal();
  factory FCMHttpService() => _instance;
  FCMHttpService._internal();

  final Logger _logger = Logger();
  String? _projectId;
  ServiceAccountCredentials? _credentials;
  bool _isInitialized = false;

  // Secure storage instance
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );

  /// Initialize FCM HTTP service with service account
  Future<void> initialize() async {
    try {
      _logger.i('🔧 Initializing FCM HTTP Service...');
      
      // Try multiple initialization approaches
      bool initialized = false;
      
      // Method 1: Try loading from assets first (recommended)
      try {
        await _initializeFromAssets();
        initialized = true;
        _logger.i('✅ Initialized from assets/service-account.json');
      } catch (e) {
        _logger.w('⚠️ Could not initialize from assets: $e');
      }
      
      // Method 2: Try loading from stored credentials if assets failed
      if (!initialized) {
        try {
          await _initializeFromStoredCredentials();
          initialized = true;
          _logger.i('✅ Initialized from stored credentials');
        } catch (e) {
          _logger.w('⚠️ Could not initialize from stored credentials: $e');
        }
      }
      
      if (!initialized) {
        _logger.w('⚠️ FCM HTTP Service not initialized - notifications will be disabled');
        _isInitialized = false;
        return;
      }
      
      _isInitialized = true;
      _logger.i('✅ FCM HTTP Service initialized successfully');
      _logger.i('📋 Project ID: $_projectId');
      
    } catch (e) {
      _logger.e('❌ Failed to initialize FCM HTTP Service: $e');
      _isInitialized = false;
    }
  }

  /// Initialize from assets/service-account.json
  Future<void> _initializeFromAssets() async {
    final serviceAccountJson = await rootBundle.loadString('assets/service-account.json');
    final serviceAccountMap = json.decode(serviceAccountJson) as Map<String, dynamic>;
    
    _projectId = serviceAccountMap['project_id'] as String;
    _credentials = ServiceAccountCredentials.fromJson(serviceAccountMap);
  }

  /// Initialize from stored credentials
  Future<void> _initializeFromStoredCredentials() async {
    await _loadConfiguration();
    if (_projectId == null || _credentials == null) {
      throw Exception('No stored credentials found');
    }
  }

  /// Load configuration from secure storage
  Future<void> _loadConfiguration() async {
    try {
      // Try secure storage first
      final projectId = await _secureStorage.read(key: 'firebase_project_id');
      final serviceAccountJson = await _secureStorage.read(key: 'fcm_service_account');
      
      if (projectId != null && serviceAccountJson != null) {
        _projectId = projectId;
        final serviceAccountMap = json.decode(serviceAccountJson) as Map<String, dynamic>;
        _credentials = ServiceAccountCredentials.fromJson(serviceAccountMap);
        return;
      }
      
      // Fallback to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final fallbackProjectId = prefs.getString('firebase_project_id');
      final fallbackServiceAccountJson = prefs.getString('fcm_service_account');
      
      if (fallbackProjectId != null && fallbackServiceAccountJson != null) {
        _projectId = fallbackProjectId;
        final serviceAccountMap = json.decode(fallbackServiceAccountJson) as Map<String, dynamic>;
        _credentials = ServiceAccountCredentials.fromJson(serviceAccountMap);
        return;
      }
      
      throw Exception('No configuration found');
    } catch (e) {
      _logger.e('Error loading configuration: $e');
      rethrow;
    }
  }

  /// Store credentials securely
  Future<void> storeCredentialsSecurely({
    required String projectId,
    required Map<String, dynamic> serviceAccount,
  }) async {
    try {
      // Store in secure storage
      await _secureStorage.write(
        key: 'firebase_project_id',
        value: projectId,
      );
      
      await _secureStorage.write(
        key: 'fcm_service_account',
        value: json.encode(serviceAccount),
      );
      
      // Also store in SharedPreferences as backup
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('firebase_project_id', projectId);
      await prefs.setString('fcm_service_account', json.encode(serviceAccount));
      
      _logger.i('✅ Credentials stored securely');
    } catch (e) {
      _logger.e('Error storing credentials: $e');
      rethrow;
    }
  }

  /// Clear stored credentials
  Future<void> clearStoredCredentials() async {
    try {
      // Clear secure storage
      await _secureStorage.delete(key: 'firebase_project_id');
      await _secureStorage.delete(key: 'fcm_service_account');
      
      // Clear shared preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('firebase_project_id');
      await prefs.remove('fcm_service_account');
      
      _logger.i('🗑️ All credentials cleared');
    } catch (e) {
      _logger.e('Error clearing credentials: $e');
    }
  }

  /// Validate stored credentials
  Future<bool> validateStoredCredentials() async {
    try {
      await _loadConfiguration();
      
      if (_credentials == null) return false;
      
      // Try to get access token to validate
      await _getAccessToken();
      
      _logger.i('✅ Credentials validation successful');
      return true;
    } catch (e) {
      _logger.e('Credentials validation failed: $e');
      return false;
    }
  }

  /// Get access token for FCM HTTP v1 API
  Future<String> _getAccessToken() async {
    if (!_isInitialized || _credentials == null) {
      throw Exception('FCM HTTP Service not initialized');
    }
    
    try {
      final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];
      final client = await clientViaServiceAccount(_credentials!, scopes);
      final accessToken = client.credentials.accessToken.data;
      client.close();
      
      _logger.i('🔑 Access token obtained successfully');
      return accessToken;
    } catch (e) {
      _logger.e('❌ Failed to get access token: $e');
      rethrow;
    }
  }

  /// Send notification to multiple users
  Future<FCMSendResult> sendToMultipleUsers({
    required String title,
    required String body,
    required List<String> userIds,
    required String notificationId,
    String priority = 'normal',
    Map<String, String>? data,
  }) async {
    if (!_isInitialized) {
      _logger.w('⚠️ FCM HTTP Service not initialized, skipping notification send');
      return FCMSendResult(sentCount: 0, failedCount: userIds.length);
    }

    try {
      _logger.i('📤 Sending FCM notification to ${userIds.length} users');
      
      // Get FCM tokens for users
      final tokens = await _getFCMTokensForUsers(userIds);
      if (tokens.isEmpty) {
        _logger.w('⚠️ No FCM tokens found for users');
        return FCMSendResult(sentCount: 0, failedCount: userIds.length);
      }

      final accessToken = await _getAccessToken();
      int sentCount = 0;
      int failedCount = 0;

      // Send to each token individually (FCM HTTP v1 doesn't support batch)
      for (final token in tokens) {
        try {
          await _sendToToken(
            token: token,
            title: title,
            body: body,
            accessToken: accessToken,
            priority: priority,
            data: data,
            notificationId: notificationId,
          );
          sentCount++;
        } catch (e) {
          _logger.e('❌ Failed to send to token: $e');
          failedCount++;
        }
      }

      _logger.i('📊 FCM send completed: $sentCount sent, $failedCount failed');
      return FCMSendResult(sentCount: sentCount, failedCount: failedCount);
      
    } catch (e) {
      _logger.e('❌ Error sending FCM notifications: $e');
      return FCMSendResult(sentCount: 0, failedCount: userIds.length);
    }
  }

  /// Send test notification
  Future<bool> sendTestNotification({
    required String userId,
    String title = 'Test Notification',
    String body = 'This is a test notification from CMMS System',
  }) async {
    try {
      final userToken = await _getUserToken(userId);
      if (userToken == null) {
        _logger.w('No valid token found for user $userId');
        return false;
      }

      final accessToken = await _getAccessToken();
      await _sendToToken(
        token: userToken,
        title: title,
        body: body,
        accessToken: accessToken,
        priority: 'normal',
        data: {'type': 'test'},
        notificationId: 'test_${DateTime.now().millisecondsSinceEpoch}',
      );
      return true;
    } catch (e) {
      _logger.e('Error sending test notification: $e');
      return false;
    }
  }

  /// Get single user token
  Future<String?> _getUserToken(String userId) async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(userId)
          .get();
      
      if (userDoc.exists) {
        final fcmToken = userDoc.data()?['fcmToken'] as String?;
        if (fcmToken != null && fcmToken.isNotEmpty) {
          return fcmToken;
        }
      }
      return null;
    } catch (e) {
      _logger.e('Error getting user token: $e');
      return null;
    }
  }

  /// Send notification to a single token - FIXED PAYLOAD STRUCTURE
  Future<void> _sendToToken({
    required String token,
    required String title,
    required String body,
    required String accessToken,
    String priority = 'normal',
    Map<String, String>? data,
    required String notificationId,
  }) async {
    final url = 'https://fcm.googleapis.com/v1/projects/$_projectId/messages:send';
    
    // FIXED: Correct FCM v1 API payload structure
    final message = {
      'message': {
        'token': token,
        'notification': {
          'title': title,
          'body': body,
        },
        'data': {
          'notificationId': notificationId,
          'click_action': 'FLUTTER_NOTIFICATION_CLICK',
          ...?data,
        },
        'android': {
          'priority': priority == 'urgent' ? 'high' : 'normal', // CORRECT: Priority at android level
          'notification': {
            'channel_id': 'maintenance_channel',
            'sound': 'default',
            'default_sound': true,
            'default_vibrate_timings': true,
            'default_light_settings': true,
            // REMOVED: priority field from here (this was causing the 400 error)
          },
        },
        'apns': {
          'headers': {
            'apns-priority': priority == 'urgent' ? '10' : '5',
          },
          'payload': {
            'aps': {
              'alert': {
                'title': title,
                'body': body,
              },
              'sound': 'default',
              'badge': 1,
            },
          },
        },
      },
    };

    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: json.encode(message),
    );

    if (response.statusCode != 200) {
      throw Exception('FCM send failed: ${response.statusCode} - ${response.body}');
    }

    _logger.i('✅ FCM notification sent successfully to token');
  }

  /// Get FCM tokens for users - OPTIMIZED VERSION
  Future<List<String>> _getFCMTokensForUsers(List<String> userIds) async {
    try {
      final tokens = <String>[];
      
      // Query users in batches (Firestore 'in' query limit is 10)
      const batchSize = 10;
      for (int i = 0; i < userIds.length; i += batchSize) {
        final batch = userIds.skip(i).take(batchSize).toList();
        
        final snapshot = await FirebaseFirestore.instance
            .collection('Users')
            .where(FieldPath.documentId, whereIn: batch)
            .get();

        for (final doc in snapshot.docs) {
          final data = doc.data();
          final fcmToken = data['fcmToken'] as String?;
          if (fcmToken != null && fcmToken.isNotEmpty) {
            tokens.add(fcmToken);
          }
        }
      }
      
      _logger.i('🔍 Found ${tokens.length} FCM tokens for ${userIds.length} users');
      return tokens;
      
    } catch (e) {
      _logger.e('❌ Error getting FCM tokens: $e');
      return [];
    }
  }

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;

  /// Get project ID
  String? get projectId => _projectId;
}

class FCMSendResult {
  final int sentCount;
  final int failedCount;
  
  FCMSendResult({required this.sentCount, required this.failedCount});
}
