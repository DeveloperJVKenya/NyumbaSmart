import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cmms/theme/app_theme.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';
import 'dart:async';

class ReportScreen extends StatefulWidget {
  final String facilityId;

  const ReportScreen({super.key, required this.facilityId});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final Logger _logger = Logger();
  String _reportType = 'Work Orders';
  String _statusFilter = 'All';
  String _priorityFilter = 'All';
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isGenerating = false;
  bool _isLoading = false;
  Map<String, dynamic>? _lastGeneratedReport;
  StreamSubscription<QuerySnapshot>? _dataSubscription;
  List<QueryDocumentSnapshot> _currentData = [];
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _logger.i('ReportScreen initialized: facilityId=${widget.facilityId}');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeDataStream();
    });
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    super.dispose();
  }

  void _initializeDataStream() {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _lastError = null;
    });

    _dataSubscription?.cancel();

    try {
      final stream = _getDataStream();
      _dataSubscription = stream.listen(
        (QuerySnapshot snapshot) {
          if (mounted) {
            setState(() {
              _currentData = snapshot.docs;
              _isLoading = false;
              _lastError = null;
            });
            _generateDetailedReport(_currentData);
          }
        },
        onError: (error) {
          _logger.e('Stream error: $error');
          if (mounted) {
            setState(() {
              _isLoading = false;
              _lastError = error.toString();
            });
          }
        },
      );
    } catch (e) {
      _logger.e('Error initializing stream: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _lastError = e.toString();
        });
      }
    }
  }

  Stream<QuerySnapshot> _getDataStream() {
    String collection = _getCollectionName();

    // Use the correct collection path
    Query query = FirebaseFirestore.instance.collection(collection).limit(100);

    // Apply filters one at a time to avoid complex composite queries
    if (_statusFilter != 'All') {
      query = query.where('status', isEqualTo: _statusFilter);
    }

    if (_startDate != null) {
      query = query.where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(_startDate!));
    }

    if (_endDate != null) {
      query = query.where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(_endDate!));
    }

    return query.orderBy('createdAt', descending: true).snapshots();
  }

  String _getCollectionName() {
    switch (_reportType) {
      case 'Work Orders':
        return 'Work_Orders';
      case 'Work on Request':
        return 'Work_Requests';
      default:
        return 'Work_Orders'; // Default to Work Orders
    }
  }

  Future<void> _generateDetailedReport(List<QueryDocumentSnapshot> docs) async {
    if (!mounted || _isGenerating) return;

    setState(() => _isGenerating = true);

    try {
      await Future.delayed(const Duration(milliseconds: 100)); // Prevent UI blocking

      if (!mounted) return;

      _logger.i('Generating detailed report for ${docs.length} items');

      // Process data in smaller chunks to prevent memory issues
      final data = <Map<String, dynamic>>[];
      for (int i = 0; i < docs.length; i += 10) {
        final chunk = docs.skip(i).take(10);
        for (final doc in chunk) {
          try {
            final docData = doc.data() as Map<String, dynamic>?;
            if (docData != null) {
              data.add(docData);
            }
          } catch (e) {
            _logger.w('Error processing document ${doc.id}: $e');
          }
        }

        // Yield control back to UI thread
        if (i % 20 == 0) {
          await Future.delayed(const Duration(milliseconds: 1));
        }
      }

      if (!mounted) return;

      // Apply additional filtering in memory for better performance
      final filteredData = data.where((item) {
        if (_priorityFilter != 'All' && item['priority'] != _priorityFilter) {
          return false;
        }
        return true;
      }).toList();

      // Generate statistics
      final stats = await _generateStatistics(filteredData);

      if (!mounted) return;

      final report = {
        'reportType': _reportType,
        'facilityId': widget.facilityId,
        'generatedAt': DateTime.now().toIso8601String(),
        'totalItems': filteredData.length,
        'filters': {
          'status': _statusFilter,
          'priority': _priorityFilter,
          'startDate': _startDate?.toIso8601String(),
          'endDate': _endDate?.toIso8601String(),
        },
        'summary': stats,
        'data': filteredData.take(50).toList(), // Limit displayed data
      };

      if (mounted) {
        setState(() {
          _lastGeneratedReport = report;
          _isGenerating = false;
        });
      }
    } catch (e, stackTrace) {
      _logger.e('Error generating report: $e', stackTrace: stackTrace);
      if (mounted) {
        setState(() => _isGenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating report: $e', style: GoogleFonts.poppins()),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<Map<String, dynamic>> _generateStatistics(List<Map<String, dynamic>> data) async {
    final Map<String, int> statusCounts = {};
    final Map<String, int> priorityCounts = {};
    double totalValue = 0;
    int totalQuantity = 0;

    for (final item in data) {
      // Status distribution
      final status = item['status'] as String? ?? 'Unknown';
      statusCounts[status] = (statusCounts[status] ?? 0) + 1;

      // Priority distribution
      if (item.containsKey('priority')) {
        final priority = item['priority'] as String? ?? 'Unknown';
        priorityCounts[priority] = (priorityCounts[priority] ?? 0) + 1;
      }

      // Value calculations
      if (item.containsKey('cost')) {
        try {
          final cost = (item['cost'] as num?)?.toDouble() ?? 0;
          final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
          totalValue += cost * quantity;
          totalQuantity += quantity;
        } catch (e) {
          _logger.w('Error processing cost for item: $e');
        }
      }
    }

    return {
      'statusDistribution': statusCounts,
      'priorityDistribution': priorityCounts,
      'totalValue': totalValue,
      'totalQuantity': totalQuantity,
    };
  }

  List<String> _getAvailableFilters() {
    return ['All', 'Open', 'In Progress', 'Closed'];
  }

  void _clearFilters() {
    setState(() {
      _statusFilter = 'All';
      _priorityFilter = 'All';
      _startDate = null;
      _endDate = null;
    });
    _initializeDataStream();
  }

  void _refreshData() {
    _initializeDataStream();
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScreenWrapper(
      title: 'Real-time Reports',
      facilityId: widget.facilityId,
      currentRole: 'Engineer',
      organization: '-',
      floatingActionButton: FloatingActionButton(
        onPressed: _refreshData,
        backgroundColor: AppColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
        child: const Icon(Icons.refresh_rounded, color: Colors.white),
      ),
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth <= 768;
    final padding = isMobile ? 8.0 : 16.0;
    final fontSizeTitle = isMobile ? 16.0 : 24.0;
    final fontSize = isMobile ? 12.0 : 16.0;

    if (_lastError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AppRadius.md)),
              child: Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
            ),
            const SizedBox(height: 16),
            Text('Error loading data', style: GoogleFonts.poppins(fontSize: fontSizeTitle, fontWeight: FontWeight.bold, color: AppColors.error)),
            const SizedBox(height: 8),
            Text(_lastError!, style: GoogleFonts.poppins(fontSize: fontSize, color: context.textSecondary), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            DecoratedBox(
              decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(AppRadius.sm)),
              child: ElevatedButton.icon(
                onPressed: _refreshData,
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                label: Text('Retry', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm))),
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: Column(
        children: [
          _buildFilterSection(padding, fontSizeTitle: fontSizeTitle, fontSize: fontSize),
          const SizedBox(height: 12),
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: CircularProgressIndicator(),
              ),
            )
          else ...[
            _buildSummaryStatsSection(padding: padding, fontSize: fontSize),
            const SizedBox(height: 12),
            _buildDataList(fontSize: fontSize, padding: padding),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterSection(double padding, {required double fontSizeTitle, required double fontSize}) {
    final isMobile = MediaQuery.of(context).size.width <= 720;

    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.surfaceAltColor),
        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(AppRadius.sm)),
                    child: const Icon(Icons.filter_list_rounded, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Text('Report Filters', style: GoogleFonts.poppins(fontSize: fontSizeTitle, fontWeight: FontWeight.bold, color: context.textPrimary)),
                ],
              ),
              OutlinedButton.icon(
                onPressed: _clearFilters,
                icon: Icon(Icons.clear_rounded, size: 15, color: context.textSecondary),
                label: Text('Clear', style: GoogleFonts.poppins(fontSize: fontSize - 1, color: context.textSecondary)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: context.surfaceAltColor),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
              ),
            ],
          ),
            const SizedBox(height: 12),
            isMobile
                ? Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _buildDropdown('Report Type', _reportType, ['Work Orders', 'Work on Request'], (value) {
                        setState(() {
                          _reportType = value!;
                          _statusFilter = 'All';
                          _priorityFilter = 'All';
                        });
                        _initializeDataStream();
                      }, fontSize),
                      _buildDropdown('Status', _statusFilter, _getAvailableFilters(), (value) {
                        setState(() {
                          _statusFilter = value!;
                        });
                        _initializeDataStream();
                      }, fontSize),
                      _buildDropdown('Priority', _priorityFilter, ['All', 'High', 'Medium', 'Low'], (value) {
                        setState(() {
                          _priorityFilter = value!;
                        });
                        _initializeDataStream();
                      }, fontSize),
                    ],
                  )
                : Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildDropdown('Report Type', _reportType, ['Work Orders', 'Work on Request'], (value) {
                              setState(() {
                                _reportType = value!;
                                _statusFilter = 'All';
                                _priorityFilter = 'All';
                              });
                              _initializeDataStream();
                            }, fontSize),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildDropdown('Status', _statusFilter, _getAvailableFilters(), (value) {
                              setState(() {
                                _statusFilter = value!;
                              });
                              _initializeDataStream();
                            }, fontSize),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildDropdown('Priority', _priorityFilter, ['All', 'High', 'Medium', 'Low'], (value) {
                              setState(() {
                                _priorityFilter = value!;
                              });
                              _initializeDataStream();
                            }, fontSize),
                          ),
                        ],
                      ),
                    ],
                  ),
            const SizedBox(height: 12),
            isMobile
                ? Row(
                    children: [
                      _buildDateButton('Start Date', _startDate, fontSize, true),
                      const SizedBox(width: 12),
                      _buildDateButton('End Date', _endDate, fontSize, false),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: _buildDateButton('Start Date', _startDate, fontSize, true)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildDateButton('End Date', _endDate, fontSize, false)),
                    ],
                  ),
          ],
        ),
    );
  }

  Widget _buildDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged, double fontSize) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      items: items.map((s) => DropdownMenuItem(value: s, child: Text(s, style: GoogleFonts.poppins(fontSize: fontSize)))).toList(),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.surfaceAltColor)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.surfaceAltColor)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: AppColors.primary, width: 2)),
        filled: true,
        fillColor: context.surfaceColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        labelStyle: GoogleFonts.poppins(fontSize: fontSize, color: context.textSecondary),
      ),
      style: GoogleFonts.poppins(fontSize: fontSize, color: context.textPrimary, fontWeight: FontWeight.w500),
      dropdownColor: context.cardColor,
      icon: Icon(Icons.keyboard_arrow_down_rounded, color: context.textSecondary),
    );
  }

  Widget _buildDateButton(String label, DateTime? date, double fontSize, bool isStart) {
    final bool hasDate = date != null;
    return OutlinedButton.icon(
      onPressed: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null && mounted) {
          setState(() {
            if (isStart) {
              _startDate = picked;
              if (_endDate != null && picked.isAfter(_endDate!)) {
                _endDate = null;
              }
            } else {
              if (_startDate == null || !picked.isBefore(_startDate!)) {
                _endDate = picked;
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('End date must be after start date', style: GoogleFonts.poppins(fontSize: fontSize))),
                );
              }
            }
          });
          _initializeDataStream();
        }
      },
      icon: Icon(Icons.calendar_today_rounded, size: 16, color: hasDate ? AppColors.primary : context.textSecondary),
      label: Text(
        date == null ? label : DateFormat.yMMMd().format(date),
        style: GoogleFonts.poppins(fontSize: fontSize, color: hasDate ? AppColors.primary : context.textSecondary, fontWeight: hasDate ? FontWeight.w600 : FontWeight.normal),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: hasDate ? AppColors.primary : AppColors.surfaceAlt, width: hasDate ? 1.5 : 1),
        backgroundColor: hasDate ? AppColors.primary.withValues(alpha: 0.06) : AppColors.surface,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
    );
  }

  Widget _buildSummaryStatsSection({required double padding, required double fontSize}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLiveIndicator(_currentData.length, fontSize: fontSize, padding: padding),
        const SizedBox(height: 12),
        if (_lastGeneratedReport != null) _buildSummarySection(_lastGeneratedReport!, fontSize: fontSize, padding: padding),
      ],
    );
  }

  Widget _buildLiveIndicator(int itemCount, {required double fontSize, required double padding}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: padding, vertical: padding / 2),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text('Live — $itemCount items found', style: GoogleFonts.poppins(fontSize: fontSize, color: AppColors.success, fontWeight: FontWeight.w500)),
          const Spacer(),
          if (_isGenerating)
            Row(
              children: [
                SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.success)),
                const SizedBox(width: 8),
                Text('Generating...', style: GoogleFonts.poppins(fontSize: fontSize, color: AppColors.success)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSummarySection(Map<String, dynamic> report, {required double fontSize, required double padding}) {
    final summary = report['summary'] as Map<String, dynamic>;

    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.surfaceAltColor),
        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AppRadius.sm)),
                child: Icon(Icons.summarize_rounded, color: AppColors.primary, size: fontSize + 2),
              ),
              const SizedBox(width: 10),
              Text('Report Summary', style: GoogleFonts.poppins(fontSize: fontSize + 2, fontWeight: FontWeight.bold, color: context.textPrimary)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildStatChip('Total Items', '${report['totalItems']}', AppColors.primary, fontSize: fontSize),
              if (summary['totalValue'] != null && summary['totalValue'] > 0)
                _buildStatChip('Total Value', '\$${summary['totalValue'].toStringAsFixed(2)}', AppColors.success, fontSize: fontSize),
              if (summary['totalQuantity'] != null && summary['totalQuantity'] > 0)
                _buildStatChip('Total Qty', '${summary['totalQuantity']}', AppColors.warning, fontSize: fontSize),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, String value, Color color, {required double fontSize}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1), // Updated to use withValues
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)), // Updated to use withValues
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: fontSize,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: fontSize,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildDataList({required double fontSize, required double padding}) {
    if (_currentData.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: context.surfaceAltColor),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(AppRadius.md)),
                child: Icon(Icons.description_outlined, size: 40, color: AppColors.primary.withValues(alpha: 0.5)),
              ),
              const SizedBox(height: 14),
              Text('No data found for current filters', style: GoogleFonts.poppins(fontSize: fontSize, color: context.textSecondary, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      );
    }

    // Limit the number of items displayed to prevent performance issues
    final displayData = _currentData.take(50).toList();

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: displayData.length,
      itemBuilder: (context, index) {
        try {
          final item = displayData[index].data() as Map<String, dynamic>?;
          if (item == null) return const SizedBox.shrink();

          return _buildDataCard(item, index, fontSize: fontSize, padding: padding);
        } catch (e) {
          _logger.w('Error building item at index $index: $e');
          return const SizedBox.shrink();
        }
      },
    );
  }

  Widget _buildDataCard(Map<String, dynamic> item, int index, {required double fontSize, required double padding}) {
    final statusColor = _getStatusColor(item['status'] ?? 'Unknown');
    final priority = item['priority'] as String?;
    final priorityColor = priority == 'High' ? AppColors.error : priority == 'Medium' ? AppColors.warning : AppColors.success;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(width: 5, color: statusColor),
            Expanded(
              child: Container(
                margin: EdgeInsets.symmetric(vertical: padding / 4),
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  borderRadius: const BorderRadius.only(topRight: Radius.circular(AppRadius.sm), bottomRight: Radius.circular(AppRadius.sm)),
                  border: Border(
                    top: BorderSide(color: context.surfaceAltColor),
                    right: BorderSide(color: context.surfaceAltColor),
                    bottom: BorderSide(color: context.surfaceAltColor),
                  ),
                ),
                padding: EdgeInsets.all(padding),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: statusColor.withValues(alpha: 0.15),
                      radius: 15,
                      child: Text('${index + 1}', style: GoogleFonts.poppins(color: statusColor, fontWeight: FontWeight.bold, fontSize: fontSize - 2)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['title'] ?? item['name'] ?? 'Item ${index + 1}',
                            style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: fontSize, color: context.textPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              _buildMiniChip(item['status'] ?? 'N/A', statusColor),
                              if (priority != null) _buildMiniChip(priority, priorityColor),
                              if (item['createdAt'] != null)
                                _buildMiniChip(DateFormat.yMMMd().format((item['createdAt'] as Timestamp).toDate()), context.textSecondary),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: context.textSecondary.withValues(alpha: 0.5), size: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(label, style: GoogleFonts.poppins(fontSize: 10, color: color, fontWeight: FontWeight.w500)),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return AppColors.primary;
      case 'in progress':
        return AppColors.warning;
      case 'closed':
        return AppColors.success;
      default:
        return context.textSecondary;
    }
  }
}
