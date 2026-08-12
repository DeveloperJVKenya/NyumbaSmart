import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cmms/notifications/services/fcm_http_service.dart';
import 'dart:convert';
import 'dart:io';

class ServiceAccountSetupScreen extends StatefulWidget {
  const ServiceAccountSetupScreen({super.key});

  @override
  State<ServiceAccountSetupScreen> createState() => _ServiceAccountSetupScreenState();
}

class _ServiceAccountSetupScreenState extends State<ServiceAccountSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _projectIdController = TextEditingController();
  final _jsonController = TextEditingController();
  
  bool _isLoading = false;
  bool _isValidJson = false;
  bool _hasExistingCredentials = false;
  bool _hasAssetsFile = false;
  String? _errorMessage;
  String? _successMessage;
  Map<String, dynamic>? _parsedJson;

  @override
  void initState() {
    super.initState();
    _checkExistingCredentials();
    _checkAssetsFile();
  }

  Future<void> _checkAssetsFile() async {
    try {
      await rootBundle.loadString('assets/service-account.json');
      setState(() {
        _hasAssetsFile = true;
      });
    } catch (e) {
      setState(() {
        _hasAssetsFile = false;
      });
    }
  }

  Future<void> _checkExistingCredentials() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final fcmService = FCMHttpService();
      final isValid = await fcmService.validateStoredCredentials();
      
      setState(() {
        _hasExistingCredentials = isValid;
        if (isValid) {
          _successMessage = '✅ Valid credentials already configured and working!';
        }
      });
    } catch (e) {
      setState(() {
        _hasExistingCredentials = false;
        _errorMessage = 'Error checking existing credentials: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _pickJsonFile() async {
    try {
      PlatformFile? result = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.path != null) {
        final file = File(result.path!);
        final jsonContent = await file.readAsString();
        
        _jsonController.text = jsonContent;
        _validateJson(jsonContent);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error reading file: $e';
        _successMessage = null;
      });
    }
  }

  void _validateJson(String jsonString) {
    try {
      if (jsonString.trim().isEmpty) {
        setState(() {
          _isValidJson = false;
          _parsedJson = null;
          _errorMessage = null;
        });
        return;
      }

      final parsed = json.decode(jsonString);
      
      // Validate required fields
      final requiredFields = [
        'type', 'project_id', 'private_key_id', 'private_key',
        'client_email', 'client_id', 'auth_uri', 'token_uri'
      ];

      final missingFields = <String>[];
      for (final field in requiredFields) {
        if (!parsed.containsKey(field) || parsed[field] == null || parsed[field].toString().isEmpty) {
          missingFields.add(field);
        }
      }

      if (missingFields.isNotEmpty) {
        throw Exception('Missing required fields: ${missingFields.join(', ')}');
      }

      // Validate that it's a service account
      if (parsed['type'] != 'service_account') {
        throw Exception('Invalid credential type. Expected "service_account", got "${parsed['type']}"');
      }

      setState(() {
        _isValidJson = true;
        _parsedJson = parsed;
        _projectIdController.text = parsed['project_id'];
        _errorMessage = null;
        _successMessage = '✅ Valid service account JSON detected';
      });
    } catch (e) {
      setState(() {
        _isValidJson = false;
        _parsedJson = null;
        _errorMessage = 'Invalid JSON: $e';
        _successMessage = null;
      });
    }
  }

  Future<void> _saveCredentials() async {
    if (!_formKey.currentState!.validate() || !_isValidJson || _parsedJson == null) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final fcmService = FCMHttpService();
      
      // Store credentials securely
      await fcmService.storeCredentialsSecurely(
        projectId: _projectIdController.text.trim(),
        serviceAccount: _parsedJson!,
      );

      // Validate the stored credentials by trying to get an access token
      final isValid = await fcmService.validateStoredCredentials();
      
      if (isValid) {
        setState(() {
          _hasExistingCredentials = true;
          _successMessage = '🎉 Credentials saved and validated successfully!\n'
                           'Firebase Cloud Messaging is now configured and ready to use.';
          _errorMessage = null;
        });

        // Show success dialog
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 8),
                  Text('Success!'),
                ],
              ),
              content: const Text(
                'Firebase Cloud Messaging has been configured successfully!\n\n'
                'Your app can now send push notifications using the HTTP FCM service.',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(); // Close dialog
                    Navigator.of(context).pop(true); // Return to previous screen
                  },
                  child: const Text('Done'),
                ),
              ],
            ),
          );
        }
      } else {
        throw Exception('Credential validation failed after storage');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error saving credentials: $e';
        _successMessage = null;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testCredentials() async {
    if (!_hasExistingCredentials && !_hasAssetsFile) {
      setState(() {
        _errorMessage = 'No credentials to test. Please save credentials first or add assets/service-account.json file.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final fcmService = FCMHttpService();
      await fcmService.initialize(); // This will try both methods
      
      setState(() {
        _successMessage = '✅ Credentials test successful! FCM service is working correctly.';
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Test failed: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _clearCredentials() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text('Clear Credentials'),
          ],
        ),
        content: const Text(
          'Are you sure you want to clear all stored Firebase credentials?\n\n'
          'This will disable push notifications until new credentials are configured.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _isLoading = true;
      });

      try {
        final fcmService = FCMHttpService();
        await fcmService.clearStoredCredentials();
        
        setState(() {
          _projectIdController.clear();
          _jsonController.clear();
          _isValidJson = false;
          _parsedJson = null;
          _hasExistingCredentials = false;
          _errorMessage = null;
          _successMessage = '🗑️ Credentials cleared successfully';
        });
      } catch (e) {
        setState(() {
          _errorMessage = 'Error clearing credentials: $e';
        });
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Firebase FCM Setup',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.blueGrey,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Instructions Card
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info, color: Colors.blue.shade700),
                          const SizedBox(width: 8),
                          Text(
                            'Setup Instructions',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '1. Go to Firebase Console → Project Settings → Service Accounts\n'
                        '2. Click "Generate new private key"\n'
                        '3. Download the JSON file\n'
                        '4. Either:\n'
                        '   • Place it as assets/service-account.json (recommended)\n'
                        '   • Or upload/paste it here for secure storage',
                        style: TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Status Cards
              if (_hasAssetsFile)
                Card(
                  color: Colors.green.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '✅ Assets file found: assets/service-account.json\nThis is the recommended approach!',
                            style: TextStyle(color: Colors.green.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              if (_hasExistingCredentials || _successMessage != null || _errorMessage != null)
                Card(
                  color: _hasExistingCredentials || _successMessage != null
                      ? Colors.green.shade50
                      : Colors.red.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Icon(
                          _hasExistingCredentials || _successMessage != null
                              ? Icons.check_circle
                              : Icons.error,
                          color: _hasExistingCredentials || _successMessage != null
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _successMessage ?? _errorMessage ?? '',
                            style: TextStyle(
                              color: _hasExistingCredentials || _successMessage != null
                                  ? Colors.green.shade700
                                  : Colors.red.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              if (_hasAssetsFile || _hasExistingCredentials || _successMessage != null || _errorMessage != null)
                const SizedBox(height: 16),
              
              // Project ID Field
              TextFormField(
                controller: _projectIdController,
                decoration: const InputDecoration(
                  labelText: 'Firebase Project ID',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.cloud),
                  helperText: 'Found in Firebase Console → Project Settings',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter the Firebase Project ID';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),
              
              // File Upload Row
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _pickJsonFile,
                      icon: const Icon(Icons.file_upload),
                      label: const Text('Upload JSON File'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : () {
                      Clipboard.getData(Clipboard.kTextPlain).then((data) {
                        if (data?.text != null) {
                          _jsonController.text = data!.text!;
                          _validateJson(data.text!);
                        }
                      });
                    },
                    icon: const Icon(Icons.paste),
                    label: const Text('Paste'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              
              // JSON Content Field
              Expanded(
                child: TextFormField(
                  controller: _jsonController,
                  decoration: InputDecoration(
                    labelText: 'Service Account JSON Content',
                    border: const OutlineInputBorder(),
                    prefixIcon: Icon(
                      _isValidJson ? Icons.check_circle : Icons.error,
                      color: _isValidJson ? Colors.green : Colors.grey,
                    ),
                    helperText: 'Paste your service account JSON content here',
                  ),
                  maxLines: null,
                  expands: true,
                  onChanged: _validateJson,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please provide the service account JSON';
                    }
                    if (!_isValidJson) {
                      return 'Invalid JSON format or missing required fields';
                    }
                    return null;
                  },
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (_isLoading || !_isValidJson) ? null : _saveCredentials,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save),
                      label: Text(_isLoading ? 'Saving...' : 'Save & Validate'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _testCredentials,
                    icon: const Icon(Icons.wifi_protected_setup),
                    label: const Text('Test'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _clearCredentials,
                    icon: const Icon(Icons.delete),
                    label: const Text('Clear'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _projectIdController.dispose();
    _jsonController.dispose();
    super.dispose();
  }
}
