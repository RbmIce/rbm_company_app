// dashboard_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'shared_data_service.dart';

class DashboardService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Inventory stats - don't call loadSharedData here
  Future<Map<String, dynamic>> getInventoryStats(SharedDataService sharedData) async {
    // Use the existing data if available, but don't trigger loading during build
    if (sharedData.products.isEmpty) {
      // If products are empty, return default values instead of loading
      return {
        'totalProducts': 0,
        'lowStockItems': 0,
        'totalStockValue': 0.0,
      };
    }

    final totalProducts = sharedData.products.length;
    final lowStockItems = sharedData.products.where((p) => p.stock <= p.lowStockThreshold).length;
    final totalStockValue = sharedData.products.fold(0.0, (sum, p) => sum + (p.stock * p.cost));

    return {
      'totalProducts': totalProducts,
      'lowStockItems': lowStockItems,
      'totalStockValue': totalStockValue,
    };
  }

  // Sales stats - pending orders
  Future<int> getPendingOrdersCount() async {
    try {
      final snapshot = await _firestore
          .collection('sales')
          .doc('orders')
          .collection('sales_orders')
          .where('status', isEqualTo: 'Pending')
          .count()
          .get();

      return snapshot.count ?? 0;
    } catch (e) {
      print('Error getting pending orders: $e');
      return 0;
    }
  }

  // Accounting stats - net income
  Future<double> getNetIncome() async {
    try {
      // Get revenue from delivered sales orders
      final revenueSnapshot = await _firestore
          .collection('sales')
          .doc('orders')
          .collection('sales_orders')
          .where('status', isEqualTo: 'Delivered')
          .get();

      final totalRevenue = revenueSnapshot.docs.fold(0.0, (sum, doc) {
        final data = doc.data();
        return sum + (data['total'] ?? 0.0);
      });

      // Get total expenses
      final expensesSnapshot = await _firestore
          .collection('accounting')
          .doc('expenses')
          .collection('items')
          .get();

      final totalExpenses = expensesSnapshot.docs.fold(0.0, (sum, doc) {
        final data = doc.data();
        return sum + (data['amount'] ?? 0.0);
      });

      return totalRevenue - totalExpenses;
    } catch (e) {
      print('Error getting net income: $e');
      return 0.0;
    }
  }

  // CRM stats - total customers
  Future<int> getTotalCustomers() async {
    try {
      final snapshot = await _firestore
          .collection('customers')
          .count()
          .get();

      return snapshot.count ?? 0;
    } catch (e) {
      print('Error getting total customers: $e');
      return 0;
    }
  }

  // HR stats - present and absent workers (FIXED: Simplified query to avoid index requirement)
  Future<Map<String, int>> getWorkersAttendance() async {
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);

      // Get all attendance records for today and filter locally
      final attendanceSnapshot = await _firestore
          .collection('hr')
          .doc('attendance')
          .collection('records')
          .where('date', isGreaterThanOrEqualTo: startOfDay)
          .get();

      int presentCount = 0;
      int absentCount = 0;

      for (final doc in attendanceSnapshot.docs) {
        final data = doc.data();
        final status = data['status']?.toString().toLowerCase() ?? '';

        if (status == 'present') {
          presentCount++;
        } else if (status == 'absent') {
          absentCount++;
        }
      }

      return {
        'present': presentCount,
        'absent': absentCount,
      };
    } catch (e) {
      print('Error getting workers attendance: $e');

      // Fallback: Use a simpler approach if the above still causes issues
      try {
        // Alternative approach - get all records and filter completely locally
        final allRecords = await _firestore
            .collection('hr')
            .doc('attendance')
            .collection('records')
            .get();

        final today = DateTime.now();
        int presentCount = 0;
        int absentCount = 0;

        for (final doc in allRecords.docs) {
          final data = doc.data();
          final recordDate = data['date']?.toDate();

          // Check if record is from today
          if (recordDate != null &&
              recordDate.year == today.year &&
              recordDate.month == today.month &&
              recordDate.day == today.day) {

            final status = data['status']?.toString().toLowerCase() ?? '';
            if (status == 'present') {
              presentCount++;
            } else if (status == 'absent') {
              absentCount++;
            }
          }
        }

        return {
          'present': presentCount,
          'absent': absentCount,
        };
      } catch (fallbackError) {
        print('Fallback error getting workers attendance: $fallbackError');
        return {'present': 0, 'absent': 0};
      }
    }
  }

  // Invoice stats - pending invoices
  Future<int> getPendingInvoicesCount() async {
    try {
      final snapshot = await _firestore
          .collection('invoices')
          .where('status', isEqualTo: 'Pending')
          .count()
          .get();

      return snapshot.count ?? 0;
    } catch (e) {
      print('Error getting pending invoices: $e');
      return 0;
    }
  }

  // Total revenue
  Future<double> getTotalRevenue() async {
    try {
      final snapshot = await _firestore
          .collection('sales')
          .doc('orders')
          .collection('sales_orders')
          .where('status', isEqualTo: 'Delivered')
          .get();

      return snapshot.docs.fold(0.0, (sum, doc) async {
        final data = doc.data();
        final total = await sum + (data['total'] ?? 0.0);
        return total;
      });
    } catch (e) {
      print('Error getting total revenue: $e');
      return 0.0;
    }
  }

  // Total orders count
  Future<int> getTotalOrdersCount() async {
    try {
      final snapshot = await _firestore
          .collection('sales')
          .doc('orders')
          .collection('sales_orders')
          .count()
          .get();

      return snapshot.count ?? 0;
    } catch (e) {
      print('Error getting total orders: $e');
      return 0;
    }
  }
}