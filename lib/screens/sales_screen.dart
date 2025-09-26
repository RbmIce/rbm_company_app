// sales_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/sales_model.dart';
import '../services/sales_data_provider.dart';

class SalesModule extends StatefulWidget {
  const SalesModule({super.key});

  @override
  State<SalesModule> createState() => _SalesModuleState();
}

class _SalesModuleState extends State<SalesModule> {
  int _currentTabIndex = 0;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Data streams automatically initialize
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Sales Module'),
        backgroundColor: Colors.blue[800],
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<SalesDataProvider>().notifyListeners();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSalesOverview(),
          const SizedBox(height: 16),
          _buildTabBar(),
          Expanded(
            child: _buildCurrentTab(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddMenu(context),
        backgroundColor: Colors.blue[800],
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildSalesOverview() {
    return StreamBuilder<List<SalesOrder>>(
      stream: context.read<SalesDataProvider>().ordersStream,
      builder: (context, ordersSnapshot) {
        final orders = ordersSnapshot.data ?? [];
        final totalSales = orders.fold(0.0, (sum, order) => sum + order.total);
        final pendingOrders = orders.where((order) => order.status == 'Pending').length;
        final deliveredOrders = orders.where((order) => order.status == 'Delivered').length;

        return Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSalesMetric('Total Sales', totalSales, Icons.attach_money, Colors.green, isCurrency: true),
              _buildSalesMetric('Pending', pendingOrders.toDouble(), Icons.pending_actions, Colors.orange),
              _buildSalesMetric('Delivered', deliveredOrders.toDouble(), Icons.local_shipping, Colors.blue),
            ],
          ),
        );
      },
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

  Widget _buildCurrentTab() {
    switch (_currentTabIndex) {
      case 0:
        return _buildOrdersTab();
      case 1:
        return _buildQuotationsTab();
      default:
        return _buildOrdersTab();
    }
  }

  Widget _buildOrdersTab() {
    return StreamBuilder<List<SalesOrder>>(
      stream: context.read<SalesDataProvider>().ordersStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text('Error: ${snapshot.error}'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    context.read<SalesDataProvider>().notifyListeners();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        final orders = snapshot.data ?? [];

        if (orders.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shopping_cart, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('No sales orders found'),
                SizedBox(height: 8),
                Text('Create your first order using the + button'),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: orders.length,
          itemBuilder: (context, index) => _buildOrderCard(orders[index]),
        );
      },
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

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            const SizedBox(height: 8),
            Text(
              'Customer: ${order.customer}',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            if (order.items.isNotEmpty) ...[
              const Text(
                'Items:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              ...order.items.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.0),
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
                  ],
                ),
              )),
              const Divider(),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total:',
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
            const SizedBox(height: 8),
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
                    if (order.status == 'Pending')
                      IconButton(
                        icon: const Icon(Icons.check, size: 18),
                        onPressed: () => _updateOrderStatus(order.id, 'Processing'),
                        tooltip: 'Mark as Processing',
                      ),
                    if (order.status == 'Processing')
                      IconButton(
                        icon: const Icon(Icons.local_shipping, size: 18),
                        onPressed: () => _updateOrderStatus(order.id, 'Delivered'),
                        tooltip: 'Mark as Delivered',
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuotationsTab() {
    return StreamBuilder<List<Quotation>>(
      stream: context.read<SalesDataProvider>().quotationsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text('Error: ${snapshot.error}'),
              ],
            ),
          );
        }

        final quotations = snapshot.data ?? [];

        if (quotations.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.description, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('No quotations found'),
                SizedBox(height: 8),
                Text('Create your first quotation using the + button'),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: quotations.length,
          itemBuilder: (context, index) => _buildQuotationCard(quotations[index]),
        );
      },
    );
  }

  Widget _buildQuotationCard(Quotation quotation) {
    final isExpired = quotation.expiryDate.isBefore(DateTime.now());
    Color statusColor = isExpired ? Colors.red : Colors.orange;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.description, color: statusColor),
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
    );
  }

  void _showAddMenu(BuildContext context) {
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
              _showCreateOrderDialog();
            },
          ),
          ListTile(
            leading: const Icon(Icons.description),
            title: const Text('Create Quotation'),
            onTap: () {
              Navigator.pop(context);
              _showCreateQuotationDialog();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _updateOrderStatus(String orderId, String status) async {
    try {
      await context.read<SalesDataProvider>().updateOrderStatus(orderId, status);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Order status updated to $status')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating status: $e')),
      );
    }
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
              leading: const Icon(Icons.shopping_cart),
              title: const Text('Convert to Order'),
              onTap: () {
                Navigator.pop(context);
                _convertQuotationToOrder(quotation);
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

  void _showCreateOrderDialog() {
    // Add your create order dialog implementation here
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Order'),
        content: const Text('Order creation dialog will be implemented here.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              // Implement order creation logic
              Navigator.pop(context);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showCreateQuotationDialog() {
    // Add your create quotation dialog implementation here
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Quotation'),
        content: const Text('Quotation creation dialog will be implemented here.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              // Implement quotation creation logic
              Navigator.pop(context);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _convertQuotationToOrder(Quotation quotation) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Convert to Order'),
        content: Text('Convert quotation ${quotation.reference} to sales order?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              // Implement conversion logic
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Quotation converted to order')),
              );
            },
            child: const Text('Convert'),
          ),
        ],
      ),
    );
  }
}