// enhanced_shared_data_service.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rbm/services/shared_data_service.dart';
import 'package:rxdart/rxdart.dart';

class EnhancedSharedDataService with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Stream controllers for real-time data
  final BehaviorSubject<List<Product>> _productsSubject =
  BehaviorSubject<List<Product>>.seeded([]);
  final BehaviorSubject<List<Customer>> _customersSubject =
  BehaviorSubject<List<Customer>>.seeded([]);

  // Stream subscriptions
  StreamSubscription<QuerySnapshot>? _productsStream;
  StreamSubscription<QuerySnapshot>? _customersStream;

  // Loading states
  bool _productsLoading = false;
  bool _customersLoading = false;

  // Public streams
  Stream<List<Product>> get productsStream => _productsSubject.stream;
  Stream<List<Customer>> get customersStream => _customersSubject.stream;
  bool get isLoading => _productsLoading || _customersLoading;

  // Current data (for synchronous access)
  List<Product> get products => _productsSubject.value;
  List<Customer> get customers => _customersSubject.value;

  EnhancedSharedDataService() {
    _initializeStreams();
  }

  void _initializeStreams() {
    // Products stream
    _productsStream = _firestore
        .collection('inventory')
        .doc('products')
        .collection('items')
        .snapshots()
        .listen((snapshot) {
      _productsLoading = false;
      final products = snapshot.docs.map((doc) {
        final data = doc.data();
        return Product(
          id: doc.id,
          name: data['name'] ?? '',
          category: data['category'] ?? '',
          stock: (data['stock'] ?? 0).toInt(),
          cost: (data['cost'] ?? 0.0).toDouble(),
          price: (data['price'] ?? 0.0).toDouble(),
          lowStockThreshold: (data['lowStockThreshold'] ?? 10).toInt(),
          unit: data['unit'] ?? 'kg',
        );
      }).toList();

      _productsSubject.add(products);
      notifyListeners();
    });

    // Customers stream
    _customersStream = _firestore
        .collection('customers')
        .snapshots()
        .listen((snapshot) {
      _customersLoading = false;
      final customers = snapshot.docs.map((doc) {
        final data = doc.data();
        return Customer(
          id: doc.id,
          customerId: data['customerId'] ?? doc.id,
          name: data['name'] ?? '',
          email: data['email'] ?? '',
          phone: data['phone'] ?? '',
          address: data['address'] ?? '',
          type: data['type'] ?? 'Regular',
          status: data['status'] ?? 'Active',
        );
      }).toList();

      _customersSubject.add(customers);
      notifyListeners();
    });
  }

  // Manual refresh if needed
  Future<void> refreshData() async {
    _productsLoading = true;
    _customersLoading = true;
    notifyListeners();

    // Streams will automatically update when data changes
  }

  @override
  void dispose() {
    _productsStream?.cancel();
    _customersStream?.cancel();
    _productsSubject.close();
    _customersSubject.close();
    super.dispose();
  }
}