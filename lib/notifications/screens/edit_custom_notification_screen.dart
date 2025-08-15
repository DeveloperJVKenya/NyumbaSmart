import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cmms/notifications/models/custom_notification_model.dart';
import 'package:cmms/notifications/services/custom_notification_service.dart';

class EditCustomNotificationScreen extends StatefulWidget {
  final CustomNotificationModel notification;

  const EditCustomNotificationScreen({
    super.key,
    required this.notification,
  });

  @override
  State<EditCustomNotificationScreen> createState() => _EditCustomNotificationScreenState();
}

class _EditCustomNotificationScreenState extends State<EditCustomNotificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final CustomNotificationService _service = CustomNotificationService();
  final Logger _logger = Logger();

  late TextEditingController _categoryController;
  late TextEditingController _componentController;
  late TextEditingController _interventionController;
  late TextEditingController _frequencyController;
  late DateTime _lastInspectionDate;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _categoryController = TextEditingController(text: widget.notification.category);
    _componentController = TextEditingController(text: widget.notification.component);
    _interventionController = TextEditingController(text: widget.notification.intervention);
    _frequencyController = TextEditingController(text: widget.notification.frequency.toString());
    _lastInspectionDate = widget.notification.lastInspectionDate;
  }

  @override
  void dispose() {
    _categoryController.dispose();
    _componentController.dispose();
    _interventionController.dispose();
    _frequencyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Edit Notification',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.blueGrey[50],
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Notification Details',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.blueGrey[800],
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Category Field
                    TextFormField(
                      controller: _categoryController,
                      decoration: InputDecoration(
                        labelText: 'Category',
                        hintText: 'e.g., HVAC, Electrical, Plumbing',
                        prefixIcon: const Icon(Icons.category),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a category';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    
                    // Component Field
                    TextFormField(
                      controller: _componentController,
                      decoration: InputDecoration(
                        labelText: 'Component',
                        hintText: 'e.g., Air Conditioner, Generator, Water Pump',
                        prefixIcon: const Icon(Icons.build),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a component';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    
                    // Intervention Field
                    TextFormField(
                      controller: _interventionController,
                      decoration: InputDecoration(
                        labelText: 'Intervention Required',
                        hintText: 'e.g., Filter Replacement, Oil Change, Inspection',
                        prefixIcon: const Icon(Icons.engineering),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter the required intervention';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    
                    // Frequency Field
                    TextFormField(
                      controller: _frequencyController,
                      decoration: InputDecoration(
                        labelText: 'Frequency (months)',
                        hintText: 'e.g., 3, 6, 12',
                        prefixIcon: const Icon(Icons.schedule),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        suffixText: 'months',
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter frequency in months';
                        }
                        final frequency = int.tryParse(value.trim());
                        if (frequency == null || frequency <= 0) {
                          return 'Please enter a valid positive number';
                        }
                        if (frequency > 60) {
                          return 'Frequency cannot exceed 60 months';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    
                    // Last Inspection Date
                    InkWell(
                      onTap: _selectLastInspectionDate,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Last Inspection Date',
                          prefixIcon: const Icon(Icons.calendar_today),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          '${_lastInspectionDate.day}/${_lastInspectionDate.month}/${_lastInspectionDate.year}',
                          style: GoogleFonts.poppins(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Update Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _updateNotification,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueGrey[600],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        'Update Notification',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectLastInspectionDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _lastInspectionDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.blueGrey[600]!,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.blueGrey[800]!,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _lastInspectionDate) {
      setState(() {
        _lastInspectionDate = picked;
      });
    }
  }

  Future<void> _updateNotification() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _service.editCustomNotification(
        notificationId: widget.notification.id,
        category: _categoryController.text.trim(),
        component: _componentController.text.trim(),
        intervention: _interventionController.text.trim(),
        frequency: int.parse(_frequencyController.text.trim()),
        lastInspectionDate: _lastInspectionDate,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Notification updated successfully',
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: Colors.green[600],
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      _logger.e('Error updating notification: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error updating notification: $e',
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: Colors.red[600],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}
