import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';

class HumanResourceModule extends StatefulWidget {
  const HumanResourceModule({super.key});

  @override
  State<HumanResourceModule> createState() => _HumanResourceModuleState();
}

class _HumanResourceModuleState extends State<HumanResourceModule> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Worker> _workers = [];
  List<DisciplinaryRecord> _disciplinaryRecords = [];
  bool _isLoading = true;
  int _currentTabIndex = 0;
  DateTime _selectedDate = DateTime.now();
  String? _selectedMonthYear;
  int _offDays = 0;
  String? _selectedWorkerId;

  // Stream subscriptions
  StreamSubscription<QuerySnapshot>? _workersStream;

  @override
  void initState() {
    super.initState();
    _selectedMonthYear = _getCurrentMonthYear();
    _setupRealtimeListeners();
  }

  @override
  void dispose() {
    _workersStream?.cancel();
    super.dispose();
  }

  String _getCurrentMonthYear() {
    return DateFormat('yyyy_MM').format(DateTime.now());
  }

  String _getMonthYearFromDate(DateTime date) {
    return DateFormat('yyyy_MM').format(date);
  }

  int _getDaysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  String _binaryToHex(String binary) {
    final paddedBinary = binary.padLeft(32, '0');
    final intValue = int.parse(paddedBinary, radix: 2);
    return intValue.toRadixString(16).toUpperCase().padLeft(8, '0');
  }

  String _hexToBinary(String hex) {
    final intValue = int.parse(hex, radix: 16);
    return intValue.toRadixString(2).padLeft(32, '0');
  }

  String _updateAttendanceBit(String currentHex, int day, bool present) {
    String binary = _hexToBinary(currentHex);
    // Fix: Use direct indexing (day - 1) instead of reverse indexing
    final dayIndex = day - 1; // Day 1 = bit 0, Day 31 = bit 30
    final newBinary = binary.substring(0, dayIndex) +
        (present ? '1' : '0') +
        binary.substring(dayIndex + 1);
    return _binaryToHex(newBinary);
  }
  int _getPresentDays(String hex, int year, int month) {
    final binary = _hexToBinary(hex);
    final daysInMonth = _getDaysInMonth(year, month);
    int presentDays = 0;

    for (int i = 0; i < daysInMonth; i++) {
      // Fix: Use direct indexing
      if (binary[i] == '1') {
        presentDays++;
      }
    }

    return presentDays;
  }

  String _initializeMonthHex(int year, int month) {
    String binary = '';
    for (int i = 0; i < 32; i++) {
      binary += '0';
    }
    return _binaryToHex(binary);
  }

  void _setupRealtimeListeners() {
    _workersStream = _firestore
        .collection('workers')
        .orderBy('name')
        .snapshots()
        .listen((snapshot) {
      setState(() {
        _workers = snapshot.docs.map((doc) {
          final data = doc.data();
          return Worker(
            id: doc.id,
            workerId: data['workerId'] ?? '',
            name: data['name'] ?? 'Unknown',
            position: data['position'] ?? 'Employee',
            department: data['department'] ?? 'General',
            email: data['email'] ?? '',
            phone: data['phone'] ?? '',
            hireDate: data['hireDate']?.toDate() ?? DateTime.now(),
            disciplinaryPoints: data['disciplinaryPoints'] ?? 0,
            salary: (data['salary'] ?? 0.0).toDouble(),
            isActive: data['isActive'] ?? true,
            photoUrl: data['photoUrl'],
            monthlyAttendance: Map<String, String>.from(data['attendance'] ?? {}),
          );
        }).toList();
      });
    });

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _updateMonthlyAttendance(String workerId, DateTime date, bool present) async {
    try {
      final monthYear = _getMonthYearFromDate(date);
      final day = date.day;

      final workerDoc = _firestore.collection('workers').doc(workerId);
      final workerSnapshot = await workerDoc.get();

      if (workerSnapshot.exists) {
        final data = workerSnapshot.data()!;
        final monthlyAttendance = Map<String, String>.from(data['attendance'] ?? {});

        String currentHex = monthlyAttendance[monthYear] ?? _initializeMonthHex(date.year, date.month);
        String newHex = _updateAttendanceBit(currentHex, day, present);

        monthlyAttendance[monthYear] = newHex;

        await workerDoc.update({
          'attendance': monthlyAttendance,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Also create a timestamped attendance record for history
        await _firestore
            .collection('workers')
            .doc(workerId)
            .collection('attendance_history')
            .add({
          'date': Timestamp.fromDate(DateTime(date.year, date.month, date.day)),
          'status': present ? 'Present' : 'Absent',
          'timestamp': FieldValue.serverTimestamp(),
          'method': 'app',
        });
      }
    } catch (e) {
      print('Error updating monthly attendance: $e');
    }
  }

  Future<void> _loadDisciplinaryHistory(String workerId) async {
    try {
      final snapshot = await _firestore
          .collection('workers')
          .doc(workerId)
          .collection('disciplinary_records')
          .orderBy('date', descending: true)
          .limit(100)
          .get();

      setState(() {
        _disciplinaryRecords = snapshot.docs.map((doc) {
          final data = doc.data();
          return DisciplinaryRecord(
            id: doc.id,
            workerId: data['workerId'] ?? '',
            workerName: data['workerName'] ?? '',
            reason: data['reason'] ?? '',
            points: (data['points'] ?? 0).toInt(),
            date: data['date']?.toDate(),
            createdBy: data['createdBy'] ?? '',
          );
        }).toList();
      });
    } catch (e) {
      print('Error loading disciplinary history: $e');
      setState(() {
        _disciplinaryRecords = [];
      });
    }
  }

  Future<void> _addWorker(Worker worker) async {
    try {
      if (worker.workerId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Worker ID is required')),
        );
        return;
      }

      // Check if workerId already exists
      final existingWorker = await _firestore
          .collection('workers')
          .doc(worker.workerId)
          .get();

      if (existingWorker.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Worker ID already exists')),
        );
        return;
      }

      // Use workerId as document ID
      await _firestore.collection('workers').doc(worker.workerId).set({
        'workerId': worker.workerId,
        'name': worker.name,
        'position': worker.position,
        'department': worker.department,
        'email': worker.email,
        'phone': worker.phone,
        'hireDate': worker.hireDate,
        'disciplinaryPoints': worker.disciplinaryPoints,
        'salary': worker.salary,
        'isActive': worker.isActive,
        'photoUrl': worker.photoUrl,
        'attendance': {},
        'createdAt': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Worker added successfully')),
      );
    } catch (e) {
      print('Error adding worker: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error adding worker')),
      );
    }
  }

  Future<void> _updateWorker(Worker worker) async {
    try {
      if (worker.workerId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Worker ID is required')),
        );
        return;
      }

      await _firestore.collection('workers').doc(worker.id).update({
        'workerId': worker.workerId,
        'name': worker.name,
        'position': worker.position,
        'department': worker.department,
        'email': worker.email,
        'phone': worker.phone,
        'disciplinaryPoints': worker.disciplinaryPoints,
        'salary': worker.salary,
        'isActive': worker.isActive,
        'photoUrl': worker.photoUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Worker updated successfully')),
      );
    } catch (e) {
      print('Error updating worker: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error updating worker')),
      );
    }
  }

  Future<void> _deleteWorker(String workerId) async {
    try {
      await _firestore.collection('workers').doc(workerId).delete();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Worker deleted successfully')),
      );
    } catch (e) {
      print('Error deleting worker: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error deleting worker')),
      );
    }
  }

  Future<void> _markAttendance(String workerId, bool present) async {
    try {
      final worker = _workers.firstWhere(
            (w) => w.id == workerId,
        orElse: () => Worker(
          id: '',
          workerId: '',
          name: 'Unknown',
          position: '',
          department: '',
          email: '',
          phone: '',
          hireDate: DateTime.now(),
          disciplinaryPoints: 0,
          salary: 0.0,
          isActive: false,
        ),
      );

      if (worker.id.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Worker not found')),
        );
        return;
      }

      await _updateMonthlyAttendance(workerId, _selectedDate, present);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Attendance marked ${present ? 'Present' : 'Absent'} successfully')),
      );
    } catch (e) {
      print('Error marking attendance: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error marking attendance')),
      );
    }
  }

  Future<void> _addDisciplinaryPoint(String workerId, String reason, int points) async {
    try {
      final worker = _workers.firstWhere(
            (w) => w.id == workerId,
        orElse: () => Worker(
          id: '',
          workerId: '',
          name: 'Unknown',
          position: '',
          department: '',
          email: '',
          phone: '',
          hireDate: DateTime.now(),
          disciplinaryPoints: 0,
          salary: 0.0,
          isActive: false,
        ),
      );

      if (worker.id.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Worker not found')),
        );
        return;
      }

      final workerDoc = _firestore.collection('workers').doc(workerId);

      await workerDoc.update({
        'disciplinaryPoints': FieldValue.increment(points),
      });

      await _firestore
          .collection('workers')
          .doc(workerId)
          .collection('disciplinary_records')
          .add({
        'workerId': workerId,
        'workerName': worker.name,
        'reason': reason,
        'points': points,
        'date': FieldValue.serverTimestamp(),
        'createdBy': 'Admin',
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$points disciplinary points added for $reason')),
      );
    } catch (e) {
      print('Error adding disciplinary points: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error adding disciplinary points')),
      );
    }
  }

  Future<void> _generateReport() async {
    if (_selectedMonthYear == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a month')),
      );
      return;
    }

    try {
      final parts = _selectedMonthYear!.split('_');
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final daysInMonth = _getDaysInMonth(year, month);
      final expectedWorkingDays = daysInMonth - _offDays;

      final workersToReport = _selectedWorkerId != null
          ? _workers.where((w) => w.id == _selectedWorkerId).toList()
          : _workers.where((w) => w.isActive).toList();

      final PdfDocument document = PdfDocument();
      final PdfPage page = document.pages.add();
      PdfGraphics graphics = page.graphics;

      final ByteData logoData = await rootBundle.load('assets/icons/rbm_ice_logo.png');
      final Uint8List logoBytes = logoData.buffer.asUint8List();
      final PdfBitmap logo = PdfBitmap(logoBytes);

      final double logoWidth = 100;
      final double logoHeight = 100;
      final double logoX = (page.size.width - logoWidth) / 2;
      final double logoY = 30;

      graphics.drawImage(logo, Rect.fromLTWH(logoX, logoY, logoWidth, logoHeight));

      final PdfFont titleFont = PdfStandardFont(PdfFontFamily.helvetica, 18, style: PdfFontStyle.bold);
      final PdfFont subtitleFont = PdfStandardFont(PdfFontFamily.helvetica, 14);
      final PdfFont headerFont = PdfStandardFont(PdfFontFamily.helvetica, 12, style: PdfFontStyle.bold);
      final PdfFont normalFont = PdfStandardFont(PdfFontFamily.helvetica, 10);
      final PdfFont smallFont = PdfStandardFont(PdfFontFamily.helvetica, 9);

      graphics.drawString(
        'RBM ICE COMPANY',
        titleFont,
        bounds: Rect.fromLTWH(0, logoY + logoHeight + 10, page.size.width, 25),
        format: PdfStringFormat(alignment: PdfTextAlignment.center),
      );

      graphics.drawString(
        'WORKERS ATTENDANCE REPORT',
        subtitleFont,
        bounds: Rect.fromLTWH(0, logoY + logoHeight + 40, page.size.width, 20),
        format: PdfStringFormat(alignment: PdfTextAlignment.center),
      );

      graphics.drawString(
        'Month: ${DateFormat('MMMM yyyy').format(DateTime(year, month))}',
        normalFont,
        bounds: Rect.fromLTWH(0, logoY + logoHeight + 65, page.size.width, 15),
        format: PdfStringFormat(alignment: PdfTextAlignment.center),
      );

      graphics.drawString(
        'Total Days: $daysInMonth | Off Days: $_offDays | Expected Working Days: $expectedWorkingDays',
        smallFont,
        bounds: Rect.fromLTWH(0, logoY + logoHeight + 85, page.size.width, 12),
        format: PdfStringFormat(alignment: PdfTextAlignment.center),
      );

      graphics.drawString(
        'Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
        smallFont,
        bounds: Rect.fromLTWH(0, logoY + logoHeight + 100, page.size.width, 12),
        format: PdfStringFormat(alignment: PdfTextAlignment.center),
      );

      double yPosition = logoY + logoHeight + 120;

      graphics.drawLine(
        PdfPen(PdfColor(0, 0, 0), width: 1),
        Offset(40, yPosition - 5),
        Offset(page.size.width - 40, yPosition - 5),
      );

      graphics.drawString('S/N', headerFont, bounds: Rect.fromLTWH(40, yPosition, 30, 20));
      graphics.drawString('Name', headerFont, bounds: Rect.fromLTWH(70, yPosition, 100, 20));
      graphics.drawString('Department', headerFont, bounds: Rect.fromLTWH(140, yPosition, 80, 20));
      graphics.drawString('Attendance', headerFont, bounds: Rect.fromLTWH(220, yPosition, 70, 20));
      graphics.drawString('Points', headerFont, bounds: Rect.fromLTWH(310, yPosition, 50, 20));
      graphics.drawString('Salary', headerFont, bounds: Rect.fromLTWH(370, yPosition, 80, 20));

      graphics.drawLine(
        PdfPen(PdfColor(0, 0, 0), width: 1),
        Offset(40, yPosition + 25),
        Offset(page.size.width - 40, yPosition + 25),
      );

      yPosition += 30;

      for (int i = 0; i < workersToReport.length; i++) {
        final worker = workersToReport[i];
        final hexCode = worker.monthlyAttendance[_selectedMonthYear] ?? _initializeMonthHex(year, month);
        final presentDays = _getPresentDays(hexCode, year, month);
        final attendancePercentage = expectedWorkingDays > 0 ? (presentDays / expectedWorkingDays * 100) : 0;
        final equivalentSalary = expectedWorkingDays > 0
            ? worker.salary * (presentDays / expectedWorkingDays)
            : 0;

        if (i % 2 == 1) {
          graphics.drawRectangle(
            brush: PdfSolidBrush(PdfColor(240, 240, 240)),
            bounds: Rect.fromLTWH(40, yPosition - 5, page.size.width - 80, 20),
          );
        }

        graphics.drawString('${i + 1}', normalFont, bounds: Rect.fromLTWH(40, yPosition, 30, 20));
        graphics.drawString(worker.name, normalFont, bounds: Rect.fromLTWH(70, yPosition, 100, 20));
        graphics.drawString(worker.department, normalFont, bounds: Rect.fromLTWH(170, yPosition, 80, 20));

        final PdfColor percentageColor = attendancePercentage >= 90
            ? PdfColor(0, 128, 0)
            : attendancePercentage >= 70
            ? PdfColor(255, 165, 0)
            : PdfColor(255, 0, 0);

        graphics.drawString(
          '${attendancePercentage.toStringAsFixed(1)}%',
          normalFont,
          brush: PdfSolidBrush(percentageColor),
          bounds: Rect.fromLTWH(250, yPosition, 70, 20),
        );

        final PdfColor pointsColor = worker.disciplinaryPoints == 0
            ? PdfColor(0, 128, 0)
            : worker.disciplinaryPoints <= 3
            ? PdfColor(255, 165, 0)
            : PdfColor(255, 0, 0);

        graphics.drawString(
          worker.disciplinaryPoints.toString(),
          normalFont,
          brush: PdfSolidBrush(pointsColor),
          bounds: Rect.fromLTWH(320, yPosition, 50, 20),
        );

        graphics.drawString(
          '${equivalentSalary.toStringAsFixed(0)} FCFA',
          normalFont,
          bounds: Rect.fromLTWH(370, yPosition, 80, 20),
        );

        yPosition += 25;

        if (yPosition > page.size.height - 50) {
          yPosition = 50;
          final newPage = document.pages.add();
          graphics = newPage.graphics;

          graphics.drawImage(logo, Rect.fromLTWH(logoX, 30, logoWidth, logoHeight));

          graphics.drawString('S/N', headerFont, bounds: Rect.fromLTWH(40, yPosition, 30, 20));
          graphics.drawString('Name', headerFont, bounds: Rect.fromLTWH(70, yPosition, 100, 20));
          graphics.drawString('Department', headerFont, bounds: Rect.fromLTWH(140, yPosition, 80, 20));
          graphics.drawString('Attendance', headerFont, bounds: Rect.fromLTWH(220, yPosition, 70, 20));
          graphics.drawString('Points', headerFont, bounds: Rect.fromLTWH(310, yPosition, 50, 20));
          graphics.drawString('Salary', headerFont, bounds: Rect.fromLTWH(370, yPosition, 80, 20));

          graphics.drawLine(
            PdfPen(PdfColor(0, 0, 0), width: 1),
            Offset(40, yPosition - 5),
            Offset(page.size.width - 40, yPosition - 5),
          );
          graphics.drawLine(
            PdfPen(PdfColor(0, 0, 0), width: 1),
            Offset(40, yPosition + 25),
            Offset(page.size.width - 40, yPosition + 25),
          );

          yPosition += 30;
        }
      }

      graphics.drawLine(
        PdfPen(PdfColor(0, 0, 0), width: 1),
        Offset(40, yPosition - 5),
        Offset(page.size.width - 40, yPosition - 5),
      );

      final totalWorkers = workersToReport.length;
      final totalPresent = workersToReport.fold(0, (sum, worker) {
        final hexCode = worker.monthlyAttendance[_selectedMonthYear] ?? _initializeMonthHex(year, month);
        return sum + _getPresentDays(hexCode, year, month);
      });
      final averageAttendance = totalWorkers > 0 ? (totalPresent / (totalWorkers * expectedWorkingDays) * 100) : 0;

      graphics.drawString(
        'Summary: $totalWorkers workers | Average Attendance: ${averageAttendance.toStringAsFixed(1)}%',
        headerFont,
        bounds: Rect.fromLTWH(0, yPosition + 10, page.size.width, 20),
        format: PdfStringFormat(alignment: PdfTextAlignment.center),
      );

      final List<int> bytes = await document.save();
      document.dispose();

      final Directory directory = await getApplicationDocumentsDirectory();
      final String path = directory.path;
      final File file = File('$path/workers_report_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await file.writeAsBytes(bytes);

      OpenFile.open(file.path);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF report generated successfully')),
      );
    } catch (e) {
      print('Error generating PDF: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error generating PDF report')),
      );
    }
  }

  // Add these progress indicator methods to HR module dialogs

  void _showAddWorkerDialog() {
    final nameController = TextEditingController();
    final positionController = TextEditingController();
    final departmentController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    final salaryController = TextEditingController();
    final workerIdController = TextEditingController();

    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Add New Worker'),
            content: isSubmitting
                ? SizedBox(
              height: 150,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[800]!),
                    ),
                    const SizedBox(height: 16),
                    const Text('Adding worker...'),
                  ],
                ),
              ),
            )
                : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: workerIdController,
                    decoration: const InputDecoration(
                      labelText: 'Worker ID *',
                      hintText: 'W001, W002, etc.',
                    ),
                  ),
                  TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Full Name *')),
                  TextField(controller: positionController, decoration: const InputDecoration(labelText: 'Position *')),
                  TextField(controller: departmentController, decoration: const InputDecoration(labelText: 'Department *')),
                  TextField(controller: emailController, decoration: const InputDecoration(labelText: 'Email')),
                  TextField(controller: phoneController, decoration: const InputDecoration(labelText: 'Phone')),
                  TextField(controller: salaryController, decoration: const InputDecoration(labelText: 'Salary *'), keyboardType: TextInputType.number),
                ],
              ),
            ),
            actions: isSubmitting
                ? []
                : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (workerIdController.text.isEmpty ||
                      nameController.text.isEmpty ||
                      positionController.text.isEmpty ||
                      departmentController.text.isEmpty ||
                      salaryController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please fill all required fields')),
                    );
                    return;
                  }

                  setState(() {
                    isSubmitting = true;
                  });

                  final worker = Worker(
                    id: workerIdController.text,
                    workerId: workerIdController.text,
                    name: nameController.text,
                    position: positionController.text,
                    department: departmentController.text,
                    email: emailController.text,
                    phone: phoneController.text,
                    hireDate: DateTime.now(),
                    disciplinaryPoints: 0,
                    salary: double.tryParse(salaryController.text) ?? 0.0,
                    isActive: true,
                  );

                  await _addWorker(worker);

                  if (mounted) {
                    Navigator.pop(context);
                  }
                },
                child: const Text('Add Worker'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditWorkerDialog(Worker worker) {
    final nameController = TextEditingController(text: worker.name);
    final positionController = TextEditingController(text: worker.position);
    final departmentController = TextEditingController(text: worker.department);
    final emailController = TextEditingController(text: worker.email);
    final phoneController = TextEditingController(text: worker.phone);
    final salaryController = TextEditingController(text: worker.salary.toString());
    final workerIdController = TextEditingController(text: worker.workerId);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Worker'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: workerIdController,
                decoration: const InputDecoration(
                  labelText: 'Worker ID ',
                  hintText: 'W001, W002, etc.',
                ),
              ),
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Full Name')),
              TextField(controller: positionController, decoration: const InputDecoration(labelText: 'Position')),
              TextField(controller: departmentController, decoration: const InputDecoration(labelText: 'Department')),
              TextField(controller: emailController, decoration: const InputDecoration(labelText: 'Email')),
              TextField(controller: phoneController, decoration: const InputDecoration(labelText: 'Phone')),
              TextField(controller: salaryController, decoration: const InputDecoration(labelText: 'Salary'), keyboardType: TextInputType.number),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (workerIdController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Worker ID is required')),
                );
                return;
              }

              final updatedWorker = Worker(
                id: worker.id,
                workerId: workerIdController.text,
                name: nameController.text,
                position: positionController.text,
                department: departmentController.text,
                email: emailController.text,
                phone: phoneController.text,
                hireDate: worker.hireDate,
                disciplinaryPoints: worker.disciplinaryPoints,
                salary: double.tryParse(salaryController.text) ?? worker.salary,
                isActive: worker.isActive,
                photoUrl: worker.photoUrl,
                monthlyAttendance: worker.monthlyAttendance,
              );
              await _updateWorker(updatedWorker);
              Navigator.pop(context);
            },
            child: const Text('Update Worker'),
          ),
        ],
      ),
    );
  }

  void _showDisciplinaryDialog(String workerId) {
    final reasonController = TextEditingController();
    final pointsController = TextEditingController(text: '1');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Disciplinary Points'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: reasonController, decoration: const InputDecoration(labelText: 'Reason *')),
              TextField(controller: pointsController, decoration: const InputDecoration(labelText: 'Points to add *'), keyboardType: TextInputType.number),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final points = int.tryParse(pointsController.text) ?? 1;
              if (reasonController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Reason is required')),
                );
                return;
              }
              await _addDisciplinaryPoint(workerId, reasonController.text, points);
              Navigator.pop(context);
            },
            child: const Text('Add Points'),
          ),
        ],
      ),
    );
  }

  void _showDisciplinaryHistory(String workerId) {
    _loadDisciplinaryHistory(workerId);
    final worker = _workers.firstWhere((w) => w.id == workerId);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Disciplinary History - ${worker.name}'),
        content: SizedBox(
          width: double.maxFinite,
          child: _disciplinaryRecords.isEmpty
              ? const Text('No disciplinary records found')
              : ListView.builder(
            shrinkWrap: true,
            itemCount: _disciplinaryRecords.length,
            itemBuilder: (context, index) {
              final record = _disciplinaryRecords[index];
              return ListTile(
                title: Text(record.reason),
                subtitle: Text('${record.points} points - ${DateFormat('yyyy-MM-dd HH:mm').format(record.date!)}'),
                trailing: Text(record.createdBy),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading HR data...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Human Resource Module'),
        backgroundColor: Colors.blue[800],
      ),
      body: Column(
        children: [
          _buildTabBar(),
          if (_currentTabIndex == 0) _buildWorkersList(),
          if (_currentTabIndex == 1) _buildAttendanceView(),
          if (_currentTabIndex == 2) _buildReportsView(),
        ],
      ),
      floatingActionButton: _currentTabIndex == 0
          ? FloatingActionButton(
        onPressed: _showAddWorkerDialog,
        backgroundColor: Colors.blue[800],
        child: const Icon(Icons.person_add, color: Colors.white),
      )
          : null,
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      child: Row(
        children: [
          _buildTabButton('Workers', 0),
          _buildTabButton('Attendance', 1),
          _buildTabButton('Reports', 2),
        ],
      ),
    );
  }

  Widget _buildTabButton(String text, int index) {
    final isSelected = _currentTabIndex == index;
    return Expanded(
      child: TextButton(
        onPressed: () {
          setState(() {
            _currentTabIndex = index;
          });
        },
        style: TextButton.styleFrom(
          foregroundColor: isSelected ? Colors.blue[800] : Colors.grey,
          backgroundColor: isSelected ? Colors.blue[50] : Colors.transparent,
          shape: const RoundedRectangleBorder(),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        child: Text(text),
      ),
    );
  }

  Widget _buildWorkersList() {
    return Expanded(
      child: RefreshIndicator(
        onRefresh: () async {
          setState(() {
            _isLoading = true;
          });
          _setupRealtimeListeners();
        },
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _workers.length,
          itemBuilder: (context, index) {
            final worker = _workers[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blue[100],
                  child: worker.photoUrl != null
                      ? Image.network(worker.photoUrl!)
                      : Text(worker.name[0]),
                ),
                title: Text(worker.name),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${worker.position} - ${worker.department}'),
                    Text('ID: ${worker.workerId}'),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Chip(
                      label: Text('Points: ${worker.disciplinaryPoints}'),
                      backgroundColor: worker.disciplinaryPoints > 0 ? Colors.orange[100] : Colors.green[100],
                    ),
                    PopupMenuButton(
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'edit', child: Text('Edit')),
                        const PopupMenuItem(value: 'disciplinary', child: Text('Add Points')),
                        const PopupMenuItem(value: 'history', child: Text('View History')),
                        const PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                      onSelected: (value) {
                        if (value == 'edit') {
                          _showEditWorkerDialog(worker);
                        } else if (value == 'disciplinary') {
                          _showDisciplinaryDialog(worker.id);
                        } else if (value == 'history') {
                          _showDisciplinaryHistory(worker.id);
                        } else if (value == 'delete') {
                          _deleteWorker(worker.id);
                        }
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildAttendanceView() {
    return Expanded(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Attendance for ${DateFormat('yyyy-MM-dd').format(_selectedDate)}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.calendar_today),
                  onPressed: () async {
                    final DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null && picked != _selectedDate) {
                      setState(() {
                        _selectedDate = picked;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _workers.length,
              itemBuilder: (context, index) {
                final worker = _workers[index];
                final monthYear = _getMonthYearFromDate(_selectedDate);
                final hexCode = worker.monthlyAttendance[monthYear] ?? _initializeMonthHex(_selectedDate.year, _selectedDate.month);
                final binary = _hexToBinary(hexCode);
                // Fix: Use direct indexing
                final dayIndex = _selectedDate.day - 1;
                final isPresent = dayIndex < binary.length ? binary[dayIndex] == '1' : false;

                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue[100],
                      child: Text(worker.name[0]),
                    ),
                    title: Text(worker.name),
                    subtitle: Text('Status: ${isPresent ? 'Present' : 'Absent'}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isPresent)
                          IconButton(
                            icon: const Icon(Icons.cancel, color: Colors.red),
                            onPressed: () => _markAttendance(worker.id, false),
                            tooltip: 'Mark Absent',
                          ),
                        if (!isPresent)
                          IconButton(
                            icon: const Icon(Icons.check_circle, color: Colors.green),
                            onPressed: () => _markAttendance(worker.id, true),
                            tooltip: 'Mark Present',
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportsView() {
    final months = _generateMonthOptions();

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Generate Workers Report',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // Worker selection
            DropdownButtonFormField<String>(
              value: _selectedWorkerId,
              decoration: const InputDecoration(
                labelText: 'Select Worker (Optional)',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('All Workers')),
                ..._workers.map((worker) => DropdownMenuItem(
                  value: worker.id,
                  child: Text('${worker.name} (${worker.workerId})'),
                )).toList(),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedWorkerId = value;
                });
              },
            ),
            const SizedBox(height: 16),

            // Month selection
            DropdownButtonFormField<String>(
              value: _selectedMonthYear,
              decoration: const InputDecoration(
                labelText: 'Select Month',
                border: OutlineInputBorder(),
              ),
              items: months.map((month) {
                return DropdownMenuItem(
                  value: month['value'],
                  child: Text(month['label']!),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedMonthYear = value;
                });
              },
            ),
            const SizedBox(height: 16),

            // Off days input
            TextField(
              decoration: const InputDecoration(
                labelText: 'Number of Off Days',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (value) {
                _offDays = int.tryParse(value) ?? 0;
              },
            ),
            const SizedBox(height: 16),

            ElevatedButton(
              onPressed: _generateReport,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[800],
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
              ),
              child: const Text('Generate PDF Report'),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, String>> _generateMonthOptions() {
    final List<Map<String, String>> months = [];
    final now = DateTime.now();

    for (int i = 0; i < 12; i++) {
      final date = DateTime(now.year, now.month - i);
      final value = DateFormat('yyyy_MM').format(date);
      final label = DateFormat('MMMM yyyy').format(date);
      months.add({'value': value, 'label': label});
    }

    return months;
  }
}

class Worker {
  final String id;
  final String workerId;
  final String name;
  final String position;
  final String department;
  final String email;
  final String phone;
  final DateTime hireDate;
  final int disciplinaryPoints;
  final double salary;
  final bool isActive;
  final String? photoUrl;
  final Map<String, String> monthlyAttendance;

  Worker({
    required this.id,
    required this.workerId,
    required this.name,
    required this.position,
    required this.department,
    required this.email,
    required this.phone,
    required this.hireDate,
    required this.disciplinaryPoints,
    required this.salary,
    required this.isActive,
    this.photoUrl,
    this.monthlyAttendance = const {},
  });
}

class AttendanceRecord {
  final String id;
  final String workerId;
  final String workerName;
  final DateTime date;
  final String status;

  AttendanceRecord({
    required this.id,
    required this.workerId,
    required this.workerName,
    required this.date,
    required this.status,
  });
}

class DisciplinaryRecord {
  final String id;
  final String workerId;
  final String workerName;
  final String reason;
  final int points;
  final DateTime? date;
  final String createdBy;

  DisciplinaryRecord({
    required this.id,
    required this.workerId,
    required this.workerName,
    required this.reason,
    required this.points,
    required this.date,
    required this.createdBy,
  });
}