import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';

import '../services/shared_data_service.dart';
import '../services/auth_service.dart'; // Add this import

class InventoryModule extends StatefulWidget {
  const InventoryModule({super.key});

  @override
  State<InventoryModule> createState() => _InventoryModuleState();
}

class _InventoryModuleState extends State<InventoryModule> {
  int _currentTabIndex = 0;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<InventoryMovement> _movements = [];
  bool _isLoading = true;
  bool _isSaving = false;
  String _userRole = 'manager'; // Default to manager for safety

  // Track ongoing operations to prevent duplicates
  final Set<String> _ongoingOperations = {};

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    final sharedData = Provider.of<SharedDataService>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);

    // Get user role
    final user = await authService.getCurrentUser();
    _userRole = user?['role'] ?? 'manager';

    if (sharedData.products.isEmpty) {
      await sharedData.loadSharedData();
    }

    await _loadInventoryData();
  }

  Future<void> _loadInventoryData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final movementsSnapshot = await _firestore
          .collection('inventory')
          .doc('movements')
          .collection('transactions')
          .orderBy('date', descending: true)
          .limit(50)
          .get();

      _movements = movementsSnapshot.docs.map((doc) {
        final data = doc.data();
        return InventoryMovement(
          id: doc.id,
          productId: data['productId'] ?? '',
          productName: data['productName'] ?? '',
          type: data['type'] ?? '',
          quantity: (data['quantity'] ?? 0).toInt(),
          date: data['date']?.toDate() ?? DateTime.now(),
          reference: data['reference'] ?? '',
          customerId: data['customerId'] ?? '',
          customerName: data['customerName'] ?? '',
          notes: data['notes'] ?? '',
          discount: (data['discount'] ?? 0.0).toDouble(),
        );
      }).toList();

    } catch (e) {
      print('Error loading inventory data: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error loading inventory data')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // ADMIN ONLY: Delete product functionality
  Future<void> _deleteProduct(Product product) async {
    final operationId = 'delete_product_${product.id}_${DateTime.now().millisecondsSinceEpoch}';

    // Prevent duplicate operations
    if (_ongoingOperations.contains(operationId)) return;
    _ongoingOperations.add(operationId);

    // Confirm deletion
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Product'),
        content: Text('Are you sure you want to delete "${product.name}"? This action cannot be undone.'),
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

    if (confirmed != true) {
      _ongoingOperations.remove(operationId);
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      // Delete from Firestore
      await _firestore
          .collection('inventory')
          .doc('products')
          .collection('items')
          .doc(product.id)
          .delete();

      // Remove from shared data
      final sharedData = Provider.of<SharedDataService>(context, listen: false);
      sharedData.removeProduct(product.id);

      // Record deletion movement
      await _recordMovement(
        productId: product.id,
        productName: product.name,
        type: 'Deletion',
        quantity: 0,
        reference: 'DEL-${DateFormat('yyyyMMdd').format(DateTime.now())}',
        notes: 'Product deleted from inventory',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Product "${product.name}" deleted successfully')),
      );

      await _loadInventoryData();
    } catch (e) {
      print('Error deleting product: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error deleting product')),
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
      _ongoingOperations.remove(operationId);
    }
  }

  Future<void> _addProduct(Product product) async {

    final operationId = 'add_product_${product.name}_${DateTime.now().millisecondsSinceEpoch}';

    // Prevent duplicate operations
    if (_ongoingOperations.contains(operationId)) return;
    _ongoingOperations.add(operationId);

    setState(() {
      _isSaving = true;
    });

    try {
      final docRef = await _firestore
          .collection('inventory')
          .doc('products')
          .collection('items')
          .add({
        'name': product.name,
        'category': product.category,
        'stock': product.stock,
        'cost': product.cost,
        'price': product.price,
        'lowStockThreshold': product.lowStockThreshold,
        'unit': product.unit,
        'lastUpdated': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Add to shared data
      final sharedData = Provider.of<SharedDataService>(context, listen: false);
      sharedData.addProduct(Product(
        id: docRef.id,
        name: product.name,
        category: product.category,
        stock: product.stock,
        cost: product.cost,
        price: product.price,
        lowStockThreshold: product.lowStockThreshold,
        unit: product.unit,
      ));

      // Add initial stock movement
      await _recordMovement(
        productId: docRef.id,
        productName: product.name,
        type: 'Initial Stock',
        quantity: product.stock,
        reference: 'INIT-${DateFormat('yyyyMMdd').format(DateTime.now())}',
        notes: 'Initial stock setup',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product added successfully')),
      );

    } catch (e) {
      print('Error adding product: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error adding product')),
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
      _ongoingOperations.remove(operationId);
    }
  }

  Future<void> _updateProduct(Product product) async {

    final operationId = 'update_product_${product.id}_${DateTime.now().millisecondsSinceEpoch}';

    // Prevent duplicate operations
    if (_ongoingOperations.contains(operationId)) return;
    _ongoingOperations.add(operationId);

    setState(() {
      _isSaving = true;
    });

    try {
      await _firestore
          .collection('inventory')
          .doc('products')
          .collection('items')
          .doc(product.id)
          .update({
        'category': product.category,
        'cost': product.cost,
        'price': product.price,
        'lowStockThreshold': product.lowStockThreshold,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      // Update shared data
      final sharedData = Provider.of<SharedDataService>(context, listen: false);
      sharedData.updateProduct(product);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product updated successfully')),
      );

      await _loadInventoryData();
    } catch (e) {
      print('Error updating product: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error updating product')),
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
      _ongoingOperations.remove(operationId);
    }
  }

  Future<void> _recordMovement({
    required String productId,
    required String productName,
    required String type,
    required int quantity,
    String reference = '',
    String customerId = '',
    String customerName = '',
    String notes = '',
    double discount = 0.0,
  }) async {
    final operationId = 'movement_${productId}_${type}_${DateTime.now().millisecondsSinceEpoch}';

    // Prevent duplicate operations
    if (_ongoingOperations.contains(operationId)) return;
    _ongoingOperations.add(operationId);

    try {
      await _firestore
          .collection('inventory')
          .doc('movements')
          .collection('transactions')
          .add({
        'productId': productId,
        'productName': productName,
        'type': type,
        'quantity': quantity,
        'date': FieldValue.serverTimestamp(),
        'reference': reference,
        'customerId': customerId,
        'customerName': customerName,
        'notes': notes,
        'discount': discount,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Update product stock in shared data
      final sharedData = Provider.of<SharedDataService>(context, listen: false);
      if (type == 'Sale' || type == 'Adjustment Out') {
        sharedData.updateProductStock(productId, -quantity);
      } else if (type == 'Production' || type == 'Adjustment In' || type == 'Initial Stock') {
        sharedData.updateProductStock(productId, quantity);
      }

      // Update Firestore
      final productDoc = _firestore
          .collection('inventory')
          .doc('products')
          .collection('items')
          .doc(productId);

      if (type == 'Sale' || type == 'Adjustment Out') {
        await productDoc.update({
          'stock': FieldValue.increment(-quantity),
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      } else if (type == 'Production' || type == 'Adjustment In' || type == 'Initial Stock') {
        await productDoc.update({
          'stock': FieldValue.increment(quantity),
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      }

      // Refresh movements data immediately after recording
      await _loadInventoryData();

    } catch (e) {
      print('Error recording movement: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error recording movement')),
      );
    } finally {
      _ongoingOperations.remove(operationId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sharedData = Provider.of<SharedDataService>(context);

    if (_isLoading || sharedData.isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final totalProducts = sharedData.products.length;
    final lowStockItems = sharedData.products.where((p) => p.stock <= p.lowStockThreshold).length;
    final totalStockValue = sharedData.products.fold(0.0, (sum, p) => sum + (p.stock * p.cost));

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Inventory Management'),

          ],
        ),
        backgroundColor: Colors.blue[800],
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadInventoryData,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStatsRow(totalProducts, lowStockItems, totalStockValue),
          const SizedBox(height: 16),
          _buildTabBar(),
          Expanded(
            child: _isSaving
                ? const Center(child: CircularProgressIndicator())
                : _buildCurrentTab(sharedData),
          ),
        ],
      ),
      floatingActionButton: _isSaving
          ? FloatingActionButton(
        onPressed: null,
        backgroundColor: Colors.grey,
        child: const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
      )
          : FloatingActionButton(
        onPressed: (){ if(_userRole=="admin"){
          _showAddMenu(context, sharedData);
        }else{
          {
           //  Navigator.pop(context);
            _showRecordProductionDialog(sharedData);
          };
        }
          },
        backgroundColor: Colors.blue[800],
        child: const Icon(Icons.add, color: Colors.white),
      )// Hide FAB for managers
    );
  }

  void _showAddMenu(BuildContext context, SharedDataService sharedData) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
           ListTile(
            leading: const Icon(Icons.inventory),
            title: const Text('Add Product'),
            onTap: () {
              Navigator.pop(context);
              _showAddProductDialog();
            },
          ),
          ListTile(
            leading: const Icon(Icons.add_shopping_cart),
            title: const Text('Record Production'),
            onTap: () {
              Navigator.pop(context);
              _showRecordProductionDialog(sharedData);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('Modify Product'),
            onTap: () {
              Navigator.pop(context);
              _showModifyProductDialog(sharedData);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(int totalProducts, int lowStockItems, double totalStockValue) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('Total Products', totalProducts.toString(), Icons.inventory),
          _buildStatItem('Low Stock', lowStockItems.toString(), Icons.warning, color: Colors.orange),
          _buildStatItem('Total Value', '${totalStockValue.toStringAsFixed(0)} FCFA', Icons.attach_money, color: Colors.green),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, {Color color = Colors.blue}) {
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
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
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
          _buildTabButton('Overview', 0),
          _buildTabButton('Products', 1),
          _buildTabButton('Movements', 2),
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
        ),
        child: Text(text),
      ),
    );
  }

  Widget _buildCurrentTab(SharedDataService sharedData) {
    switch (_currentTabIndex) {
      case 0:
        return _buildOverviewTab(sharedData);
      case 1:
        return _buildProductsTab(sharedData);
      case 2:
        return _buildMovementsTab();
      default:
        return _buildOverviewTab(sharedData);
    }
  }

  Widget _buildOverviewTab(SharedDataService sharedData) {
    final lowStockProducts = sharedData.products.where((p) => p.stock <= p.lowStockThreshold).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Stock Overview',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 200,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SfCartesianChart(
              primaryXAxis: CategoryAxis(
                majorGridLines: const MajorGridLines(width: 0),
              ),
              primaryYAxis: NumericAxis(
                majorGridLines: const MajorGridLines(width: 0),
                majorTickLines: const MajorTickLines(size: 0),
              ),
              series: <CartesianSeries>[
                ColumnSeries<Product, String>(
                  dataSource: sharedData.products.take(10).toList(),
                  xValueMapper: (Product product, _) => product.name,
                  yValueMapper: (Product product, _) => product.stock,
                  color: Colors.blue,
                )
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Low Stock Alerts',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          if (lowStockProducts.isEmpty)
            const Text('No low stock items. Good job!')
          else
            Column(
              children: lowStockProducts.map((product) => _buildProductCard(product, showActions: _userRole == 'admin')).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildProductsTab(SharedDataService sharedData) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Products',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        ...sharedData.products.map((product) => _buildProductCard(product, showActions: _userRole == 'admin')),
      ],
    );
  }

  Widget _buildProductCard(Product product, {bool showActions = false}) {
    final isLowStock = product.stock <= product.lowStockThreshold;

    return GestureDetector(
      onLongPress: _userRole == 'admin'
          ? () => _deleteProduct(product)
          : null,
      child: Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _getCategoryColor(product.category).withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _getCategoryIcon(product.category),
                      color: _getCategoryColor(product.category),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '${product.category} • ${product.unit}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isLowStock)
                    const Icon(Icons.warning, color: Colors.orange),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildProductDetail('Stock', '${product.stock} ${product.unit}'),
                  _buildProductDetail('Cost', '${product.cost.toStringAsFixed(0)} FCFA'),
                  _buildProductDetail('Price', '${product.price.toStringAsFixed(0)} FCFA'),
                ],
              ),
              if (showActions && _userRole == 'admin') ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showModifyProductDialog(Provider.of<SharedDataService>(context, listen: false), product: product),
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text('Modify Product'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _showRecordProductionDialog(Provider.of<SharedDataService>(context, listen: false), product: product),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add Production'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductDetail(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMovementsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Inventory Movements',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        ..._movements.map((movement) => _buildMovementCard(movement)),
      ],
    );
  }

  Widget _buildMovementCard(InventoryMovement movement) {
    final isPositive = movement.quantity > 0;
    final hasDiscount = movement.discount > 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _getMovementTypeColor(movement.type).withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(
            _getMovementTypeIcon(movement.type),
            color: _getMovementTypeColor(movement.type),
            size: 20,
          ),
        ),
        title: Text(movement.productName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${movement.type} • ${DateFormat('MMM d, y').format(movement.date)}'),
            if (hasDiscount && movement.type == 'Sale')
              Text(
                'Discount: ${movement.discount}%',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.green[700],
                ),
              ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              isPositive ? '+${movement.quantity}' : '${movement.quantity}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isPositive ? Colors.green : Colors.red,
              ),
            ),
            Text(
              movement.reference,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddProductDialog() {
    final nameController = TextEditingController();
    final categoryController = TextEditingController();
    final stockController = TextEditingController(text: '0');
    final costController = TextEditingController(text: '0.00');
    final priceController = TextEditingController(text: '0.00');
    final skuController = TextEditingController();
    final unitController = TextEditingController(text: 'kg');
    final thresholdController = TextEditingController(text: '10');

    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Add New Product'),
            content: isSubmitting
                ? SizedBox(
              height: 100,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[800]!),
                    ),
                    const SizedBox(height: 16),
                    const Text('Adding product...'),
                  ],
                ),
              ),
            )
                : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Product Name'),
                  ),
                  TextField(
                    controller: categoryController,
                    decoration: const InputDecoration(labelText: 'Category'),
                  ),
                  TextField(
                    controller: skuController,
                    decoration: const InputDecoration(labelText: 'SKU'),
                  ),
                  TextField(
                    controller: unitController,
                    decoration: const InputDecoration(labelText: 'Unit'),
                  ),
                  TextField(
                    controller: stockController,
                    decoration: const InputDecoration(labelText: 'Initial Stock'),
                    keyboardType: TextInputType.number,
                  ),
                  TextField(
                    controller: costController,
                    decoration: const InputDecoration(labelText: 'Cost Price'),
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                  ),
                  TextField(
                    controller: priceController,
                    decoration: const InputDecoration(labelText: 'Selling Price'),
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                  ),
                  TextField(
                    controller: thresholdController,
                    decoration: const InputDecoration(labelText: 'Low Stock Threshold'),
                    keyboardType: TextInputType.number,
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
                  setState(() {
                    isSubmitting = true;
                  });

                  final product = Product(
                    id: '',
                    name: nameController.text,
                    category: categoryController.text,
                    stock: int.tryParse(stockController.text) ?? 0,
                    cost: double.tryParse(costController.text) ?? 0.0,
                    price: double.tryParse(priceController.text) ?? 0.0,
                    lowStockThreshold: int.tryParse(thresholdController.text) ?? 10,
                    unit: unitController.text,
                  );
                  await _addProduct(product);

                  if (mounted) {
                    Navigator.pop(context);
                  }
                },
                child: const Text('Add Product'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showModifyProductDialog(SharedDataService sharedData, {Product? product}) {

    Product? selectedProduct = product;
    final categoryController = TextEditingController(text: product?.category ?? '');
    final costController = TextEditingController(text: product?.cost.toString() ?? '0.00');
    final priceController = TextEditingController(text: product?.price.toString() ?? '0.00');
    final thresholdController = TextEditingController(text: product?.lowStockThreshold.toString() ?? '10');

    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Modify Product'),
            content: isSubmitting
                ? SizedBox(
              height: 100,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[800]!),
                    ),
                    const SizedBox(height: 16),
                    const Text('Updating product...'),
                  ],
                ),
              ),
            )
                : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (product == null)
                    DropdownButtonFormField<Product>(
                      value: selectedProduct,
                      decoration: const InputDecoration(labelText: 'Product'),
                      items: sharedData.products.map((Product product) {
                        return DropdownMenuItem<Product>(
                          value: product,
                          child: Text(product.name),
                        );
                      }).toList(),
                      onChanged: (Product? newValue) {
                        setState(() {
                          selectedProduct = newValue;
                          if (newValue != null) {
                            categoryController.text = newValue.category;
                            costController.text = newValue.cost.toStringAsFixed(2);
                            priceController.text = newValue.price.toStringAsFixed(2);
                            thresholdController.text = newValue.lowStockThreshold.toString();
                          }
                        });
                      },
                    ),
                  TextField(
                    controller: categoryController,
                    decoration: const InputDecoration(labelText: 'Category'),
                  ),
                  TextField(
                    controller: costController,
                    decoration: const InputDecoration(labelText: 'Cost Price'),
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                  ),
                  TextField(
                    controller: priceController,
                    decoration: const InputDecoration(labelText: 'Selling Price'),
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                  ),
                  TextField(
                    controller: thresholdController,
                    decoration: const InputDecoration(labelText: 'Low Stock Threshold'),
                    keyboardType: TextInputType.number,
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
                onPressed: selectedProduct == null ? null : () async {
                  setState(() {
                    isSubmitting = true;
                  });

                  final updatedProduct = Product(
                    id: selectedProduct!.id,
                    name: selectedProduct!.name,
                    category: categoryController.text,
                    stock: selectedProduct!.stock,
                    cost: double.tryParse(costController.text) ?? selectedProduct!.cost,
                    price: double.tryParse(priceController.text) ?? selectedProduct!.price,
                    lowStockThreshold: int.tryParse(thresholdController.text) ?? selectedProduct!.lowStockThreshold,
                    unit: selectedProduct!.unit,
                  );
                  await _updateProduct(updatedProduct);

                  if (mounted) {
                    Navigator.pop(context);
                  }
                },
                child: const Text('Update Product'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showRecordProductionDialog(SharedDataService sharedData, {Product? product}) {
    Product? selectedProduct = product;
    final quantityController = TextEditingController(text: '1');
    final referenceController = TextEditingController(text: 'PROD-${DateFormat('yyyyMMdd').format(DateTime.now())}');
    final notesController = TextEditingController();

    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Record Production'),
            content: isSubmitting
                ? SizedBox(
              height: 100,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[800]!),
                    ),
                    const SizedBox(height: 16),
                    const Text('Recording production...'),
                  ],
                ),
              ),
            )
                : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (product == null)
                    DropdownButtonFormField<Product>(
                      value: selectedProduct,
                      decoration: const InputDecoration(labelText: 'Product'),
                      items: sharedData.products.map((Product product) {
                        return DropdownMenuItem<Product>(
                          value: product,
                          child: Text('${product.name} (Current: ${product.stock} ${product.unit})'),
                        );
                      }).toList(),
                      onChanged: (Product? newValue) {
                        setState(() {
                          selectedProduct = newValue;
                        });
                      },
                    ),
                  TextField(
                    controller: quantityController,
                    decoration: const InputDecoration(labelText: 'Quantity Produced'),
                    keyboardType: TextInputType.number,
                  ),
                  TextField(
                    controller: referenceController,
                    decoration: const InputDecoration(labelText: 'Production Reference'),
                  ),
                  TextField(
                    controller: notesController,
                    decoration: const InputDecoration(labelText: 'Production Notes'),
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
                onPressed: selectedProduct == null ? null : () async {
                  setState(() {
                    isSubmitting = true;
                  });

                  await _recordMovement(
                    productId: selectedProduct!.id,
                    productName: selectedProduct!.name,
                    type: 'Production',
                    quantity: int.tryParse(quantityController.text) ?? 1,
                    reference: referenceController.text,
                    notes: notesController.text,
                  );

                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Production recorded successfully!'),
                        backgroundColor: Colors.green,
                      ),
                    );

                    setState(() {
                      _currentTabIndex = 2;
                    });
                  }
                },
                child: const Text('Record Production'),
              ),
            ],
          );
        },
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'food':
        return Colors.orange;
      case 'drink':
        return Colors.blue;
      case 'snack':
        return Colors.green;
      case 'dessert':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'food':
        return Icons.restaurant;
      case 'drink':
        return Icons.local_drink;
      case 'snack':
        return Icons.fastfood;
      case 'dessert':
        return Icons.cake;
      default:
        return Icons.category;
    }
  }

  Color _getMovementTypeColor(String type) {
    switch (type) {
      case 'Production':
        return Colors.green;
      case 'Sale':
        return Colors.red;
      case 'Adjustment In':
        return Colors.blue;
      case 'Adjustment Out':
        return Colors.orange;
      case 'Initial Stock':
        return Colors.purple;
      case 'Deletion':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getMovementTypeIcon(String type) {
    switch (type) {
      case 'Production':
        return Icons.factory;
      case 'Sale':
        return Icons.shopping_cart;
      case 'Adjustment In':
        return Icons.add;
      case 'Adjustment Out':
        return Icons.remove;
      case 'Initial Stock':
        return Icons.inventory;
      case 'Deletion':
        return Icons.delete;
      default:
        return Icons.swap_horiz;
    }
  }
}

class InventoryMovement {
  final String id;
  final String productId;
  final String productName;
  final String type;
  final int quantity;
  final DateTime date;
  final String reference;
  final String customerId;
  final String customerName;
  final String notes;
  final double discount;

  InventoryMovement({
    required this.id,
    required this.productId,
    required this.productName,
    required this.type,
    required this.quantity,
    required this.date,
    required this.reference,
    this.customerId = '',
    this.customerName = '',
    this.notes = '',
    this.discount = 0.0,
  });
}