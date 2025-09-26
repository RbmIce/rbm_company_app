import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class Product {
  final String id;
  final String name;
  final String category;
  final int stock;
  final double cost;
  final double price;
  final int lowStockThreshold;
  final String unit;

  Product({
    required this.id,
    required this.name,
    required this.category,
    required this.stock,
    required this.cost,
    required this.price,
    required this.lowStockThreshold,
    required this.unit,
  });

  // NEW: CopyWith method for Product
  Product copyWith({
    String? id,
    String? name,
    String? category,
    int? stock,
    double? cost,
    double? price,
    int? lowStockThreshold,
    String? unit,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      stock: stock ?? this.stock,
      cost: cost ?? this.cost,
      price: price ?? this.price,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      unit: unit ?? this.unit,
    );
  }
}

class Customer {
  final String id;
  final String customerId;
  final String name;
  final String email;
  final String phone;
  final String address;
  final String type;
  final String status;

  Customer({
    required this.id,
    required this.customerId,
    required this.name,
    required this.email,
    required this.phone,
    required this.address,
    required this.type,
    required this.status,
  });

  // CopyWith method for Customer
  Customer copyWith({
    String? id,
    String? customerId,
    String? name,
    String? email,
    String? phone,
    String? address,
    String? type,
    String? status,
  }) {
    return Customer(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      type: type ?? this.type,
      status: status ?? this.status,
    );
  }
}

