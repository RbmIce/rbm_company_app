// sales_data_provider.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rxdart/rxdart.dart';

import '../models/sales_model.dart';

class SalesDataProvider with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final BehaviorSubject<List<SalesOrder>> _ordersSubject =
  BehaviorSubject<List<SalesOrder>>.seeded([]);
  final BehaviorSubject<List<Quotation>> _quotationsSubject =
  BehaviorSubject<List<Quotation>>.seeded([]);

  StreamSubscription<QuerySnapshot>? _ordersStream;
  StreamSubscription<QuerySnapshot>? _quotationsStream;

  bool _isLoading = false;
  final Set<String> _ongoingOperations = {};

  Stream<List<SalesOrder>> get ordersStream => _ordersSubject.stream;
  Stream<List<Quotation>> get quotationsStream => _quotationsSubject.stream;
  bool get isLoading => _isLoading;
  List<SalesOrder> get orders => _ordersSubject.value;
  List<Quotation> get quotations => _quotationsSubject.value;

  SalesDataProvider() {
    _initializeStreams();
  }

  void _initializeStreams() {
    _isLoading = true;
    notifyListeners();

    // Sales orders stream
    _ordersStream = _firestore
        .collection('sales')
        .doc('orders')
        .collection('customers')
        .orderBy('date', descending: true)
        .snapshots()
        .listen((snapshot) async {
      try {
        final orders = await Future.wait(snapshot.docs.map((doc) async {
          final data = doc.data();

          // Load order items from subcollection
          List<OrderItem> items = [];
          try {
            final itemsSnapshot = await doc.reference.collection('items').get();
            items = itemsSnapshot.docs.map((itemDoc) {
              final itemData = itemDoc.data();
              return OrderItem(
                product: itemData['product'] ?? '',
                quantity: (itemData['quantity'] ?? 0).toInt(),
                price: (itemData['price'] ?? 0.0).toDouble(),
                total: (itemData['total'] ?? 0.0).toDouble(),
              );
            }).toList();
          } catch (e) {
            print('Error loading items for order ${doc.id}: $e');
          }

          return SalesOrder(
            id: doc.id,
            customer: data['customer'] ?? '',
            date: data['date']?.toDate() ?? DateTime.now(),
            status: data['status'] ?? 'Pending',
            total: (data['total'] ?? 0.0).toDouble(),
            items: items,
            customerId: data['customerId'] ?? '',
            reference: data['reference'] ?? '',
            notes: data['notes'] ?? '',
            createdAt: data['createdAt']?.toDate(),
            updatedAt: data['updatedAt']?.toDate(),
            invoiceCreated: data['invoiceCreated'] ?? false,
            invoiceId: data['invoiceId'] ?? '',
            stockDeducted: data['stockDeducted'] ?? false,
          );
        }));

        _ordersSubject.add(orders);
      } catch (e) {
        print('Error processing orders stream: $e');
      } finally {
        _isLoading = false;
        notifyListeners();
      }
    }, onError: (error) {
      print('Orders stream error: $error');
      _isLoading = false;
      notifyListeners();
    });

    // Quotations stream
    _quotationsStream = _firestore
        .collection('sales')
        .doc('quotations')
        .collection('customers')
        .orderBy('date', descending: true)
        .snapshots()
        .listen((snapshot) {
      try {
        final quotations = snapshot.docs.map((doc) {
          final data = doc.data();
          return Quotation(
            id: doc.id,
            customer: data['customer'] ?? '',
            date: data['date']?.toDate() ?? DateTime.now(),
            expiryDate: data['expiryDate']?.toDate() ?? DateTime.now(),
            status: data['status'] ?? 'Pending',
            total: (data['total'] ?? 0.0).toDouble(),
            customerId: data['customerId'] ?? '',
            reference: data['reference'] ?? '',
            notes: data['notes'] ?? '',
            items: List<OrderItem>.from((data['items'] ?? []).map((item) => OrderItem(
              product: item['product'] ?? '',
              quantity: (item['quantity'] ?? 0).toInt(),
              price: (item['price'] ?? 0.0).toDouble(),
              total: (item['total'] ?? 0.0).toDouble(),
            ))),
            createdAt: data['createdAt']?.toDate(),
          );
        }).toList();

        _quotationsSubject.add(quotations);
      } catch (e) {
        print('Error processing quotations stream: $e');
      }
    }, onError: (error) {
      print('Quotations stream error: $error');
    });
  }

  Future<void> createSalesOrder(SalesOrder order) async {
    final operationId = 'create_order_${DateTime.now().millisecondsSinceEpoch}';
    if (_ongoingOperations.contains(operationId)) return;
    _ongoingOperations.add(operationId);

    try {
      String orderNumber = order.reference;
      if (orderNumber.isEmpty) {
        final ordersSnapshot = await _firestore
            .collection('sales')
            .doc('orders')
            .collection('customers')
            .limit(1)
            .get();

        int highestNumber = 0;
        for (final doc in ordersSnapshot.docs) {
          final data = doc.data();
          final reference = data['reference'] ?? '';
          if (reference.startsWith('SO-')) {
            final numberStr = reference.split('-').last;
            final number = int.tryParse(numberStr) ?? 0;
            if (number > highestNumber) {
              highestNumber = number;
            }
          }
        }
        orderNumber = 'SO-${(highestNumber + 1).toString().padLeft(4, '0')}';
      }

      final docRef = await _firestore
          .collection('sales')
          .doc('orders')
          .collection('customers')
          .add({
        'customer': order.customer,
        'customerId': order.customerId,
        'date': Timestamp.fromDate(order.date),
        'status': order.status,
        'total': order.total,
        'reference': orderNumber,
        'notes': order.notes,
        'invoiceCreated': false,
        'invoiceId': '',
        'stockDeducted': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      for (final item in order.items) {
        await docRef.collection('items').add({
          'product': item.product,
          'quantity': item.quantity,
          'price': item.price,
          'total': item.total,
        });
      }

    } catch (e) {
      print('Error creating sales order: $e');
      rethrow;
    } finally {
      _ongoingOperations.remove(operationId);
    }
  }

  Future<void> updateOrderStatus(String orderId, String status) async {
    final operationId = 'update_status_${orderId}_${DateTime.now().millisecondsSinceEpoch}';
    if (_ongoingOperations.contains(operationId)) return;
    _ongoingOperations.add(operationId);

    try {
      await _firestore
          .collection('sales')
          .doc('orders')
          .collection('customers')
          .doc(orderId)
          .update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error updating order status: $e');
      rethrow;
    } finally {
      _ongoingOperations.remove(operationId);
    }
  }

  Future<void> createQuotation(Quotation quotation) async {
    final operationId = 'create_quotation_${DateTime.now().millisecondsSinceEpoch}';
    if (_ongoingOperations.contains(operationId)) return;
    _ongoingOperations.add(operationId);

    try {
      String quoteNumber = quotation.reference;
      if (quoteNumber.isEmpty) {
        final quotesSnapshot = await _firestore
            .collection('sales')
            .doc('quotations')
            .collection('customers')
            .limit(1)
            .get();

        int highestNumber = 0;
        for (final doc in quotesSnapshot.docs) {
          final data = doc.data();
          final reference = data['reference'] ?? '';
          if (reference.startsWith('QT-')) {
            final numberStr = reference.split('-').last;
            final number = int.tryParse(numberStr) ?? 0;
            if (number > highestNumber) {
              highestNumber = number;
            }
          }
        }
        quoteNumber = 'QT-${(highestNumber + 1).toString().padLeft(4, '0')}';
      }

      await _firestore
          .collection('sales')
          .doc('quotations')
          .collection('customers')
          .add({
        'customer': quotation.customer,
        'customerId': quotation.customerId,
        'date': Timestamp.fromDate(quotation.date),
        'expiryDate': Timestamp.fromDate(quotation.expiryDate),
        'status': quotation.status,
        'total': quotation.total,
        'reference': quoteNumber,
        'notes': quotation.notes,
        'items': quotation.items.map((item) => ({
          'product': item.product,
          'quantity': item.quantity,
          'price': item.price,
          'total': item.total,
        })).toList(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error creating quotation: $e');
      rethrow;
    } finally {
      _ongoingOperations.remove(operationId);
    }
  }

  Future<void> deleteSalesOrder(String orderId) async {
    final operationId = 'delete_order_${orderId}_${DateTime.now().millisecondsSinceEpoch}';
    if (_ongoingOperations.contains(operationId)) return;
    _ongoingOperations.add(operationId);

    try {
      // Delete order items first
      final itemsSnapshot = await _firestore
          .collection('sales')
          .doc('orders')
          .collection('customers')
          .doc(orderId)
          .collection('items')
          .get();

      for (final itemDoc in itemsSnapshot.docs) {
        await itemDoc.reference.delete();
      }

      // Delete the order
      await _firestore
          .collection('sales')
          .doc('orders')
          .collection('customers')
          .doc(orderId)
          .delete();

    } catch (e) {
      print('Error deleting order: $e');
      rethrow;
    } finally {
      _ongoingOperations.remove(operationId);
    }
  }

  Future<void> deleteQuotation(String quotationId) async {
    final operationId = 'delete_quotation_${quotationId}_${DateTime.now().millisecondsSinceEpoch}';
    if (_ongoingOperations.contains(operationId)) return;
    _ongoingOperations.add(operationId);

    try {
      await _firestore
          .collection('sales')
          .doc('quotations')
          .collection('customers')
          .doc(quotationId)
          .delete();
    } catch (e) {
      print('Error deleting quotation: $e');
      rethrow;
    } finally {
      _ongoingOperations.remove(operationId);
    }
  }

  @override
  void dispose() {
    _ordersStream?.cancel();
    _quotationsStream?.cancel();
    _ordersSubject.close();
    _quotationsSubject.close();
    super.dispose();
  }
}