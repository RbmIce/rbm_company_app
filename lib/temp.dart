import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/shared_data_service.dart';
import 'models/sales_model.dart';

class SalesModule extends StatefulWidget {
  const SalesModule({super.key});

  @override
  State<SalesModule> createState() => _SalesModuleState();
}

class _SalesModuleState extends State<SalesModule> {
  int _currentTabIndex = 0;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<SalesOrder> _salesOrders = [];
  List<Quotation> _quotations = [];
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isCreatingOrder = false;
  bool _isCreatingCustomer = false;
  bool _isCreatingQuotation = false;
  bool _isConvertingQuotation = false;
  bool _isUpdatingStatus = false;
  bool _isCreatingInvoice = false;

  String? _currentlyUpdatingOrderId;
  String? _currentlyCreatingInvoiceOrderId;


  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    final sharedData = Provider.of<SharedDataService>(context, listen: false);

    if (sharedData.customers.isEmpty || sharedData.products.isEmpty) {
      await sharedData.loadSharedData();
    }

    await _loadSalesData();
  }
  Future<void> _debugFirestoreStructure() async {
    try {
      print('=== DEBUG: Checking Firestore Structure ===');

      // Check sales/orders structure
      final salesOrders = await _firestore.collection('sales').doc('orders').collection('customers').get();
      print('Sales orders found: ${salesOrders.docs.length}');
      for (final doc in salesOrders.docs) {
        print('Order: ${doc.id} - ${doc.data()['reference']} - Customer: ${doc.data()['customer']}');
      }

      // Check if there are any orders in other paths
      final allSales = await _firestore.collection('sales').get();
      print('Total sales collections: ${allSales.docs.length}');

    } catch (e) {
      print('Debug error: $e');
    }
  }

  Future<void> _loadSalesData() async {
    setState(() {
      _isLoading = true;
    });
    await _debugFirestoreStructure();

    try {
      // FIXED: Load sales orders from the correct path structure
      final ordersSnapshot = await _firestore
          .collection('sales')
          .doc('orders')
          .collection('customers')
          .limit(100)
          .get();

      _salesOrders = await Future.wait(ordersSnapshot.docs.map((doc) async {
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
        );
      }).toList());

      // Sort locally
      _salesOrders.sort((a, b) => b.date.compareTo(a.date));

      // FIXED: Load quotations from the correct path structure
      final quotationsSnapshot = await _firestore
          .collection('sales')
          .doc('quotations')
          .collection('customers')
          .limit(100)
          .get();

      _quotations = quotationsSnapshot.docs.map((doc) {
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

      // Sort quotations locally
      _quotations.sort((a, b) => b.date.compareTo(a.date));

    } catch (e) {
      print('Error loading sales data: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error loading sales data')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _createSalesOrder(SalesOrder order) async {
    setState(() {
      _isCreatingOrder = true;
    });

    try {
      final sharedData = Provider.of<SharedDataService>(context, listen: false);

      // Validate products exist
      for (final item in order.items) {
        final product = _getProductByName(sharedData, item.product);
        if (product == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Product ${item.product} not found')),
          );
          setState(() {
            _isCreatingOrder = false;
          });
          return;
        }
      }

      // Generate order number
      String orderNumber = order.reference;
      if (orderNumber.isEmpty) {
        // Get existing orders to find highest number
        final ordersSnapshot = await _firestore
            .collection('sales')
            .doc('orders')
            .collection('customers')
            .limit(100)
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

      // FIXED: Consistent path structure
      final ordersRef = _firestore
          .collection('sales')
          .doc('orders')
          .collection('customers');

      // Create sales order
      final docRef = await ordersRef.add({
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

      // Add order items to subcollection
      for (final item in order.items) {
        await docRef.collection('items').add({
          'product': item.product,
          'quantity': item.quantity,
          'price': item.price,
          'total': item.total,
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sales order created successfully'),
            backgroundColor: Colors.green),
      );

      await _loadSalesData();
    } catch (e) {
      print('Error creating sales order: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error creating sales order')),
      );
    } finally {
      setState(() {
        _isCreatingOrder = false;
      });
    }
  }


  Future<void> _createInvoiceForOrder(SalesOrder order) async {
    if (_isCreatingInvoice) return;
    _showCreateInvoiceDialog(order);
  }

  void _showCreateInvoiceDialog(SalesOrder order) {
    final taxController = TextEditingController(text: (order.total * 0.1).toStringAsFixed(0));
    final discountController = TextEditingController(text: '0');
    final feesController = TextEditingController(text: '0');
    final notesController = TextEditingController(text: 'Invoice for order ${order.reference}');

    DateTime dueDate = DateTime.now().add(const Duration(days: 30));
    final dueDateController = TextEditingController(
        text: DateFormat('yyyy-MM-dd').format(dueDate)
    );

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Create Invoice'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildInvoiceInfoRow('Order:', order.reference),
                  _buildInvoiceInfoRow('Customer:', order.customer),
                  _buildInvoiceInfoRow('Amount:', '${order.total.toStringAsFixed(0)} FCFA'),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),

                  TextField(
                    controller: taxController,
                    decoration: const InputDecoration(labelText: 'Tax (FCFA)'),
                    keyboardType: TextInputType.number,
                  ),
                  TextField(
                    controller: discountController,
                    decoration: const InputDecoration(labelText: 'Discount (FCFA)'),
                    keyboardType: TextInputType.number,
                  ),
                  TextField(
                    controller: feesController,
                    decoration: const InputDecoration(labelText: 'Fees (FCFA)'),
                    keyboardType: TextInputType.number,
                  ),
                  TextField(
                    controller: dueDateController,
                    decoration: const InputDecoration(labelText: 'Due Date'),
                    readOnly: true,
                    onTap: () async {
                      final DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: dueDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null && picked != dueDate) {
                        setState(() {
                          dueDate = picked;
                          dueDateController.text = DateFormat('yyyy-MM-dd').format(picked);
                        });
                      }
                    },
                  ),
                  TextField(
                    controller: notesController,
                    decoration: const InputDecoration(labelText: 'Notes'),
                    maxLines: 3,
                  ),

                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),

                  _buildInvoiceSummary(
                    order.total,
                    double.tryParse(taxController.text) ?? 0,
                    double.tryParse(discountController.text) ?? 0,
                    double.tryParse(feesController.text) ?? 0,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              if (_isCreatingInvoice)
                const CircularProgressIndicator()
              else
                ElevatedButton(
                  onPressed: () async {
                    await _processInvoiceCreation(
                      order,
                      taxController.text,
                      discountController.text,
                      feesController.text,
                      dueDate,
                      notesController.text,
                    );
                    Navigator.pop(context);
                  },
                  child: const Text('Create Invoice'),
                ),
            ],
          );
        },
      ),
    );
  }
  Future<void> _processInvoiceCreation(
      SalesOrder order,
      String taxText,
      String discountText,
      String feesText,
      DateTime dueDate,
      String notes,
      ) async {
    // FIX: Track specific order for invoice creation
    setState(() {
      _isCreatingInvoice = true;
      _currentlyCreatingInvoiceOrderId = order.id;
    });

    try {
      // Check if invoice already exists for this order
      if (order.invoiceCreated) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invoice already exists for this order')),
        );
        return;
      }

      // Generate invoice number - search all customer invoice collections
      final invoicesSnapshot = await _firestore
          .collectionGroup('customer_invoices')
          .orderBy('number', descending: true)
          .limit(1)
          .get();

      int highestNumber = 0;
      for (final doc in invoicesSnapshot.docs) {
        final data = doc.data();
        final number = data['number'] ?? '';
        if (number.startsWith('INV-')) {
          final numberStr = number.split('-').last;
          final num = int.tryParse(numberStr) ?? 0;
          if (num > highestNumber) {
            highestNumber = num;
          }
        }
      }

      String invoiceNumber = 'INV-${(highestNumber + 1).toString().padLeft(4, '0')}';

      // Parse user inputs
      final tax = double.tryParse(taxText) ?? 0;
      final discount = double.tryParse(discountText) ?? 0;
      final fees = double.tryParse(feesText) ?? 0;
      final total = order.total + tax + fees - discount;

      // Convert order items to invoice items
      final invoiceItems = order.items.map((item) => {
        'description': item.product,
        'quantity': item.quantity,
        'unitPrice': item.price,
        'total': item.total,
      }).toList();

      // Get customer details for invoice
      final customer = await _getCustomerById(order.customerId);

      // MODIFIED: Store invoice in the same path as Invoices Module
      // invoices/customerId/customer_invoices
      final customerInvoicesRef = _firestore
          .collection('invoices')
          .doc(order.customerId)
          .collection('customer_invoices');

      // Create invoice data
      final invoiceData = {
        'number': invoiceNumber,
        'customer': order.customer,
        'customerId': order.customerId,
        'customerEmail': customer?.email ?? '',
        'customerPhone': customer?.phone ?? '',
        'customerAddress': customer?.address ?? '',
        'date': Timestamp.fromDate(DateTime.now()),
        'dueDate': Timestamp.fromDate(dueDate),
        'subtotal': order.total,
        'tax': tax,
        'discount': discount,
        'fees': fees,
        'total': total,
        'status': 'Pending',
        'items': invoiceItems,
        'payments': [],
        'notes': notes.isNotEmpty ? notes : 'Invoice for order ${order.reference}',
        'terms': 'Net 30 days',
        'taxId': 'TAX-${order.customerId}',
        'orderReference': order.reference,
        'orderId': order.id,
        'orderStatus': order.status,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Create invoice
      final invoiceDocRef = await customerInvoicesRef.add(invoiceData);

      // Update the order to mark that invoice has been created
      final orderDocRef = _firestore
          .collection('sales')
          .doc('orders')
          .collection('customers')
          .doc(order.id);

      await orderDocRef.update({
        'invoiceCreated': true,
        'invoiceId': invoiceDocRef.id,
        'invoiceNumber': invoiceNumber,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invoice $invoiceNumber created successfully'),
            backgroundColor: Colors.green),
      );

      await _loadSalesData();
    } catch (e) {
      print('Error creating invoice: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error creating invoice')),
      );
    } finally {
      // FIX: Reset the specific order tracking
      setState(() {
        _isCreatingInvoice = false;
        _currentlyCreatingInvoiceOrderId = null;
      });
    }
  }

  Widget _buildInvoiceInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceSummary(double subtotal, double tax, double discount, double fees) {
    final total = subtotal + tax + fees - discount;

    return Column(
      children: [
        _buildSummaryRow('Subtotal', subtotal),
        _buildSummaryRow('Tax', tax),
        _buildSummaryRow('Fees', fees),
        _buildSummaryRow('Discount', -discount, isDiscount: true),
        const Divider(),
        _buildSummaryRow('TOTAL', total, isTotal: true),
      ],
    );
  }

  Widget _buildSummaryRow(String label, double amount, {bool isDiscount = false, bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isDiscount ? Colors.red : Colors.black,
            ),
          ),
          Text(
            '${amount.toStringAsFixed(0)} FCFA',
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isDiscount ? Colors.red : (isTotal ? Colors.green : Colors.black),
            ),
          ),
        ],
      ),
    );
  }

  Future<Customer?> _getCustomerById(String customerId) async {
    try {
      // First try to get customer by customerId field
      final customerSnapshot = await _firestore
          .collection('customers')
          .where('customerId', isEqualTo: customerId)
          .limit(1)
          .get();

      if (customerSnapshot.docs.isNotEmpty) {
        final data = customerSnapshot.docs.first.data();
        return Customer(
          id: customerSnapshot.docs.first.id,
          customerId: data['customerId'] ?? '',
          name: data['name'] ?? '',
          email: data['email'] ?? '',
          phone: data['phone'] ?? '',
          address: data['address'] ?? '',
          type: data['type'] ?? 'Regular',
          status: data['status'] ?? 'Active',
        );
      }

      // If not found by customerId, try by document ID
      final customerDoc = await _firestore
          .collection('customers')
          .doc(customerId)
          .get();

      if (customerDoc.exists) {
        final data = customerDoc.data()!;
        return Customer(
          id: customerDoc.id,
          customerId: data['customerId'] ?? customerDoc.id,
          name: data['name'] ?? '',
          email: data['email'] ?? '',
          phone: data['phone'] ?? '',
          address: data['address'] ?? '',
          type: data['type'] ?? 'Regular',
          status: data['status'] ?? 'Active',
        );
      }
    } catch (e) {
      print('Error loading customer: $e');
    }
    return null;
  }
  Future<void> _updateOrderStatus(String orderId, String status) async {
    // FIX: Set the specific order ID that's being updated
    setState(() {
      _isUpdatingStatus = true;
      _currentlyUpdatingOrderId = orderId;
    });

    try {
      // Find the order to get customerId for path
      final order = _salesOrders.firstWhere((o) => o.id == orderId);

      // NEW: Deduct stock only when order is delivered
      if (status == 'Delivered') {
        await _deductStockForOrder(order);
      }

      // CORRECTED: Use the actual path structure from your Firestore
      await _firestore
          .collection('sales')
          .doc('orders')
          .collection('customers')  // Fixed: Use 'customers' collection, not customerId
          .doc(orderId)             // Use the order document ID directly
          .update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Order status updated to $status')),
      );

      await _loadSalesData();
    } catch (e) {
      print('Error updating order status: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error updating order status')),
      );
    } finally {
      // FIX: Reset the specific order tracking
      setState(() {
        _isUpdatingStatus = false;
        _currentlyUpdatingOrderId = null;
      });
    }
  }
  Future<void> _deductStockForOrder(SalesOrder order) async {
    try {
      final sharedData = Provider.of<SharedDataService>(context, listen: false);

      // Check if stock has already been deducted for this order
      final orderDoc = await _firestore
          .collection('sales')
          .doc('orders')
          .collection('customers')  // Fixed: Use 'customers' collection
          .doc(order.id)            // Use order document ID directly
          .get();

      if (orderDoc.exists && orderDoc.data()?['stockDeducted'] == true) {
        print('Stock already deducted for order ${order.reference}');
        return;
      }

      // Validate stock availability before delivery
      for (final item in order.items) {
        final product = _getProductByName(sharedData, item.product);
        if (product != null && item.quantity > product.stock) {
          throw Exception('Insufficient stock for ${item.product}. Available: ${product.stock}, Requested: ${item.quantity}');
        }
      }

      // Deduct stock for each product
      for (final item in order.items) {
        final product = _getProductByName(sharedData, item.product);
        if (product != null && product.id.isNotEmpty) {
          // Update shared data
          sharedData.updateProductStock(product.id, -item.quantity);

          // Update Firestore
          await _firestore
              .collection('inventory')
              .doc('products')
              .collection('items')
              .doc(product.id)
              .update({
            'stock': FieldValue.increment(-item.quantity),
            'lastUpdated': FieldValue.serverTimestamp(),
          });
        }
      }

      // Mark that stock has been deducted for this order
      await _firestore
          .collection('sales')
          .doc('orders')
          .collection('customers')  // Fixed: Use 'customers' collection
          .doc(order.id)            // Use order document ID directly
          .update({
        'stockDeducted': true,
      });

      print('Stock deducted successfully for order ${order.reference}');
    } catch (e) {
      print('Error deducting stock for order: $e');
      rethrow; // Re-throw to be handled by the calling function
    }
  }

  Future<void> _createQuotation(Quotation quotation) async {
    setState(() {
      _isCreatingQuotation = true;
    });

    try {
      String quoteNumber = quotation.reference;
      if (quoteNumber.isEmpty) {
        final quotesSnapshot = await _firestore
            .collection('sales')
            .doc('quotations')
            .collection('customers')
            .limit(100)
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

      // FIXED: Consistent path structure
      final quotationsRef = _firestore
          .collection('sales')
          .doc('quotations')
          .collection('customers');

      await quotationsRef.add({
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

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quotation created successfully'),
            backgroundColor: Colors.green),
      );

      await _loadSalesData();
    } catch (e) {
      print('Error creating quotation: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error creating quotation')),
      );
    } finally {
      setState(() {
        _isCreatingQuotation = false;
      });
    }
  }

  Future<void> _convertQuotationToOrder(String quotationId) async {
    setState(() {
      _isConvertingQuotation = true;
    });

    try {
      // Find the quotation to get its path
      final quotation = _quotations.firstWhere((q) => q.id == quotationId);

      final quoteDoc = await _firestore
          .collection('sales')
          .doc('quotations')
          .collection(quotation.customerId)
          .doc(quotationId)
          .get();

      // final orderDoc = await _firestore
      //     .collection('sales')
      //     .doc('orders')
      //     .collection(order.customerId)
      //     .doc('sales_orders')
      //     .collection('orders')
      //     .doc(order.id)
      //     .get();

      if (quoteDoc.exists) {
        final quoteData = quoteDoc.data();
        final items = List<OrderItem>.from((quoteData?['items'] ?? []).map((item) => OrderItem(
          product: item['product'] ?? '',
          quantity: (item['quantity'] ?? 0).toInt(),
          price: (item['price'] ?? 0.0).toDouble(),
          total: (item['total'] ?? 0.0).toDouble(),
        )));

        final salesOrder = SalesOrder(
          id: '',
          customer: quoteData?['customer'] ?? '',
          date: DateTime.now(),
          status: 'Pending',
          total: (quoteData?['total'] ?? 0.0).toDouble(),
          items: items,
          customerId: quoteData?['customerId'] ?? '',
          reference: '',
          notes: 'Converted from quotation: ${quoteData?['reference']}',
        );

        await _createSalesOrder(salesOrder);

        // Update quotation status
        await _firestore
            .collection('sales')
            .doc('quotations')
            .collection(quotation.customerId)
            .doc(quotationId)
            .update({
          'status': 'Converted',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print('Error converting quotation: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error converting quotation')),
      );
    } finally {
      setState(() {
        _isConvertingQuotation = false;
      });
    }
  }

  Future<void> _deleteSalesOrder(String orderId) async {
    final confirmed = await _showConfirmationDialog(
        'Delete Order',
        'Are you sure you want to delete this order? This action cannot be undone.'
    );

    if (!confirmed) return;

    setState(() {
      _isSaving = true;
    });

    try {
      // Find the order to get customerId for path
      final order = _salesOrders.firstWhere((o) => o.id == orderId);

      // Delete order items first
      final itemsSnapshot = await _firestore
          .collection('sales')
          .doc('orders')
          .collection('customers')  // FIXED: Consistent path
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
          .collection('customers')  // FIXED: Consistent path
          .doc(orderId)
          .delete();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order deleted successfully'),
            backgroundColor: Colors.green),
      );

      await _loadSalesData();
    } catch (e) {
      print('Error deleting order: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error deleting order')),
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<void> _deleteQuotation(String quotationId) async {
    final confirmed = await _showConfirmationDialog(
        'Delete Quotation',
        'Are you sure you want to delete this quotation? This action cannot be undone.'
    );

    if (!confirmed) return;

    setState(() {
      _isSaving = true;
    });

    try {
      await _firestore
          .collection('sales')
          .doc('quotations')
          .collection('quotes')
          .doc(quotationId)
          .delete();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quotation deleted successfully'),
            backgroundColor: Colors.green),
      );

      await _loadSalesData();
    } catch (e) {
      print('Error deleting quotation: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error deleting quotation')),
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<void> _deleteCustomer(String customerId, SharedDataService sharedData) async {
    final confirmed = await _showConfirmationDialog(
        'Delete Distributor',
        'Are you sure you want to delete this distributor? This action cannot be undone.'
    );

    if (!confirmed) return;

    setState(() {
      _isSaving = true;
    });

    try {
      await _firestore
          .collection('customers')
          .doc(customerId)
          .delete();

      // Remove from shared data
      sharedData.removeCustomer(customerId);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Distributor deleted successfully'),
            backgroundColor: Colors.green),
      );

      await _loadSalesData();
    } catch (e) {
      print('Error deleting distributor: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error deleting distributor')),
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<bool> _showConfirmationDialog(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final sharedData = Provider.of<SharedDataService>(context);

    if (_isLoading || sharedData.isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading sales data...'),
            ],
          ),
        ),
      );
    }

    final totalSales = _salesOrders.fold(0.0, (sum, order) => sum + order.total);
    final pendingOrders = _salesOrders.where((order) => order.status == 'Pending').length;
    final deliveredOrders = _salesOrders.where((order) => order.status == 'Delivered').length;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Sales Module'),
        backgroundColor: Colors.blue[800],
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSalesData,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSalesOverview(totalSales, pendingOrders, deliveredOrders, sharedData.customers.length),
          const SizedBox(height: 16),
          _buildTabBar(),
          Expanded(
            child: _isSaving
                ? const Center(child: CircularProgressIndicator())
                : _buildCurrentTab(sharedData),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddMenu(context, sharedData),
        backgroundColor: Colors.blue[800],
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _showAddMenu(BuildContext context, SharedDataService sharedData) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.shopping_cart),
            title: const Text('Create Sales Order'),
            onTap: () {
              Navigator.pop(context);
              _showCreateOrderDialog(sharedData);
            },
          ),
          ListTile(
            leading: const Icon(Icons.person_add),
            title: const Text('Add Distributor'),
            onTap: () {
              Navigator.pop(context);
              _showAddCustomerDialog(sharedData);
            },
          ),
          ListTile(
            leading: const Icon(Icons.description),
            title: const Text('Create Quotation'),
            onTap: () {
              Navigator.pop(context);
              _showCreateQuotationDialog(sharedData);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSalesOverview(double totalSales, int pendingOrders, int deliveredOrders, int totalCustomers) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildSalesMetric('Pending Orders', pendingOrders.toDouble(), Icons.pending_actions, Colors.orange),
          _buildSalesMetric('Delivered', deliveredOrders.toDouble(), Icons.local_shipping, Colors.blue),
          _buildSalesMetric('Distributors', totalCustomers.toDouble(), Icons.people, Colors.purple),
        ],
      ),
    );
  }

  Widget _buildSalesMetric(String label, double value, IconData icon, Color color, {bool isCurrency = false}) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 8),
        Text(
          isCurrency ? '${value.toStringAsFixed(0)} FCFA' : value.toInt().toString(),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      child: Row(
        children: [
          _buildTabButton('Orders', 0),
          _buildTabButton('Quotations', 1),
          _buildTabButton('Distributors', 2),
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
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildCurrentTab(SharedDataService sharedData) {
    switch (_currentTabIndex) {
      case 0:
        return _buildOrdersTab();
      case 1:
        return  _buildQuotationsTab();
      case 2:
        return _buildCustomersTab(sharedData);
      default:
        return _buildOrdersTab();
    }
  }

  Widget _buildOrdersTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Sales Orders',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        ..._salesOrders.map((order) => _buildOrderCard(order)),
      ],
    );
  }

  Widget _buildOrderCard(SalesOrder order) {
    Color statusColor;
    IconData statusIcon;

    switch (order.status) {
      case 'Delivered':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'Processing':
        statusColor = Colors.blue;
        statusIcon = Icons.autorenew;
        break;
      case 'Pending':
        statusColor = Colors.orange;
        statusIcon = Icons.pending;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help;
    }

    final isCreatingInvoice = _isCreatingInvoice;
    // FIX: Track loading state per order
    final isThisOrderUpdating = _isUpdatingStatus && _currentlyUpdatingOrderId == order.id;

    return GestureDetector(
      onLongPress: () => _deleteSalesOrder(order.id),
      child: Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with Reference and Status
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    order.reference.isNotEmpty ? order.reference : 'SO-${order.id.substring(0, 8)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(statusIcon, size: 14, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          order.status,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Customer Name
              const SizedBox(height: 8),
              Text(
                'Customer: ${order.customer}',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),

              // Order Items with Quantities and Prices
              const SizedBox(height: 12),
              if (order.items.isNotEmpty) ...[
                const Text(
                  'Products Ordered:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                ...order.items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '• ${item.product}',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      Text(
                        '${item.quantity} × ${item.price.toStringAsFixed(0)} FCFA',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${item.total.toStringAsFixed(0)} FCFA',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                )),
                const Divider(),
              ] else ...[
                const Text(
                  'No items in this order',
                  style: TextStyle(
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const Divider(),
              ],

              // Total Price
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total Amount:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    '${order.total.toStringAsFixed(0)} FCFA',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),

              // Invoice Status
              if (order.invoiceCreated)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.receipt, size: 14, color: Colors.green[700]),
                      const SizedBox(width: 4),
                      Text(
                        'Invoice Created',
                        style: TextStyle(
                          color: Colors.green[700],
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 12),

              // Footer with Date and Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    DateFormat('MMM d, y').format(order.date),
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 12,
                    ),
                  ),
                  Row(
                    children: [
                      // View Details Button
                      IconButton(
                        icon: const Icon(Icons.visibility, size: 18),
                        onPressed: () => _viewOrderDetails(order),
                        tooltip: 'View Order Details',
                      ),

                      // Invoice Creation Button
                      // Invoice Creation Button
                      if (!order.invoiceCreated)
                        (_isCreatingInvoice && _currentlyCreatingInvoiceOrderId == order.id)
                            ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                            : IconButton(
                          icon: const Icon(Icons.receipt, size: 18, color: Colors.green),
                          onPressed: () => _createInvoiceForOrder(order),
                          tooltip: 'Create Invoice',
                        ),

                      // Status Update Buttons - FIXED: Only show loading for this specific order
                      if (order.status == 'Pending' && !isThisOrderUpdating)
                        IconButton(
                          icon: const Icon(Icons.check, size: 18),
                          onPressed: () => _updateOrderStatus(order.id, 'Processing'),
                          tooltip: 'Process Order',
                        ),
                      if (order.status == 'Processing' && !isThisOrderUpdating)
                        IconButton(
                          icon: const Icon(Icons.local_shipping, size: 18),
                          onPressed: () => _updateOrderStatus(order.id, 'Delivered'),
                          tooltip: 'Mark as Delivered',
                        ),
                      if (isThisOrderUpdating)
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomersTab(SharedDataService sharedData) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Distributors',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        ...sharedData.customers.map((customer) => _buildCustomerCard(customer, sharedData)),
      ],
    );
  }

  Widget _buildCustomerCard(Customer customer, SharedDataService sharedData) {
    return GestureDetector(
      onLongPress: () => _deleteCustomer(customer.id, sharedData),
      child: Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.blue[100],
            child: Text(
              customer.name[0],
              style: const TextStyle(color: Colors.blue),
            ),
          ),
          title: Text(
            customer.name,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ID: ${customer.customerId}'),
              Text(customer.email),
              Text(customer.phone),
            ],
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _getCustomerStatusColor(customer.status).withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              customer.status,
              style: TextStyle(
                color: _getCustomerStatusColor(customer.status),
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          onTap: () => _viewCustomerDetails(customer),
        ),
      ),
    );
  }

  Color _getCustomerStatusColor(String status) {
    return status == 'Active' ? Colors.green : Colors.grey;
  }

  Widget _buildCustomerMetric(String label, dynamic value, {bool isCurrency = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isCurrency ? '${(value as double).toStringAsFixed(0)} FCFA' : value.toString(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.blue[800],
        ),
      ),
    );
  }

  Widget _buildQuotationsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Quotations',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        ..._quotations.map((quotation) => _buildQuotationCard(quotation)),
      ],
    );
  }

  Widget _buildQuotationCard(Quotation quotation) {
    Color statusColor;
    IconData statusIcon;

    switch (quotation.status) {
      case 'Accepted':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'Pending':
        statusColor = Colors.orange;
        statusIcon = Icons.pending;
        break;
      case 'Expired':
        statusColor = Colors.red;
        statusIcon = Icons.timer_off;
        break;
      case 'Converted':
        statusColor = Colors.blue;
        statusIcon = Icons.shopping_cart;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help;
    }

    final isExpired = quotation.expiryDate.isBefore(DateTime.now());

    return GestureDetector(
      onLongPress: () => _deleteQuotation(quotation.id),
      child: Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(statusIcon, color: statusColor),
          ),
          title: Text(
            quotation.reference.isNotEmpty ? quotation.reference : 'QT-${quotation.id.substring(0, 8)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(quotation.customer),
              Text(
                'Valid until: ${DateFormat('MMM d, y').format(quotation.expiryDate)}',
                style: TextStyle(
                  color: isExpired ? Colors.red : Colors.grey[600],
                  fontWeight: isExpired ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${quotation.total.toStringAsFixed(0)} FCFA',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Text(
                quotation.status,
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          onTap: () => _showQuotationActions(quotation),
        ),
      ),
    );
  }
  void _viewCustomerDetails(Customer customer) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(customer.name),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Customer ID: ${customer.customerId}'),
              Text('Email: ${customer.email}'),
              Text('Phone: ${customer.phone}'),
              Text('Address: ${customer.address}'),
              Text('Type: ${customer.type}'),
              Text('Status: ${customer.status}'),
            ],
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

  void _showInsufficientStockDialog(Product product, int requestedQuantity) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Insufficient Stock'),
        content: Text(
          'Cannot sell $requestedQuantity ${product.unit} of ${product.name}. '
              'Only ${product.stock} ${product.unit} available in stock.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Product? _getProductByName(SharedDataService sharedData, String productName) {
    try {
      return sharedData.products.firstWhere(
            (product) => product.name == productName,
      );
    } catch (e) {
      return null;
    }
  }

  Widget _buildStockValidationMessage(Product product, String quantityText) {
    final quantity = int.tryParse(quantityText) ?? 0;

    if (quantity > product.stock) {
      return Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: Text(
          '⚠️ Insufficient stock! Available: ${product.stock} ${product.unit}',
          style: const TextStyle(
            color: Colors.red,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    } else if (quantity == product.stock) {
      return Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: Text(
          '⚠️ This will deplete all stock',
          style: TextStyle(
            color: Colors.orange[700],
            fontSize: 12,
          ),
        ),
      );
    }
    return const SizedBox();
  }

  void _showCreateOrderDialog(SharedDataService sharedData) {
    Customer? selectedCustomer;
    final List<OrderItem> orderItems = [];
    final referenceController = TextEditingController();
    final notesController = TextEditingController();

    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Create Sales Order'),
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
                    const Text('Creating sales order...'),
                  ],
                ),
              ),
            )
                : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<Customer>(
                    value: selectedCustomer,
                    decoration: const InputDecoration(labelText: 'Distributor'),
                    items: sharedData.customers.map((Customer customer) {
                      return DropdownMenuItem<Customer>(
                        value: customer,
                        child: Text(customer.name),
                      );
                    }).toList(),
                    onChanged: (Customer? newValue) {
                      setState(() {
                        selectedCustomer = newValue;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text('Order Items:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...orderItems.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    return ListTile(
                      title: Text('${item.quantity}x ${item.product}'),
                      subtitle: Text('${item.total.toStringAsFixed(0)} FCFA'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, size: 18),
                        onPressed: () {
                          setState(() {
                            orderItems.removeAt(index);
                          });
                        },
                      ),
                    );
                  }),
                  ElevatedButton(
                    onPressed: () => _showAddOrderItemDialog(sharedData, orderItems, setState),
                    child: const Text('Add Item'),
                  ),
                  TextField(
                    controller: referenceController,
                    decoration: const InputDecoration(labelText: 'Reference Number'),
                  ),
                  TextField(
                    controller: notesController,
                    decoration: const InputDecoration(labelText: 'Notes'),
                    maxLines: 2,
                  ),
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
                onPressed: (selectedCustomer == null || orderItems.isEmpty) ? null : () async {
                  // Check stock availability for all items
                  bool hasInsufficientStock = false;
                  Product? firstOutOfStockProduct;
                  int firstRequestedQuantity = 0;

                  for (final item in orderItems) {
                    final product = _getProductByName(sharedData, item.product);
                    if (product != null && item.quantity > product.stock) {
                      hasInsufficientStock = true;
                      firstOutOfStockProduct = product;
                      firstRequestedQuantity = item.quantity;
                      break; // Stop at first insufficient stock item
                    }
                  }

                  if (hasInsufficientStock && firstOutOfStockProduct != null) {
                    // Show insufficient stock dialog for the first problematic item
                    _showInsufficientStockDialog(firstOutOfStockProduct, firstRequestedQuantity);
                    return;
                  }

                  setState(() {
                    isSubmitting = true;
                  });

                  final total = orderItems.fold(0.0, (sum, item) => sum + item.total);
                  final order = SalesOrder(
                    id: '',
                    customer: selectedCustomer!.name,
                    date: DateTime.now(),
                    status: 'Pending',
                    total: total,
                    items: orderItems,
                    customerId: selectedCustomer!.customerId,
                    reference: referenceController.text,
                    notes: notesController.text,
                  );

                  await _createSalesOrder(order);

                  if (mounted) {
                    Navigator.pop(context);
                  }
                },
                child: const Text('Create Order'),
              ),
            ],
          );
        },
      ),
    );
  }
  void _showAddOrderItemDialog(SharedDataService sharedData, List<OrderItem> orderItems, StateSetter setState) {
    Product? selectedProduct;
    final quantityController = TextEditingController(text: '1');
    final priceController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, dialogSetState) {
          return AlertDialog(
            title: const Text('Add Order Item'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<Product>(
                  value: selectedProduct,
                  decoration: const InputDecoration(labelText: 'Product'),
                  items: sharedData.products.map((Product product) {
                    return DropdownMenuItem<Product>(
                      value: product,
                      child: Text('${product.name} (Stock: ${product.stock} ${product.unit})'),
                    );
                  }).toList(),
                  onChanged: (Product? newValue) {
                    dialogSetState(() {
                      selectedProduct = newValue;
                      if (newValue != null) {
                        priceController.text = newValue.price.toStringAsFixed(2);
                        // Update validation when product changes
                        final quantity = int.tryParse(quantityController.text) ?? 1;
                        if (quantity > newValue.stock) {
                          quantityController.text = newValue.stock.toString();
                        }
                      }
                    });
                  },
                ),
                TextField(
                  controller: quantityController,
                  decoration: const InputDecoration(labelText: 'Quantity'),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    dialogSetState(() {}); // Rebuild to show validation message
                  },
                ),
                if (selectedProduct != null)
                  _buildStockValidationMessage(selectedProduct!, quantityController.text),
                TextField(
                  controller: priceController,
                  decoration: const InputDecoration(labelText: 'Unit Price'),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: selectedProduct == null ? null : () {
                  final quantity = int.tryParse(quantityController.text) ?? 1;

                  // Validate stock availability
                  if (quantity > selectedProduct!.stock) {
                    _showInsufficientStockDialog(selectedProduct!, quantity);
                    return;
                  }

                  final price = double.tryParse(priceController.text) ?? selectedProduct!.price;
                  final total = quantity * price;

                  orderItems.add(OrderItem(
                    product: selectedProduct!.name,
                    quantity: quantity,
                    price: price,
                    total: total,
                  ));

                  setState(() {}); // Update parent dialog
                  Navigator.pop(context);
                },
                child: const Text('Add Item'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddCustomerDialog(SharedDataService sharedData) {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    final addressController = TextEditingController();
    final customerIdController = TextEditingController();

    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Add Distributor'),
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
                    const Text('Adding distributor...'),
                  ],
                ),
              ),
            )
                : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: customerIdController,
                    decoration: const InputDecoration(labelText: 'Customer ID'),
                  ),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  TextField(
                    controller: emailController,
                    decoration: const InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  TextField(
                    controller: phoneController,
                    decoration: const InputDecoration(labelText: 'Phone'),
                    keyboardType: TextInputType.phone,
                  ),
                  TextField(
                    controller: addressController,
                    decoration: const InputDecoration(labelText: 'Address'),
                    maxLines: 2,
                  ),
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
                  if (nameController.text.isEmpty || customerIdController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please fill in required fields')),
                    );
                    return;
                  }

                  setState(() {
                    isSubmitting = true;
                  });

                  final customer = Customer(
                    id: '',
                    customerId: customerIdController.text,
                    name: nameController.text,
                    email: emailController.text,
                    phone: phoneController.text,
                    address: addressController.text,
                    type: 'Regular',
                    status: 'Active',
                  );

                  await _createCustomer(customer, sharedData);

                  if (mounted) {
                    Navigator.pop(context);
                  }
                },
                child: const Text('Add Distributor'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _createCustomer(Customer customer, SharedDataService sharedData) async {
    setState(() {
      _isCreatingCustomer = true;
    });

    try {
      final docRef = await _firestore
          .collection('customers')
          .add({
        'customerId': customer.customerId,
        'name': customer.name,
        'email': customer.email,
        'phone': customer.phone,
        'address': customer.address,
        'type': customer.type,
        'status': customer.status,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Add to shared data
      sharedData.addCustomer(Customer(
        id: docRef.id,
        customerId: customer.customerId,
        name: customer.name,
        email: customer.email,
        phone: customer.phone,
        address: customer.address,
        type: customer.type,
        status: customer.status,
      ));

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Distributor added successfully'),
            backgroundColor: Colors.green),
      );
    } catch (e) {
      print('Error creating distributor: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error creating distributor')),
      );
    } finally {
      setState(() {
        _isCreatingCustomer = false;
      });
    }
  }

  void _showCreateQuotationDialog(SharedDataService sharedData) {
    Customer? selectedCustomer;
    final List<OrderItem> quotationItems = [];
    final referenceController = TextEditingController();
    final notesController = TextEditingController();
    final expiryDateController = TextEditingController(
        text: DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 30)))
    );

    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Create Quotation'),
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
                    const Text('Creating quotation...'),
                  ],
                ),
              ),
            )
                : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<Customer>(
                    value: selectedCustomer,
                    decoration: const InputDecoration(labelText: 'Distributor'),
                    items: sharedData.customers.map((Customer customer) {
                      return DropdownMenuItem<Customer>(
                        value: customer,
                        child: Text(customer.name),
                      );
                    }).toList(),
                    onChanged: (Customer? newValue) {
                      setState(() {
                        selectedCustomer = newValue;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text('Quotation Items:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...quotationItems.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    return ListTile(
                      title: Text('${item.quantity}x ${item.product}'),
                      subtitle: Text('${item.total.toStringAsFixed(0)} FCFA'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, size: 18),
                        onPressed: () {
                          setState(() {
                            quotationItems.removeAt(index);
                          });
                        },
                      ),
                    );
                  }),
                  ElevatedButton(
                    onPressed: () => _showAddQuotationItemDialog(sharedData, quotationItems, setState),
                    child: const Text('Add Item'),
                  ),
                  TextField(
                    controller: expiryDateController,
                    decoration: const InputDecoration(labelText: 'Expiry Date'),
                    readOnly: true,
                    onTap: () async {
                      final DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now().add(const Duration(days: 30)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        expiryDateController.text = DateFormat('yyyy-MM-dd').format(picked);
                      }
                    },
                  ),
                  TextField(
                    controller: referenceController,
                    decoration: const InputDecoration(labelText: 'Reference Number'),
                  ),
                  TextField(
                    controller: notesController,
                    decoration: const InputDecoration(labelText: 'Notes'),
                    maxLines: 2,
                  ),
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
                onPressed: (selectedCustomer == null || quotationItems.isEmpty) ? null : () async {
                  setState(() {
                    isSubmitting = true;
                  });

                  final total = quotationItems.fold(0.0, (sum, item) => sum + item.total);
                  final quotation = Quotation(
                    id: '',
                    customer: selectedCustomer!.name,
                    date: DateTime.now(),
                    expiryDate: DateTime.parse(expiryDateController.text),
                    status: 'Pending',
                    total: total,
                    customerId: selectedCustomer!.customerId,
                    reference: referenceController.text,
                    notes: notesController.text,
                    items: quotationItems,
                  );

                  await _createQuotation(quotation);

                  if (mounted) {
                    Navigator.pop(context);
                  }
                },
                child: const Text('Create Quotation'),
              ),
            ],
          );
        },
      ),
    );
  }
  void _showAddQuotationItemDialog(SharedDataService sharedData, List<OrderItem> quotationItems, StateSetter setState) {
    Product? selectedProduct;
    final quantityController = TextEditingController(text: '1');
    final priceController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, dialogSetState) {
          return AlertDialog(
            title: const Text('Add Quotation Item'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<Product>(
                  value: selectedProduct,
                  decoration: const InputDecoration(labelText: 'Product'),
                  items: sharedData.products.map((Product product) {
                    return DropdownMenuItem<Product>(
                      value: product,
                      child: Text('${product.name} (Price: ${product.price.toStringAsFixed(0)} FCFA)'),
                    );
                  }).toList(),
                  onChanged: (Product? newValue) {
                    dialogSetState(() {
                      selectedProduct = newValue;
                      if (newValue != null) {
                        priceController.text = newValue.price.toStringAsFixed(2);
                      }
                    });
                  },
                ),
                TextField(
                  controller: quantityController,
                  decoration: const InputDecoration(labelText: 'Quantity'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: priceController,
                  decoration: const InputDecoration(labelText: 'Unit Price'),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: selectedProduct == null ? null : () {
                  final quantity = int.tryParse(quantityController.text) ?? 1;
                  final price = double.tryParse(priceController.text) ?? selectedProduct!.price;
                  final total = quantity * price;

                  quotationItems.add(OrderItem(
                    product: selectedProduct!.name,
                    quantity: quantity,
                    price: price,
                    total: total,
                  ));

                  setState(() {}); // Update parent dialog
                  Navigator.pop(context);
                },
                child: const Text('Add Item'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _viewOrderDetails(SalesOrder order) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Order ${order.reference}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Customer: ${order.customer}'),
              Text('Status: ${order.status}'),
              Text('Total: ${order.total.toStringAsFixed(0)} FCFA'),
              Text('Date: ${DateFormat('MMM d, y').format(order.date)}'),
              if (order.invoiceCreated)
                Text('Invoice: Created ✓', style: TextStyle(color: Colors.green[700])),
              const SizedBox(height: 16),
              const Text('Items:', style: TextStyle(fontWeight: FontWeight.bold)),
              ...order.items.map((item) => Text(
                  '${item.quantity}x ${item.product} - ${item.total.toStringAsFixed(0)} FCFA'
              )),
            ],
          ),
        ),
        actions: [
          if (order.status == 'Delivered' && !order.invoiceCreated)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _createInvoiceForOrder(order);
              },
              child: const Text('Create Invoice'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }


  void _showQuotationActions(Quotation quotation) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.visibility),
            title: const Text('View Details'),
            onTap: () {
              Navigator.pop(context);
              _viewQuotationDetails(quotation);
            },
          ),
          if (quotation.status == 'Pending')
            ListTile(
              leading: _isConvertingQuotation
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.shopping_cart),
              title: const Text('Convert to Order'),
              onTap: _isConvertingQuotation ? null : () {
                Navigator.pop(context);
                _convertQuotationToOrder(quotation.id);
              },
            ),
        ],
      ),
    );
  }

  void _viewQuotationDetails(Quotation quotation) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Quotation ${quotation.reference}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Customer: ${quotation.customer}'),
              Text('Status: ${quotation.status}'),
              Text('Total: ${quotation.total.toStringAsFixed(0)} FCFA'),
              Text('Valid Until: ${DateFormat('MMM d, y').format(quotation.expiryDate)}'),
              const SizedBox(height: 16),
              const Text('Items:', style: TextStyle(fontWeight: FontWeight.bold)),
              ...quotation.items.map((item) => Text(
                  '${item.quantity}x ${item.product} - ${item.total.toStringAsFixed(0)} FCFA'
              )),
            ],
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
}