class SharedDataService with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<Product> _products = [];
  List<Customer> _customers = [];
  bool _isLoading = false;
  bool _hasData = false;

  List<Product> get products => List.unmodifiable(_products);
  List<Customer> get customers => List.unmodifiable(_customers);
  bool get isLoading => _isLoading;
  bool get hasData => _hasData;

  // NEW: Force reload parameter
  Future<void> loadSharedData({bool forceReload = false}) async {
    if (_hasData && !forceReload) {
      return; // Already loaded and not forcing reload
    }

    _isLoading = true;
    notifyListeners(); // Notify that loading has started

    try {
      // Load products
      final productsSnapshot = await _firestore
          .collection('inventory')
          .doc('products')
          .collection('items')
          .get();

      _products = productsSnapshot.docs.map((doc) {
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

      // Load customers
      final customersSnapshot = await _firestore
          .collection('customers')
          .get();

      _customers = customersSnapshot.docs.map((doc) {
        final data = doc.data();
        return Customer(
          id: doc.id,
          customerId: data['customerId'] ?? doc.id, // Fallback to doc.id if customerId is missing
          name: data['name'] ?? '',
          email: data['email'] ?? '',
          phone: data['phone'] ?? '',
          address: data['address'] ?? '',
          type: data['type'] ?? 'Regular',
          status: data['status'] ?? 'Active',
        );
      }).toList();

      _hasData = true;

    } catch (e) {
      print('Error loading shared data: $e');
      _hasData = false;
    } finally {
      _isLoading = false;
      notifyListeners(); // Notify that loading has completed
    }
  }

  // Product methods
  void addProduct(Product product) {
    _products.add(product);
    notifyListeners();
  }

  void updateProduct(Product updatedProduct) {
    final index = _products.indexWhere((p) => p.id == updatedProduct.id);
    if (index != -1) {
      _products[index] = updatedProduct;
      notifyListeners();
    }
  }

  void updateProductStock(String productId, int quantityChange) {
    final index = _products.indexWhere((p) => p.id == productId);
    if (index != -1) {
      final product = _products[index];
      _products[index] = product.copyWith(
        stock: product.stock + quantityChange,
      );
      notifyListeners();
    }
  }

  void removeProduct(String productId) {
    _products.removeWhere((product) => product.id == productId);
    notifyListeners();
  }

  // Customer methods
  void addCustomer(Customer customer) {
    _customers.add(customer);
    notifyListeners();
  }

  void removeCustomer(String customerId) {
    _customers.removeWhere((customer) => customer.id == customerId);
    notifyListeners();
  }

  void updateCustomer(Customer updatedCustomer) {
    final index = _customers.indexWhere((c) => c.id == updatedCustomer.id);
    if (index != -1) {
      _customers[index] = updatedCustomer;
      notifyListeners();
    }
  }

  // NEW: Update customer by customerId (custom ID)
  void updateCustomerByCustomerId(String customerId, Customer updatedCustomer) {
    final index = _customers.indexWhere((c) => c.customerId == customerId);
    if (index != -1) {
      _customers[index] = updatedCustomer;
      notifyListeners();
    }
  }

  // NEW: Remove customer by customerId (custom ID)
  void removeCustomerByCustomerId(String customerId) {
    _customers.removeWhere((customer) => customer.customerId == customerId);
    notifyListeners();
  }

  // Getter methods
  Product? getProductById(String productId) {
    try {
      return _products.firstWhere((product) => product.id == productId);
    } catch (e) {
      return null;
    }
  }

  Customer? getCustomerById(String customerId) {
    try {
      return _customers.firstWhere((customer) => customer.id == customerId);
    } catch (e) {
      return null;
    }
  }

  Customer? getCustomerByCustomerId(String customerId) {
    try {
      return _customers.firstWhere((customer) => customer.customerId == customerId);
    } catch (e) {
      return null;
    }
  }

  Product? getProductByName(String productName) {
    try {
      return _products.firstWhere((product) => product.name == productName);
    } catch (e) {
      return null;
    }
  }

  // NEW: Get customers by status
  List<Customer> getCustomersByStatus(String status) {
    return _customers.where((customer) => customer.status == status).toList();
  }

  // NEW: Get products by category
  List<Product> getProductsByCategory(String category) {
    return _products.where((product) => product.category == category).toList();
  }

  // NEW: Get low stock products
  List<Product> getLowStockProducts() {
    return _products.where((product) => product.stock <= product.lowStockThreshold).toList();
  }

  // NEW: Search products by name
  List<Product> searchProducts(String query) {
    if (query.isEmpty) return _products;
    return _products.where((product) =>
        product.name.toLowerCase().contains(query.toLowerCase())
    ).toList();
  }

  // NEW: Search customers by name or email
  List<Customer> searchCustomers(String query) {
    if (query.isEmpty) return _customers;
    return _customers.where((customer) =>
    customer.name.toLowerCase().contains(query.toLowerCase()) ||
        customer.email.toLowerCase().contains(query.toLowerCase())
    ).toList();
  }

  // Data management methods
  void clearData() {
    _products.clear();
    _customers.clear();
    _hasData = false;
    notifyListeners();
  }

  Future<void> refreshData() async {
    await loadSharedData(forceReload: true);
  }

  // NEW: Initialize method for app startup
  Future<void> initialize() async {
    if (!_hasData) {
      await loadSharedData();
    }
  }

  // NEW: Check if customerId already exists
  bool customerIdExists(String customerId) {
    return _customers.any((customer) => customer.customerId == customerId);
  }

  // NEW: Check if product name already exists
  bool productNameExists(String productName) {
    return _products.any((product) => product.name == productName);
  }

  // NEW: Get next available customer ID (for generating new IDs)
  String getNextCustomerId() {
    final existingIds = _customers.map((c) => c.customerId).toList();
    int nextNumber = 1;

    while (existingIds.contains('CUST-${nextNumber.toString().padLeft(4, '0')}')) {
      nextNumber++;
    }

    return 'CUST-${nextNumber.toString().padLeft(4, '0')}';
  }

  // NEW: Statistics methods
  int get totalProducts => _products.length;
  int get totalCustomers => _customers.length;
  int get activeCustomers => _customers.where((c) => c.status == 'Active').length;
  int get totalLowStockProducts => getLowStockProducts().length;

  // NEW: Export data for debugging
  Map<String, dynamic> exportData() {
    return {
      'products': _products.map((p) => {
        'id': p.id,
        'name': p.name,
        'stock': p.stock,
        'price': p.price,
      }).toList(),
      'customers': _customers.map((c) => {
        'id': c.id,
        'customerId': c.customerId,
        'name': c.name,
        'email': c.email,
      }).toList(),
    };
  }
}