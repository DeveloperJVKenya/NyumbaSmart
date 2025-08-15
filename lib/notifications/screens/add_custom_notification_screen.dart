import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cmms/notifications/services/custom_notification_service.dart';
import 'package:cmms/notifications/utils/date_calculator.dart';
import 'package:intl/intl.dart';

class AddCustomNotificationScreen extends StatefulWidget {
  final String organization;

  const AddCustomNotificationScreen({
    super.key,
    required this.organization,
  });

  @override
  State<AddCustomNotificationScreen> createState() => _AddCustomNotificationScreenState();
}

class _AddCustomNotificationScreenState extends State<AddCustomNotificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final CustomNotificationService _customNotificationService = CustomNotificationService();
  
  final _categoryController = TextEditingController();
  final _componentController = TextEditingController();
  final _interventionController = TextEditingController();
  final _frequencyController = TextEditingController();
  
  DateTime? _lastInspectionDate;
  DateTime? _calculatedNotificationDate;
  DateTime? _calculatedAlertDate;
  DateTime? _calculatedNextInspectionDate;
  
  bool _isLoading = false;

  @override
  void dispose() {
    _categoryController.dispose();
    _componentController.dispose();
    _interventionController.dispose();
    _frequencyController.dispose();
    super.dispose();
  }

  void _calculateDates() {
    if (_lastInspectionDate != null && _frequencyController.text.isNotEmpty) {
      final frequency = int.tryParse(_frequencyController.text);
      if (frequency != null && frequency > 0) {
        final dates = NotificationDateCalculator.calculateNotificationDates(
          lastInspectionDate: _lastInspectionDate!,
          frequencyMonths: frequency,
        );
        
        setState(() {
          _calculatedNextInspectionDate = dates['nextInspectionDate'];
          _calculatedNotificationDate = dates['notificationDate'];
          _calculatedAlertDate = dates['alertDate'];
        });
      }
    }
  }

  Future<void> _selectLastInspectionDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _lastInspectionDate ?? DateTime.now().subtract(const Duration(days: 30)),
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 2)),
      lastDate: DateTime.now(),
      helpText: 'Select Last Inspection Date',
    );
    
    if (date != null) {
      setState(() {
        _lastInspectionDate = date;
      });
      _calculateDates();
    }
  }

  Future<void> _createNotification() async {
    if (!_formKey.currentState!.validate() || _lastInspectionDate == null) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _customNotificationService.createCustomNotification(
        category: _categoryController.text.trim(),
        component: _componentController.text.trim(),
        intervention: _interventionController.text.trim(),
        frequency: int.parse(_frequencyController.text.trim()),
        lastInspectionDate: _lastInspectionDate!,
        organization: widget.organization,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Custom notification created successfully!', style: GoogleFonts.poppins()),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating notification: $e', style: GoogleFonts.poppins()),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Add Custom Notification',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.blueGrey,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Instructions Card
              Card(
                color: Colors.blue[50],
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info, color: Colors.blue[700]),
                          const SizedBox(width: 8),
                          Text(
                            'Create Custom Notification',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[800],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Fill in the details below to create a custom maintenance notification. The system will automatically calculate notification and alert dates based on your frequency.',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.blue[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Category Field
              TextFormField(
                controller: _categoryController,
                decoration: InputDecoration(
                  labelText: 'Category',
                  hintText: 'e.g., HVAC, Electrical, Plumbing',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.category),
                  labelStyle: GoogleFonts.poppins(),
                  hintStyle: GoogleFonts.poppins(),
                ),
                style: GoogleFonts.poppins(),
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
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.build),
                  labelStyle: GoogleFonts.poppins(),
                  hintStyle: GoogleFonts.poppins(),
                ),
                style: GoogleFonts.poppins(),
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
                  labelText: 'Intervention/Action',
                  hintText: 'e.g., Clean filters, Check oil level, Replace parts',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.settings),
                  labelStyle: GoogleFonts.poppins(),
                  hintStyle: GoogleFonts.poppins(),
                ),
                style: GoogleFonts.poppins(),
                maxLines: 2,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter the intervention/action required';
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
                  hintText: 'e.g., 2, 4, 6, 12',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.schedule),
                  labelStyle: GoogleFonts.poppins(),
                  hintStyle: GoogleFonts.poppins(),
                ),
                style: GoogleFonts.poppins(),
                keyboardType: TextInputType.number,
                onChanged: (value) => _calculateDates(),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter frequency in months';
                  }
                  final frequency = int.tryParse(value.trim());
                  if (frequency == null || frequency <= 0) {
                    return 'Please enter a valid number greater than 0';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Last Inspection Date Field
              InkWell(
                onTap: _selectLastInspectionDate,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[400]!),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Last Inspection Date',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                            Text(
                              _lastInspectionDate != null
                                  ? DateFormat.yMMMd().format(_lastInspectionDate!)
                                  : 'Select last inspection date',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                color: _lastInspectionDate != null ? Colors.black : Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              ),
              
              if (_lastInspectionDate == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 12),
                  child: Text(
                    'Please select the last inspection date',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.red[600],
                    ),
                  ),
                ),

              const SizedBox(height: 24),

              // Calculated Dates Preview
              if (_calculatedNotificationDate != null && 
                  _calculatedAlertDate != null && 
                  _calculatedNextInspectionDate != null) ...[
                Card(
                  color: Colors.green[50],
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.preview, color: Colors.green[700]),
                            const SizedBox(width: 8),
                            Text(
                              'Calculated Dates Preview',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.green[800],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildDatePreviewRow(
                          'Next Inspection Date',
                          _calculatedNextInspectionDate!,
                          Icons.event,
                          Colors.blue,
                        ),
                        const SizedBox(height: 8),
                        _buildDatePreviewRow(
                          'Notification Date (5 days before)',
                          _calculatedNotificationDate!,
                          Icons.notifications,
                          Colors.orange,
                        ),
                        const SizedBox(height: 8),
                        _buildDatePreviewRow(
                          'Alert Date (1 day before)',
                          _calculatedAlertDate!,
                          Icons.warning,
                          Colors.red,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Create Button
              ElevatedButton(
                onPressed: _isLoading ? null : _createNotification,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueGrey,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isLoading
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text('Creating...', style: GoogleFonts.poppins()),
                        ],
                      )
                    : Text(
                        'Create Custom Notification',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDatePreviewRow(String label, DateTime date, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              DateFormat.yMMMd().format(date),
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              NotificationDateCalculator.getRelativeDateString(date),
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
