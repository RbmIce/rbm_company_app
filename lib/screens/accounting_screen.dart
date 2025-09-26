import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AccountingModule extends StatefulWidget {
  const AccountingModule({super.key});

  @override
  State<AccountingModule> createState() => _AccountingModuleState();
}

class _AccountingModuleState extends State<AccountingModule> {
  int _currentTabIndex = 0;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Asset> _assets = [];
  List<Liability> _liabilities = [];
  List<Expense> _expenses = [];
  List<SalesOrder> _salesOrders = [];
  List<Product> _products = [];
  List<InventoryMovement> _salesMovements = [];
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadAccountingData();
  }

  Future<void> _loadAccountingData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Load assets
      final assetsSnapshot = await _firestore
          .collection('accounting')
          .doc('assets')
          .collection('items')
          .orderBy('date', descending: true)
          .get();

      _assets = assetsSnapshot.docs.map((doc) {
        final data = doc.data();
        return Asset(
          id: doc.id,
          name: data['name'] ?? '',
          description: data['description'] ?? '',
          value: (data['value'] ?? 0.0).toDouble(),
          date: data['date']?.toDate() ?? DateTime.now(),
          category: data['category'] ?? '',
          depreciation: (data['depreciation'] ?? 0.0).toDouble(),
          usefulLife: (data['usefulLife'] ?? 0).toInt(),
          createdAt: data['createdAt']?.toDate() ?? DateTime.now(),
        );
      }).toList();

      // Load liabilities
      final liabilitiesSnapshot = await _firestore
          .collection('accounting')
          .doc('liabilities')
          .collection('items')
          .orderBy('date', descending: true)
          .get();

      _liabilities = liabilitiesSnapshot.docs.map((doc) {
        final data = doc.data();
        return Liability(
          id: doc.id,
          name: data['name'] ?? '',
          description: data['description'] ?? '',
          amount: (data['amount'] ?? 0.0).toDouble(),
          date: data['date']?.toDate() ?? DateTime.now(),
          dueDate: data['dueDate']?.toDate(),
          interestRate: (data['interestRate'] ?? 0.0).toDouble(),
          status: data['status'] ?? 'Outstanding',
          createdAt: data['createdAt']?.toDate() ?? DateTime.now(),
        );
      }).toList();

      // Load expenses
      final expensesSnapshot = await _firestore
          .collection('accounting')
          .doc('expenses')
          .collection('items')
          .orderBy('date', descending: true)
          .get();

      _expenses = expensesSnapshot.docs.map((doc) {
        final data = doc.data();
        return Expense(
          id: doc.id,
          name: data['name'] ?? '',
          description: data['description'] ?? '',
          amount: (data['amount'] ?? 0.0).toDouble(),
          date: data['date']?.toDate() ?? DateTime.now(),
          category: data['category'] ?? '',
          paymentMethod: data['paymentMethod'] ?? '',
          status: data['status'] ?? 'Paid',
          createdAt: data['createdAt']?.toDate() ?? DateTime.now(),
        );
      }).toList();

      // MODIFIED: Load all sales orders and filter locally to avoid index requirement
      final salesSnapshot = await _firestore
          .collection('sales')
          .doc('orders')
          .collection('sales_orders')
          .orderBy('date', descending: true)
          .get();

      _salesOrders = salesSnapshot.docs.where((doc) {
        final data = doc.data();
        return data['status'] == 'Delivered';
      }).map((doc) {
        final data = doc.data();
        return SalesOrder(
          id: doc.id,
          customer: data['customer'] ?? '',
          date: data['date']?.toDate() ?? DateTime.now(),
          status: data['status'] ?? '',
          total: (data['total'] ?? 0.0).toDouble(),
          items: [],
          customerId: data['customerId'] ?? '',
          reference: data['reference'] ?? '',
          notes: data['notes'] ?? '',
        );
      }).toList();

      // Load products for cost calculation
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
          lowStockThreshold: (data['lowStockThreshold'] ?? 0).toInt(),
          sku: data['sku'] ?? '',
          unit: data['unit'] ?? 'units',
        );
      }).toList();

      // MODIFIED: Load all movements and filter locally to avoid index requirement
      final movementsSnapshot = await _firestore
          .collection('inventory')
          .doc('movements')
          .collection('transactions')
          .orderBy('date', descending: true)
          .get();

      _salesMovements = movementsSnapshot.docs.where((doc) {
        final data = doc.data();
        return data['type'] == 'Sale';
      }).map((doc) {
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
      print('Error loading accounting data: $e');
      setState(() {
        _errorMessage = 'Failed to load accounting data: ${e.toString()}';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading accounting data: ${e.toString()}')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  Future<void> _addAsset(Asset asset) async {
    setState(() {
      _isSaving = true;
    });

    try {
      await _firestore
          .collection('accounting')
          .doc('assets')
          .collection('items')
          .add({
        'name': asset.name,
        'description': asset.description,
        'value': asset.value,
        'date': asset.date,
        'category': asset.category,
        'depreciation': asset.depreciation,
        'usefulLife': asset.usefulLife,
        'createdAt': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Asset added successfully'),
        backgroundColor: Colors.green),
      );

      await _loadAccountingData();
    } catch (e) {
      print('Error adding asset: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error adding asset')),
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<void> _addLiability(Liability liability) async {
    setState(() {
      _isSaving = true;
    });

    try {
      await _firestore
          .collection('accounting')
          .doc('liabilities')
          .collection('items')
          .add({
        'name': liability.name,
        'description': liability.description,
        'amount': liability.amount,
        'date': liability.date,
        'dueDate': liability.dueDate,
        'interestRate': liability.interestRate,
        'status': liability.status,
        'createdAt': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Liability added successfully'),
        backgroundColor: Colors.green),
      );

      await _loadAccountingData();
    } catch (e) {
      print('Error adding liability: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error adding liability')),
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<void> _addExpense(Expense expense) async {
    setState(() {
      _isSaving = true;
    });

    try {
      await _firestore
          .collection('accounting')
          .doc('expenses')
          .collection('items')
          .add({
        'name': expense.name,
        'description': expense.description,
        'amount': expense.amount,
        'date': expense.date,
        'category': expense.category,
        'paymentMethod': expense.paymentMethod,
        'status': expense.status,
        'createdAt': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expense added successfully'),
        backgroundColor: Colors.green),
      );

      await _loadAccountingData();
    } catch (e) {
      print('Error adding expense: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error adding expense')),
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<void> _deleteAsset(String assetId) async {
    setState(() {
      _isSaving = true;
    });

    try {
      await _firestore
          .collection('accounting')
          .doc('assets')
          .collection('items')
          .doc(assetId)
          .delete();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Asset deleted successfully'),
        backgroundColor: Colors.green),
      );

      await _loadAccountingData();
    } catch (e) {
      print('Error deleting asset: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error deleting asset')),
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<void> _deleteLiability(String liabilityId) async {
    setState(() {
      _isSaving = true;
    });

    try {
      await _firestore
          .collection('accounting')
          .doc('liabilities')
          .collection('items')
          .doc(liabilityId)
          .delete();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Liability deleted successfully'),
        backgroundColor: Colors.green),
      );

      await _loadAccountingData();
    } catch (e) {
      print('Error deleting liability: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error deleting liability')),
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<void> _deleteExpense(String expenseId) async {
    setState(() {
      _isSaving = true;
    });

    try {
      await _firestore
          .collection('accounting')
          .doc('expenses')
          .collection('items')
          .doc(expenseId)
          .delete();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expense deleted successfully'),
        backgroundColor: Colors.green),
      );

      await _loadAccountingData();
    } catch (e) {
      print('Error deleting expense: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error deleting expense')),
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
      }
          }

          // Calculate financial metrics - CORRECTED
          double get _totalAssets => _assets.fold(0.0, (sum, asset) => sum + asset.value);

      double get _totalLiabilities => _liabilities.fold(0.0, (sum, liability) => sum + liability.amount);

      double get _totalExpenses => _expenses.fold(0.0, (sum, expense) => sum + expense.amount);

      double get _totalRevenue => _salesOrders.fold(0.0, (sum, order) => sum + order.total);

      double get _totalProductCosts {
        double totalCost = 0.0;
        for (var movement in _salesMovements) {
          final product = _products.firstWhere((p) => p.id == movement.productId, orElse: () => Product(
              id: '', name: '', category: '', stock: 0, cost: 0.0, price: 0.0, lowStockThreshold: 0, sku: '', unit: ''
          ));
          totalCost += movement.quantity * product.cost;
        }
        return totalCost;
      }

      double get _netIncome => _totalRevenue - _totalExpenses - _totalProductCosts;

      double get _equity => _totalAssets - _totalLiabilities;

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
                  Text('Loading accounting data...'),
                ],
              ),
            ),
          );
        }

        if (_errorMessage != null) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Accounting Module'),
              backgroundColor: Colors.purple[800],
            ),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, color: Colors.red),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _loadAccountingData,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: Colors.grey[100],
          appBar: AppBar(
            title: const Text('Accounting Module'),
            backgroundColor: Colors.purple[800],
            elevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadAccountingData,
                tooltip: 'Refresh Data',
              ),
            ],
          ),
          body: Column(
            children: [
              _buildFinancialSummary(),
              const SizedBox(height: 16),
              _buildTabBar(),
              Expanded(
                child: _isSaving
                    ? const Center(child: CircularProgressIndicator())
                    : _buildCurrentTab(),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _showAddMenu(context),
            backgroundColor: Colors.purple[800],
            child: const Icon(Icons.add, color: Colors.white),
          ),
        );
      }

      void _showAddMenu(BuildContext context) {
        showModalBottomSheet(
          context: context,
          builder: (context) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.business_center),
                title: const Text('Add Asset'),
                onTap: () {
                  Navigator.pop(context);
                  _showAddAssetDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.credit_card),
                title: const Text('Add Liability'),
                onTap: () {
                  Navigator.pop(context);
                  _showAddLiabilityDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.money_off),
                title: const Text('Add Expense'),
                onTap: () {
                  Navigator.pop(context);
                  _showAddExpenseDialog();
                },
              ),
            ],
          ),
        );
      }

      Widget _buildFinancialSummary() {
        return Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildFinancialItem('Assets', _totalAssets, Icons.business_center, Colors.green),
                  _buildFinancialItem('Liabilities', _totalLiabilities, Icons.credit_card, Colors.red),
                  _buildFinancialItem('Equity', _equity, Icons.pie_chart, Colors.blue),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildFinancialItem('Revenue', _totalRevenue, Icons.trending_up, Colors.green),
                  _buildFinancialItem('Expenses', _totalExpenses, Icons.trending_down, Colors.red),
                  _buildFinancialItem('Net Income', _netIncome, Icons.bar_chart, _netIncome >= 0 ? Colors.green : Colors.red),
                ],
              ),
              // const SizedBox(height: 16),
              // Row(
              //   mainAxisAlignment: MainAxisAlignment.spaceAround,
              //   children: [
              //     _buildFinancialItem('Net Income', _netIncome, Icons.bar_chart, _netIncome >= 0 ? Colors.green : Colors.red),
              //     _buildFinancialItem('Orders', _salesOrders.length.toDouble(), Icons.shopping_cart, Colors.purple),
              //     _buildFinancialItem('Products', _products.length.toDouble(), Icons.inventory, Colors.teal),
              //   ],
              // ),
            ],
          ),
        );
      }

      Widget _buildFinancialItem(String label, double value, IconData icon, Color color) {
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
              '${value.toStringAsFixed(0)} FCFA',
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
              _buildTabButton('Dashboard', 0),
              _buildTabButton('Assets', 1),
              _buildTabButton('Liabilities', 2),
              _buildTabButton('Expenses', 3),
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
              foregroundColor: isSelected ? Colors.purple[800] : Colors.grey,
              backgroundColor: isSelected ? Colors.purple[50] : Colors.transparent,
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

      Widget _buildCurrentTab() {
        switch (_currentTabIndex) {
          case 0:
            return _buildDashboardTab();
          case 1:
            return _buildAssetsTab();
          case 2:
            return _buildLiabilitiesTab();
          case 3:
            return _buildExpensesTab();
          default:
            return _buildDashboardTab();
        }
      }

      Widget _buildDashboardTab() {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Financial Overview',
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
                    numberFormat: NumberFormat.simpleCurrency(decimalDigits: 0),
                    majorGridLines: const MajorGridLines(width: 0),
                    majorTickLines: const MajorTickLines(size: 0),
                  ),
                  series: <CartesianSeries>[
                    ColumnSeries<Map<String, dynamic>, String>(
                      dataSource: [
                        {'category': 'Assets', 'value': _totalAssets},
                        {'category': 'Liabilities', 'value': _totalLiabilities},
                        {'category': 'Equity', 'value': _equity},
                        {'category': 'Revenue', 'value': _totalRevenue},
                        {'category': 'Expenses', 'value': _totalExpenses},
                        {'category': 'Product Costs', 'value': _totalProductCosts},
                      ],
                      xValueMapper: (data, _) => data['category'],
                      yValueMapper: (data, _) => data['value'],
                      color: Colors.purple,
                    )
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Recent Sales Orders',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ..._salesOrders.take(3).map((order) => _buildSalesOrderCard(order)),
            ],
          ),
        );
      }

      Widget _buildSalesOrderCard(SalesOrder order) {
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: const Icon(Icons.shopping_cart, color: Colors.green),
            title: Text(order.reference.isNotEmpty ? order.reference : 'SO-${order.id.substring(0, 8)}'),
            subtitle: Text('${order.customer} • ${DateFormat('MMM d, y').format(order.date)}'),
            trailing: Text(
              '${order.total.toStringAsFixed(0)} FCFA',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
            ),
          ),
        );
      }

      Widget _buildAssetsTab() {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Assets',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ..._assets.map((asset) => _buildAssetCard(asset)),
          ],
        );
      }

      Widget _buildAssetCard(Asset asset) {
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: const Icon(Icons.business_center, color: Colors.green),
            title: Text(asset.name),
            subtitle: Text('${asset.category} • ${DateFormat('MMM d, y').format(asset.date)}'),
            trailing: Text(
              '${asset.value.toStringAsFixed(0)} FCFA',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
            ),
            onLongPress: () => _showDeleteDialog('asset', asset.id, asset.name),
          ),
        );
      }

      Widget _buildLiabilitiesTab() {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Liabilities',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ..._liabilities.map((liability) => _buildLiabilityCard(liability)),
          ],
        );
      }

      Widget _buildLiabilityCard(Liability liability) {
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: const Icon(Icons.credit_card, color: Colors.red),
            title: Text(liability.name),
            subtitle: Text('${liability.status} • ${DateFormat('MMM d, y').format(liability.date)}'),
            trailing: Text(
              '${liability.amount.toStringAsFixed(0)} FCFA',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
            ),
            onLongPress: () => _showDeleteDialog('liability', liability.id, liability.name),
          ),
        );
      }

      Widget _buildExpensesTab() {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Expenses',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ..._expenses.map((expense) => _buildExpenseCard(expense)),
          ],
        );
      }

      Widget _buildExpenseCard(Expense expense) {
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: const Icon(Icons.money_off, color: Colors.orange),
            title: Text(expense.name),
            subtitle: Text('${expense.category} • ${expense.paymentMethod}'),
            trailing: Text(
              '${expense.amount.toStringAsFixed(0)} FCFA',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
            ),
            onLongPress: () => _showDeleteDialog('expense', expense.id, expense.name),
          ),
        );
      }

  void _showDeleteDialog(String type, String id, String name) {
    bool isDeleting = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text('Delete $type'),
            content: isDeleting
                ? SizedBox(
              height: 100,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.purple[800]!),
                    ),
                    const SizedBox(height: 16),
                    Text('Deleting $type...'),
                  ],
                ),
              ),
            )
                : Text('Are you sure you want to delete $name?'),
            actions: isDeleting
                ? []
                : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  setState(() {
                    isDeleting = true;
                  });

                  try {
                    switch (type) {
                      case 'asset':
                        await _deleteAsset(id);
                        break;
                      case 'liability':
                        await _deleteLiability(id);
                        break;
                      case 'expense':
                        await _deleteExpense(id);
                        break;
                    }

                    if (mounted) {
                      Navigator.pop(context);
                    }
                  } catch (e) {
                    setState(() {
                      isDeleting = false;
                    });
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddAssetDialog() {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final valueController = TextEditingController();
    final categoryController = TextEditingController();
    final depreciationController = TextEditingController(text: '0');
    final usefulLifeController = TextEditingController(text: '0');

    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Add Asset'),
            content: isSubmitting
                ? SizedBox(
              height: 150,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.purple[800]!),
                    ),
                    const SizedBox(height: 16),
                    const Text('Adding asset...'),
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
                    decoration: const InputDecoration(labelText: 'Asset Name'),
                  ),
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                  TextField(
                    controller: valueController,
                    decoration: const InputDecoration(labelText: 'Value'),
                    keyboardType: TextInputType.number,
                  ),
                  TextField(
                    controller: categoryController,
                    decoration: const InputDecoration(labelText: 'Category'),
                  ),
                  TextField(
                    controller: depreciationController,
                    decoration: const InputDecoration(labelText: 'Depreciation (%)'),
                    keyboardType: TextInputType.number,
                  ),
                  TextField(
                    controller: usefulLifeController,
                    decoration: const InputDecoration(labelText: 'Useful Life (years)'),
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
                  if (nameController.text.isEmpty || valueController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please fill in required fields')),
                    );
                    return;
                  }

                  setState(() {
                    isSubmitting = true;
                  });

                  final asset = Asset(
                    id: '',
                    name: nameController.text,
                    description: descriptionController.text,
                    value: double.tryParse(valueController.text) ?? 0.0,
                    date: DateTime.now(),
                    category: categoryController.text,
                    depreciation: double.tryParse(depreciationController.text) ?? 0.0,
                    usefulLife: int.tryParse(usefulLifeController.text) ?? 0,
                    createdAt: DateTime.now(),
                  );

                  await _addAsset(asset);

                  if (mounted) {
                    Navigator.pop(context);
                  }
                },
                child: const Text('Add Asset'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddLiabilityDialog() {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final amountController = TextEditingController();
    final interestRateController = TextEditingController(text: '0');

    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Add Liability'),
            content: isSubmitting
                ? SizedBox(
              height: 150,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.purple[800]!),
                    ),
                    const SizedBox(height: 16),
                    const Text('Adding liability...'),
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
                    decoration: const InputDecoration(labelText: 'Liability Name'),
                  ),
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                  TextField(
                    controller: amountController,
                    decoration: const InputDecoration(labelText: 'Amount'),
                    keyboardType: TextInputType.number,
                  ),
                  TextField(
                    controller: interestRateController,
                    decoration: const InputDecoration(labelText: 'Interest Rate (%)'),
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
                  if (nameController.text.isEmpty || amountController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please fill in required fields')),
                    );
                    return;
                  }

                  setState(() {
                    isSubmitting = true;
                  });

                  final liability = Liability(
                    id: '',
                    name: nameController.text,
                    description: descriptionController.text,
                    amount: double.tryParse(amountController.text) ?? 0.0,
                    date: DateTime.now(),
                    interestRate: double.tryParse(interestRateController.text) ?? 0.0,
                    status: 'Outstanding',
                    createdAt: DateTime.now(),
                  );

                  await _addLiability(liability);

                  if (mounted) {
                    Navigator.pop(context);
                  }
                },
                child: const Text('Add Liability'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddExpenseDialog() {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final amountController = TextEditingController();
    final categoryController = TextEditingController();
    String selectedPaymentMethod = 'Cash';

    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Add Expense'),
            content: isSubmitting
                ? SizedBox(
              height: 150,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.purple[800]!),
                    ),
                    const SizedBox(height: 16),
                    const Text('Adding expense...'),
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
                    decoration: const InputDecoration(labelText: 'Expense Name'),
                  ),
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                  TextField(
                    controller: amountController,
                    decoration: const InputDecoration(labelText: 'Amount'),
                    keyboardType: TextInputType.number,
                  ),
                  TextField(
                    controller: categoryController,
                    decoration: const InputDecoration(labelText: 'Category'),
                  ),
                  DropdownButtonFormField<String>(
                    value: selectedPaymentMethod,
                    decoration: const InputDecoration(labelText: 'Payment Method'),
                    items: ['Cash', 'Bank Transfer', 'Credit Card', 'Other']
                        .map((method) => DropdownMenuItem(
                      value: method,
                      child: Text(method),
                    ))
                        .toList(),
                    onChanged: (value) => setState(() => selectedPaymentMethod = value!),
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
                  if (nameController.text.isEmpty || amountController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please fill in required fields')),
                    );
                    return;
                  }

                  setState(() {
                    isSubmitting = true;
                  });

                  final expense = Expense(
                    id: '',
                    name: nameController.text,
                    description: descriptionController.text,
                    amount: double.tryParse(amountController.text) ?? 0.0,
                    date: DateTime.now(),
                    category: categoryController.text,
                    paymentMethod: selectedPaymentMethod,
                    status: 'Paid',
                    createdAt: DateTime.now(),
                  );

                  await _addExpense(expense);

                  if (mounted) {
                    Navigator.pop(context);
                  }
                },
                child: const Text('Add Expense'),
              ),
            ],
          );
        },
      ),
    );
  }
}

  class Asset {
  final String id;
  final String name;
  final String description;
  final double value;
  final DateTime date;
  final String category;
  final double depreciation;
  final int usefulLife;
  final DateTime createdAt;

  Asset({
  required this.id,
  required this.name,
  required this.description,
  required this.value,
  required this.date,
  required this.category,
  required this.depreciation,
  required this.usefulLife,
  required this.createdAt,
  });
  }

  class Liability {
  final String id;
  final String name;
  final String description;
  final double amount;
  final DateTime date;
  final DateTime? dueDate;
  final double interestRate;
  final String status;
  final DateTime createdAt;

  Liability({
  required this.id,
  required this.name,
  required this.description,
  required this.amount,
  required this.date,
  this.dueDate,
  required this.interestRate,
  required this.status,
  required this.createdAt,
  });
  }

  class Expense {
  final String id;
  final String name;
  final String description;
  final double amount;
  final DateTime date;
  final String category;
  final String paymentMethod;
  final String status;
  final DateTime createdAt;

  Expense({
  required this.id,
  required this.name,
  required this.description,
  required this.amount,
  required this.date,
  required this.category,
  required this.paymentMethod,
  required this.status,
  required this.createdAt,
  });
  }

// Reuse your existing SalesOrder and Product classes from other modules
  class SalesOrder {
  final String id;
  final String customer;
  final DateTime date;
  final String status;
  final double total;
  final List<dynamic> items;
  final String customerId;
  final String reference;
  final String notes;

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
  });
  }

  class Product {
  final String id;
  final String name;
  final String category;
  final int stock;
  final double cost;
  final double price;
  final int lowStockThreshold;
  final String sku;
  final String unit;

  Product({
  required this.id,
  required this.name,
  required this.category,
  required this.stock,
  required this.cost,
  required this.price,
  required this.lowStockThreshold,
  required this.sku,
  required this.unit,
  });
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