import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rbm/screens/human_resource.dart';
import 'package:rbm/screens/sales_screen.dart';
import '../services/auth_service.dart';
import '../services/dashboard_service.dart';
import '../services/shared_data_service.dart';
import 'accounting_screen.dart';
import 'inventory_screen.dart';
import 'invoices.dart';
import 'crm.dart';
import 'login_screen.dart';
import 'settings_screen.dart';
import 'managers_screen.dart'; // Add this import

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  final DashboardService _dashboardService = DashboardService();
  Map<String, dynamic> _dashboardData = {};
  bool _isLoading = true;
  Map<String, dynamic>? _currentUser;

  @override
  void initState() {
    super.initState();
    _initializeUser();
  }

  Future<void> _initializeUser() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    _currentUser = await authService.getCurrentUser();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final sharedData = Provider.of<SharedDataService>(context, listen: false);
      await sharedData.loadSharedData();

      final results = await Future.wait([
        _dashboardService.getInventoryStats(sharedData),
        _dashboardService.getPendingOrdersCount(),
        _dashboardService.getNetIncome(),
        _dashboardService.getTotalCustomers(),
        _dashboardService.getWorkersAttendance(),
        _dashboardService.getPendingInvoicesCount(),
        _dashboardService.getTotalRevenue(),
        _dashboardService.getTotalOrdersCount(),
      ]);

      setState(() {
        _dashboardData = {
          'inventory': results[0],
          'pendingOrders': results[1],
          'netIncome': results[2],
          'totalCustomers': results[3],
          'attendance': results[4],
          'pendingInvoices': results[5],
          'totalRevenue': results[6],
          'totalOrders': results[7],
        };
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading dashboard data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _logout() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    await authService.logout();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: null, // Remove app bar as requested
      body: Column(
        children: [
          // Fixed header image (25% height, not scrollable)
          Container(
            height: MediaQuery.of(context).size.height * 0.25,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
              child: Image.asset(
                'assets/icons/rbmice.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.blue[50],
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.image, size: 64, color: Colors.blue[800]),
                          const SizedBox(height: 8),
                          Text(
                            'RBM Ice',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[800],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // Admin actions (only visible to admin)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _currentUser?['role'] == 'admin'
                        ? 'Welcome back, Admin!'
                        : 'Welcome, ${_currentUser?['username'] ?? 'Manager'}!',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                  Row(
                    children: [
                      if (_currentUser?['role'] == 'admin') ElevatedButton.icon(
                         onPressed: () {
                           Navigator.push(
                             context,
                             MaterialPageRoute(builder: (context) => const ManagersScreen()),
                           );
                         }, label: Icon(Icons.people),
                         ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _logout,
                        icon: const Icon(Icons.logout, color: Colors.red),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          // Dashboard content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TwoColumnDashboard(
              dashboardData: _dashboardData,
              userRole: _currentUser?['role'] ?? 'manager',
            ),
          ),
        ],
      ),
    );
  }
}

class TwoColumnDashboard extends StatelessWidget {
  final Map<String, dynamic> dashboardData;
  final String userRole;

  const TwoColumnDashboard({
    super.key,
    required this.dashboardData,
    required this.userRole,
  });

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: const ScrollBehavior().copyWith(overscroll: false),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                if (width > 600) {
                  return TwoColumnLayout(dashboardData: dashboardData, userRole: userRole);
                } else {
                  return SingleColumnLayout(dashboardData: dashboardData, userRole: userRole);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class TwoColumnLayout extends StatelessWidget {
  final Map<String, dynamic> dashboardData;
  final String userRole;

  const TwoColumnLayout({super.key, required this.dashboardData, required this.userRole});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            children: [
              ModuleCard(
                title: 'Inventory',
                icon: Icons.inventory,
                color: Colors.green,
                description: 'Track stock levels and movements',
                stats: '${(dashboardData['inventory'] as Map<String, dynamic>?)?['totalProducts'] ?? 0} items, ${(dashboardData['inventory'] as Map<String, dynamic>?)?['lowStockItems'] ?? 0} low stock',
                onPressed: (){
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const InventoryModule(),
                    ),
                  );
                },
                userRole: userRole,
              ),
              const SizedBox(height: 16),
              ModuleCard(
                title: 'Sales',
                icon: Icons.shopping_cart,
                color: Colors.blue,
                description: 'Manage orders, quotations, and customers',
                stats: '${dashboardData['pendingOrders'] ?? 0} pending orders',
                onPressed: (){
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SalesModule(),
                    ),
                  );
                },
                userRole: userRole,
              ),
              const SizedBox(height: 16),
              ModuleCard(
                title: 'Invoices',
                icon: Icons.receipt,
                color: Colors.purpleAccent,
                description: 'Manage invoices and payments',
                stats: '${dashboardData['pendingInvoices'] ?? 0} pending invoices',
                onPressed: (){
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const InvoicesModule(),
                    ),
                  );
                },
                userRole: userRole,
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            children: [
              ModuleCard(
                title: 'Accounting',
                icon: Icons.account_balance,
                color: Colors.purple,
                description: 'Financial management and reports',
                stats: 'Net Income: ${(dashboardData['netIncome'] ?? 0.0).toStringAsFixed(0)} FCFA',
                onPressed: (){
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AccountingModule(),
                    ),
                  );
                },
                userRole: userRole,
              ),
              const SizedBox(height: 16),
              ModuleCard(
                title: 'CRM',
                icon: Icons.people,
                color: Colors.orange,
                description: 'Manage customer relationships',
                stats: '${dashboardData['totalCustomers'] ?? 0} customers',
                onPressed: (){
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CrmModule(),
                    ),
                  );
                },
                userRole: userRole,
              ),
              const SizedBox(height: 16),
              ModuleCard(
                title: 'Human Resource',
                icon: Icons.person,
                color: Colors.teal,
                description: 'Manage employees and attendance',
                stats: '${(dashboardData['attendance'] as Map<String, dynamic>?)?['present'] ?? 0} present, ${(dashboardData['attendance'] as Map<String, dynamic>?)?['absent'] ?? 0} absent',
                onPressed: (){
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const HumanResourceModule(),
                    ),
                  );
                },
                userRole: userRole,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class SingleColumnLayout extends StatelessWidget {
  final Map<String, dynamic> dashboardData;
  final String userRole;

  const SingleColumnLayout({super.key, required this.dashboardData, required this.userRole});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ModuleCard(
          title: 'Inventory',
          icon: Icons.inventory,
          color: Colors.green,
          description: 'Track stock levels and movements',
          stats: '${(dashboardData['inventory'] as Map<String, dynamic>?)?['totalProducts'] ?? 0} items, ${(dashboardData['inventory'] as Map<String, dynamic>?)?['lowStockItems'] ?? 0} low stock',
          onPressed: (){
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const InventoryModule(),
              ),
            );
          },
          userRole: userRole,
        ),
        const SizedBox(height: 16),
        ModuleCard(
          title: 'Sales',
          icon: Icons.shopping_cart,
          color: Colors.blue,
          description: 'Manage orders, quotations, and customers',
          stats: '${dashboardData['pendingOrders'] ?? 0} pending orders',
          onPressed: (){
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const SalesModule(),
              ),
            );
          },
          userRole: userRole,
        ),
        const SizedBox(height: 16),
        ModuleCard(
          title: 'Invoices',
          icon: Icons.receipt,
          color: Colors.purpleAccent,
          description: 'Manage invoices and payments',
          stats: '${dashboardData['pendingInvoices'] ?? 0} pending invoices',
          onPressed: (){
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const InvoicesModule(),
              ),
            );
          },
          userRole: userRole,
        ),
        const SizedBox(height: 16),
        ModuleCard(
          title: 'Accounting',
          icon: Icons.account_balance,
          color: Colors.purple,
          description: 'Financial management and reports',
          stats: 'Net Income: ${(dashboardData['netIncome'] ?? 0.0).toStringAsFixed(0)} FCFA',
          onPressed: (){
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const AccountingModule(),
              ),
            );
          },
          userRole: userRole,
        ),
        const SizedBox(height: 16),
        ModuleCard(
          title: 'CRM',
          icon: Icons.people,
          color: Colors.orange,
          description: 'Manage customer relationships',
          stats: '${dashboardData['totalCustomers'] ?? 0} customers',
          onPressed: (){
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const CrmModule(),
              ),
            );
          },
          userRole: userRole,
        ),
        const SizedBox(height: 16),
        ModuleCard(
          title: 'Human Resource',
          icon: Icons.person,
          color: Colors.teal,
          description: 'Manage employees and attendance',
          stats: '${(dashboardData['attendance'] as Map<String, dynamic>?)?['present'] ?? 0} present, ${(dashboardData['attendance'] as Map<String, dynamic>?)?['absent'] ?? 0} absent',
          onPressed: (){
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const HumanResourceModule(),
              ),
            );
          },
          userRole: userRole,
        ),
      ],
    );
  }
}

class ModuleCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final String description;
  final String stats;
  final VoidCallback onPressed;
  final String userRole;

  const ModuleCard({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.description,
    required this.stats,
    required this.onPressed,
    required this.userRole,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              description,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                stats,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[700],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onPressed,
                child: const Text('Open Module →'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}