class SalesOrder {
  final String id;
  final String customer;
  final DateTime date;
  final String status;
  final double total;
  final List<OrderItem> items;
  final String customerId;
  final String reference;
  final String notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool invoiceCreated;
  final String invoiceId;
  final bool stockDeducted;

  SalesOrder({
    required this.id,
    required this.customer,
    required this.date,
    required this.status,
    required this.total,
    required this.items,
    required this.customerId,
    required this.reference,
    required this.notes,
    this.createdAt,
    this.updatedAt,
    this.invoiceCreated = false,
    this.invoiceId = '',
    this.stockDeducted = false,
  });
}

class OrderItem {
  final String product;
  final int quantity;
  final double price;
  final double total;

  OrderItem({
    required this.product,
    required this.quantity,
    required this.price,
    required this.total,
  });
}

class Quotation {
  final String id;
  final String customer;
  final DateTime date;
  final DateTime expiryDate;
  final String status;
  final double total;
  final String customerId;
  final String reference;
  final String notes;
  final List<OrderItem> items;
  final DateTime? createdAt;

  Quotation({
    required this.id,
    required this.customer,
    required this.date,
    required this.expiryDate,
    required this.status,
    required this.total,
    required this.customerId,
    required this.reference,
    required this.notes,
    required this.items,
    this.createdAt,
  });
}

class SalesData {
  final String month;
  final double amount;

  SalesData(this.month, this.amount);
}