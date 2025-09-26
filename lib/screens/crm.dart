import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/shared_data_service.dart';

class CrmModule extends StatefulWidget {
  const CrmModule({super.key});

  @override
  State<CrmModule> createState() => _CrmModuleState();
}

class _CrmModuleState extends State<CrmModule> {
  int _currentTabIndex = 0;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Lead> _leads = [];
  List<Customer> _customers = [];
  List<Interaction> _interactions = [];
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isCreatingLead = false;
  bool _isCreatingCustomer = false;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    final sharedData = Provider.of<SharedDataService>(context, listen: false);

    if (sharedData.customers.isEmpty) {
      await sharedData.loadSharedData();
    }

    await _loadCrmData();
  }

  Future<void> _loadCrmData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Load leads
      final leadsSnapshot = await _firestore
          .collection('crm')
          .doc('leads')
          .collection('leads')
          .orderBy('createdDate', descending: true)
          .limit(50)
          .get();

      _leads = leadsSnapshot.docs.map((doc) {
        final data = doc.data();
        return Lead(
          id: doc.id,
          name: data['name'] ?? '',
          company: data['company'] ?? '',
          email: data['email'] ?? '',
          phone: data['phone'] ?? '',
          status: data['status'] ?? 'New',
          source: data['source'] ?? '',
          value: (data['value'] ?? 0.0).toDouble(),
          createdDate: data['createdDate']?.toDate() ?? DateTime.now(),
          lastContact: data['lastContact']?.toDate() ?? DateTime.now(),
          notes: data['notes'] ?? '',
          followUpDate: data['followUpDate']?.toDate(),
          customerId: data['customerId'] ?? '', // NEW: Added customerId
        );
      }).toList();

      // Load interactions
      final interactionsSnapshot = await _firestore
          .collection('crm')
          .doc('activities')
          .collection('interactions')
          .orderBy('date', descending: true)
          .limit(50)
          .get();

      _interactions = interactionsSnapshot.docs.map((doc) {
        final data = doc.data();
        return Interaction(
          id: doc.id,
          type: data['type'] ?? '',
          contact: data['contact'] ?? '',
          date: data['date']?.toDate() ?? DateTime.now(),
          description: data['description'] ?? '',
          outcome: data['outcome'] ?? '',
          leadId: data['leadId'] ?? '',
        );
      }).toList();

      // Load customers from shared data
      final sharedData = Provider.of<SharedDataService>(context, listen: false);
      _customers = sharedData.customers;

    } catch (e) {
      print('Error loading CRM data: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error loading CRM data')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _createLead(Lead lead) async {
    setState(() {
      _isCreatingLead = true;
    });

    try {
      // Generate lead ID if not provided
      String leadId = lead.id;
      if (leadId.isEmpty) {
        final lastLead = await _firestore
            .collection('crm')
            .doc('leads')
            .collection('leads')
            .orderBy('createdDate', descending: true)
            .limit(1)
            .get();

        if (lastLead.docs.isNotEmpty) {
          final lastNumber = lastLead.docs.first.data()['id'] ?? '';
          if (lastNumber.startsWith('L')) {
            final lastNum = int.tryParse(lastNumber.substring(1)) ?? 0;
            leadId = 'L${(lastNum + 1).toString().padLeft(3, '0')}';
          } else {
            leadId = 'L001';
          }
        } else {
          leadId = 'L001';
        }
      }

      await _firestore
          .collection('crm')
          .doc('leads')
          .collection('leads')
          .doc(leadId)
          .set({
        'id': leadId,
        'name': lead.name,
        'company': lead.company,
        'email': lead.email,
        'phone': lead.phone,
        'status': lead.status,
        'source': lead.source,
        'value': lead.value,
        'notes': lead.notes,
        'customerId': lead.customerId, // NEW: Save customerId
        'createdDate': FieldValue.serverTimestamp(),
        'lastContact': FieldValue.serverTimestamp(),
        'followUpDate': lead.followUpDate,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lead created successfully')),
      );

      await _loadCrmData();
    } catch (e) {
      print('Error creating lead: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error creating lead')),
      );
    } finally {
      setState(() {
        _isCreatingLead = false;
      });
    }
  }

  Future<void> _editLead(Lead lead) async {
    setState(() {
      _isSaving = true;
    });

    try {
      await _firestore
          .collection('crm')
          .doc('leads')
          .collection('leads')
          .doc(lead.id)
          .update({
        'name': lead.name,
        'company': lead.company,
        'email': lead.email,
        'phone': lead.phone,
        'status': lead.status,
        'source': lead.source,
        'value': lead.value,
        'notes': lead.notes,
        'customerId': lead.customerId, // NEW: Update customerId
        'lastContact': FieldValue.serverTimestamp(),
        'followUpDate': lead.followUpDate,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lead updated successfully')),
      );

      await _loadCrmData();
    } catch (e) {
      print('Error updating lead: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error updating lead')),
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<void> _scheduleFollowUp(Lead lead, DateTime followUpDate, String notes) async {
    setState(() {
      _isSaving = true;
    });

    try {
      await _firestore
          .collection('crm')
          .doc('leads')
          .collection('leads')
          .doc(lead.id)
          .update({
        'followUpDate': followUpDate,
        'notes': notes.isNotEmpty ? notes : lead.notes,
        'lastContact': FieldValue.serverTimestamp(),
      });

      // Create interaction record
      await _firestore
          .collection('crm')
          .doc('activities')
          .collection('interactions')
          .add({
        'type': 'Follow-up Scheduled',
        'contact': lead.name,
        'date': FieldValue.serverTimestamp(),
        'description': 'Follow-up scheduled for ${DateFormat('MMM d, y').format(followUpDate)}',
        'outcome': 'Scheduled',
        'leadId': lead.id,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Follow-up scheduled successfully')),
      );

      await _loadCrmData();
    } catch (e) {
      print('Error scheduling follow-up: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error scheduling follow-up')),
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<void> _convertToCustomer(Lead lead) async {
    setState(() {
      _isSaving = true;
    });

    try {
      final sharedData = Provider.of<SharedDataService>(context, listen: false);

      // Generate customer ID
      String customerId = '';
      final lastCustomer = await _firestore
          .collection('customers')
          .orderBy('customerId', descending: true)
          .limit(1)
          .get();

      if (lastCustomer.docs.isNotEmpty) {
        final lastNumber = lastCustomer.docs.first.data()['customerId'] ?? '';
        if (lastNumber.startsWith('C')) {
          final lastNum = int.tryParse(lastNumber.substring(1)) ?? 0;
          customerId = 'C${(lastNum + 1).toString().padLeft(3, '0')}';
        } else {
          customerId = 'C001';
        }
      } else {
        customerId = 'C001';
      }

      // Create customer in Firestore
      final docRef = await _firestore
          .collection('customers')
          .add({
        'customerId': customerId, // NEW: Add customerId
        'name': lead.name,
        'email': lead.email,
        'phone': lead.phone,
        'address': '',
        'type': 'Regular',
        'status': 'Active',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Add to shared data
      final newCustomer = Customer(
        id: docRef.id,
        customerId: customerId, // NEW: Add customerId
        name: lead.name,
        email: lead.email,
        phone: lead.phone,
        address: '',
        type: 'Regular',
        status: 'Active',
      );
      sharedData.addCustomer(newCustomer);

      // Update lead status to "Converted"
      await _firestore
          .collection('crm')
          .doc('leads')
          .collection('leads')
          .doc(lead.id)
          .update({
        'status': 'Converted',
        'customerId': customerId, // NEW: Add customerId to lead
        'lastContact': FieldValue.serverTimestamp(),
      });

      // Create interaction record
      await _firestore
          .collection('crm')
          .doc('activities')
          .collection('interactions')
          .add({
        'type': 'Conversion',
        'contact': lead.name,
        'date': FieldValue.serverTimestamp(),
        'description': 'Lead converted to customer',
        'outcome': 'Converted',
        'leadId': lead.id,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lead converted to customer successfully')),
      );

      await _loadCrmData();
    } catch (e) {
      print('Error converting lead: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error converting lead')),
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<void> _deleteLead(String leadId) async {
    final confirmed = await _showConfirmationDialog(
        'Delete Lead',
        'Are you sure you want to delete this lead? This action cannot be undone.'
    );

    if (!confirmed) return;

    setState(() {
      _isSaving = true;
    });

    try {
      await _firestore
          .collection('crm')
          .doc('leads')
          .collection('leads')
          .doc(leadId)
          .delete();

      // Also delete related interactions
      final interactionsSnapshot = await _firestore
          .collection('crm')
          .doc('activities')
          .collection('interactions')
          .where('leadId', isEqualTo: leadId)
          .get();

      for (final doc in interactionsSnapshot.docs) {
        await doc.reference.delete();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lead deleted successfully')),
      );

      await _loadCrmData();
    } catch (e) {
      print('Error deleting lead: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error deleting lead')),
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<void> _deleteCustomer(String customerId, SharedDataService sharedData) async {
    final confirmed = await _showConfirmationDialog(
        'Delete Customer',
        'Are you sure you want to delete this customer? This action cannot be undone.'
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
        const SnackBar(content: Text('Customer deleted successfully')),
      );

      await _loadCrmData();
    } catch (e) {
      print('Error deleting customer: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error deleting customer')),
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

    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading CRM data...'),
            ],
          ),
        ),
      );
    }

    final newLeads = _leads.where((lead) => lead.status == 'New').length;
    final contactedLeads = _leads.where((lead) => lead.status == 'Contacted').length;
    final qualifiedLeads = _leads.where((lead) => lead.status == 'Qualified').length;
    final totalPipelineValue = _leads.fold(0.0, (sum, lead) => sum + lead.value);

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('CRM Module'),
        backgroundColor: Colors.purple[800],
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
            onPressed: _loadCrmData,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildCrmOverview(newLeads, contactedLeads, qualifiedLeads, totalPipelineValue),
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
        backgroundColor: Colors.purple[800],
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
            leading: const Icon(Icons.person_add),
            title: const Text('Add New Lead'),
            onTap: () {
              Navigator.pop(context);
              _addNewLead();
            },
          ),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Add New Customer'),
            onTap: () {
              Navigator.pop(context);
              _showAddCustomerDialog(sharedData);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCrmOverview(int newLeads, int contactedLeads, int qualifiedLeads, double pipelineValue) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildCrmMetric('New Leads', newLeads, Icons.person_add, Colors.blue),
          _buildCrmMetric('Contacted', contactedLeads, Icons.phone, Colors.orange),
          _buildCrmMetric('Qualified', qualifiedLeads, Icons.thumb_up, Colors.green),
          _buildCrmMetric('Pipeline', pipelineValue, Icons.trending_up, Colors.purple, isCurrency: true),
        ],
      ),
    );
  }

  Widget _buildCrmMetric(String label, dynamic value, IconData icon, Color color, {bool isCurrency = false}) {
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
          isCurrency ? '${(value as double).toStringAsFixed(0)} FCFA' : value.toString(),
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
          _buildTabButton('Leads', 1),
          _buildTabButton('Customers', 2),
          _buildTabButton('Activities', 3),
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

  Widget _buildCurrentTab(SharedDataService sharedData) {
    switch (_currentTabIndex) {
      case 0:
        return _buildDashboardTab();
      case 1:
        return _buildLeadsTab();
      case 2:
        return _buildCustomersTab(sharedData);
      case 3:
        return _buildActivitiesTab();
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
            'Sales Pipeline',
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
                ColumnSeries<PipelineData, String>(
                  dataSource: [
                    PipelineData('New', 25000),
                    PipelineData('Contacted', 18000),
                    PipelineData('Qualified', 35000),
                    PipelineData('Proposal', 22000),
                    PipelineData('Negotiation', 28000),
                    PipelineData('Won', 45000),
                  ],
                  xValueMapper: (PipelineData data, _) => data.stage,
                  yValueMapper: (PipelineData data, _) => data.value,
                  color: Colors.purple,
                )
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Recent Activities',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ..._interactions.take(3).map((interaction) => _buildActivityCard(interaction)),
        ],
      ),
    );
  }

  Widget _buildLeadsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Leads',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        ..._leads.map((lead) => _buildLeadCard(lead)),
      ],
    );
  }

  Widget _buildLeadCard(Lead lead) {
    Color statusColor;
    IconData statusIcon;

    switch (lead.status) {
      case 'New':
        statusColor = Colors.blue;
        statusIcon = Icons.new_releases;
        break;
      case 'Contacted':
        statusColor = Colors.orange;
        statusIcon = Icons.phone;
        break;
      case 'Qualified':
        statusColor = Colors.green;
        statusIcon = Icons.thumb_up;
        break;
      case 'Proposal Sent':
        statusColor = Colors.purple;
        statusIcon = Icons.description;
        break;
      case 'Negotiation':
        statusColor = Colors.deepOrange;
        statusIcon = Icons.handshake;
        break;
      case 'Converted':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help;
    }

    return GestureDetector(
      onLongPress: () => _deleteLead(lead.id),
      child: Card(
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
                    lead.name,
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
                          lead.status,
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
                lead.company,
                style: TextStyle(
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildLeadDetail(Icons.email, lead.email),
                  const SizedBox(width: 16),
                  _buildLeadDetail(Icons.phone, lead.phone),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Potential Value',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '${lead.value.toStringAsFixed(0)} FCFA',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (lead.followUpDate != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.calendar_today, size: 14, color: Colors.blue),
                    const SizedBox(width: 4),
                    Text(
                      'Follow-up: ${DateFormat('MMM d, y').format(lead.followUpDate!)}',
                      style: TextStyle(
                        color: Colors.blue[700],
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Last contact: ${DateFormat('MMM d').format(lead.lastContact)}',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 12,
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.phone, size: 18),
                        onPressed: () => _callLead(lead),
                      ),
                      IconButton(
                        icon: const Icon(Icons.email, size: 18),
                        onPressed: () => _emailLead(lead),
                      ),
                      IconButton(
                        icon: const Icon(Icons.more_vert, size: 18),
                        onPressed: () => _showLeadOptions(lead),
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

  Widget _buildLeadDetail(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  void _callLead(Lead lead) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Calling ${lead.name} at ${lead.phone}...')),
    );
  }

  void _emailLead(Lead lead) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Emailing ${lead.name} at ${lead.email}...')),
    );
  }

  void _showLeadOptions(Lead lead) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('Edit Lead'),
            onTap: () {
              Navigator.pop(context);
              _showEditLeadDialog(lead);
            },
          ),
          ListTile(
            leading: const Icon(Icons.calendar_today),
            title: const Text('Schedule Follow-up'),
            onTap: () {
              Navigator.pop(context);
              _showScheduleFollowUpDialog(lead);
            },
          ),
          if (lead.status != 'Converted')
            ListTile(
              leading: const Icon(Icons.person_add),
              title: const Text('Convert to Customer'),
              onTap: () {
                Navigator.pop(context);
                _showConvertToCustomerDialog(lead);
              },
            ),
        ],
      ),
    );
  }

  void _showEditLeadDialog(Lead lead) {
    final nameController = TextEditingController(text: lead.name);
    final companyController = TextEditingController(text: lead.company);
    final emailController = TextEditingController(text: lead.email);
    final phoneController = TextEditingController(text: lead.phone);
    final valueController = TextEditingController(text: lead.value.toString());
    final notesController = TextEditingController(text: lead.notes);

    String selectedStatus = lead.status;
    String selectedSource = lead.source;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Edit Lead'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name')),
                  TextField(controller: companyController, decoration: const InputDecoration(labelText: 'Company')),
                  TextField(controller: emailController, decoration: const InputDecoration(labelText: 'Email')),
                  TextField(controller: phoneController, decoration: const InputDecoration(labelText: 'Phone')),
                  TextField(controller: valueController, decoration: const InputDecoration(labelText: 'Value'), keyboardType: TextInputType.number),
                  TextField(controller: notesController, decoration: const InputDecoration(labelText: 'Notes'), maxLines: 2),

                  DropdownButtonFormField<String>(
                    value: selectedStatus,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: ['New', 'Contacted', 'Qualified', 'Proposal Sent', 'Negotiation', 'Converted']
                        .map((status) => DropdownMenuItem(value: status, child: Text(status)))
                        .toList(),
                    onChanged: (value) => setState(() => selectedStatus = value!),
                  ),

                  DropdownButtonFormField<String>(
                    value: selectedSource,
                    decoration: const InputDecoration(labelText: 'Source'),
                    items: ['Website', 'Referral', 'Trade Show', 'Cold Call', 'Social Media']
                        .map((source) => DropdownMenuItem(value: source, child: Text(source)))
                        .toList(),
                    onChanged: (value) => setState(() => selectedSource = value!),
                  ),
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
                  final updatedLead = Lead(
                    id: lead.id,
                    name: nameController.text,
                    company: companyController.text,
                    email: emailController.text,
                    phone: phoneController.text,
                    status: selectedStatus,
                    source: selectedSource,
                    value: double.tryParse(valueController.text) ?? 0.0,
                    createdDate: lead.createdDate,
                    lastContact: DateTime.now(),
                    notes: notesController.text,
                    followUpDate: lead.followUpDate,
                    customerId: lead.customerId,
                  );
                  await _editLead(updatedLead);
                  Navigator.pop(context);
                },
                child: const Text('Update Lead'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showScheduleFollowUpDialog(Lead lead) {
    DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
    TimeOfDay selectedTime = TimeOfDay.now();
    final notesController = TextEditingController(text: lead.notes);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Schedule Follow-up'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: Text('Date: ${DateFormat('MMM d, y').format(selectedDate)}'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (date != null) {
                        setState(() => selectedDate = date);
                      }
                    },
                  ),
                  ListTile(
                    title: Text('Time: ${selectedTime.format(context)}'),
                    trailing: const Icon(Icons.access_time),
                    onTap: () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: selectedTime,
                      );
                      if (time != null) {
                        setState(() => selectedTime = time);
                      }
                    },
                  ),
                  TextField(
                    controller: notesController,
                    decoration: const InputDecoration(labelText: 'Notes'),
                    maxLines: 3,
                  ),
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
                  final followUpDateTime = DateTime(
                    selectedDate.year,
                    selectedDate.month,
                    selectedDate.day,
                    selectedTime.hour,
                    selectedTime.minute,
                  );
                  await _scheduleFollowUp(lead, followUpDateTime, notesController.text);
                  Navigator.pop(context);
                },
                child: const Text('Schedule'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showConvertToCustomerDialog(Lead lead) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Convert to Customer'),
        content: Text('Are you sure you want to convert ${lead.name} to a customer?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _convertToCustomer(lead);
              Navigator.pop(context);
            },
            child: const Text('Convert'),
          ),
        ],
      ),
    );
  }

  void _addNewLead() {
    final nameController = TextEditingController();
    final companyController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    final valueController = TextEditingController();
    final notesController = TextEditingController();

    String selectedStatus = 'New';
    String selectedSource = 'Website';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Add New Lead'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name')),
                  TextField(controller: companyController, decoration: const InputDecoration(labelText: 'Company')),
                  TextField(controller: emailController, decoration: const InputDecoration(labelText: 'Email')),
                  TextField(controller: phoneController, decoration: const InputDecoration(labelText: 'Phone')),
                  TextField(controller: valueController, decoration: const InputDecoration(labelText: 'Value'), keyboardType: TextInputType.number),
                  TextField(controller: notesController, decoration: const InputDecoration(labelText: 'Notes'), maxLines: 2),

                  DropdownButtonFormField<String>(
                    value: selectedStatus,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: ['New', 'Contacted', 'Qualified', 'Proposal Sent', 'Negotiation']
                        .map((status) => DropdownMenuItem(value: status, child: Text(status)))
                        .toList(),
                    onChanged: (value) => setState(() => selectedStatus = value!),
                  ),

                  DropdownButtonFormField<String>(
                    value: selectedSource,
                    decoration: const InputDecoration(labelText: 'Source'),
                    items: ['Website', 'Referral', 'Trade Show', 'Cold Call', 'Social Media']
                        .map((source) => DropdownMenuItem(value: source, child: Text(source)))
                        .toList(),
                    onChanged: (value) => setState(() => selectedSource = value!),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              if (_isCreatingLead)
                const CircularProgressIndicator()
              else
                ElevatedButton(
                  onPressed: () async {
                    final lead = Lead(
                      id: '',
                      name: nameController.text,
                      company: companyController.text,
                      email: emailController.text,
                      phone: phoneController.text,
                      status: selectedStatus,
                      source: selectedSource,
                      value: double.tryParse(valueController.text) ?? 0.0,
                      createdDate: DateTime.now(),
                      lastContact: DateTime.now(),
                      notes: notesController.text,
                      customerId: '', // Will be generated on conversion
                    );
                    await _createLead(lead);
                    Navigator.pop(context);
                  },
                  child: const Text('Add Lead'),
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

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Customer'),
        content: SingleChildScrollView(
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (_isCreatingCustomer)
            const CircularProgressIndicator()
          else
            ElevatedButton(
              onPressed: () async {
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
                Navigator.pop(context);
              },
              child: const Text('Add Customer'),
            ),
        ],
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
        const SnackBar(content: Text('Customer added successfully')),
      );
    } catch (e) {
      print('Error creating customer: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error creating customer')),
      );
    } finally {
      setState(() {
        _isCreatingCustomer = false;
      });
    }
  }

  Widget _buildCustomersTab(SharedDataService sharedData) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Customers',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        ..._customers.map((customer) => _buildCustomerCard(customer, sharedData)),
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
            backgroundColor: _getCustomerColor(customer.status),
            child: Text(
              customer.name[0],
              style: const TextStyle(color: Colors.white),
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
              color: _getCustomerColor(customer.status).withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              customer.status,
              style: TextStyle(
                color: _getCustomerColor(customer.status),
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

  Color _getCustomerColor(String status) {
    return status == 'Active' ? Colors.green : Colors.grey;
  }

  void _viewCustomerDetails(Customer customer) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CustomerDetailScreen(customer: customer),
      ),
    );
  }

  Widget _buildActivitiesTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Recent Activities',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        ..._interactions.map((interaction) => _buildActivityCard(interaction)),
      ],
    );
  }

  Widget _buildActivityCard(Interaction interaction) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _getActivityColor(interaction.type).withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(
            _getActivityIcon(interaction.type),
            color: _getActivityColor(interaction.type),
          ),
        ),
        title: Text(
          interaction.contact,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(interaction.description),
            const SizedBox(height: 4),
            Text(
              '${interaction.type} • ${DateFormat('MMM d, h:mm a').format(interaction.date)}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Outcome: ${interaction.outcome}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.green[700],
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getActivityColor(String type) {
    switch (type) {
      case 'Phone Call':
        return Colors.blue;
      case 'Email':
        return Colors.green;
      case 'Meeting':
        return Colors.orange;
      case 'Proposal':
        return Colors.purple;
      case 'Follow-up Scheduled':
        return Colors.blue;
      case 'Conversion':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getActivityIcon(String type) {
    switch (type) {
      case 'Phone Call':
        return Icons.phone;
      case 'Email':
        return Icons.email;
      case 'Meeting':
        return Icons.people;
      case 'Proposal':
        return Icons.description;
      case 'Follow-up Scheduled':
        return Icons.calendar_today;
      case 'Conversion':
        return Icons.person_add;
      default:
        return Icons.event;
    }
  }
}

class Lead {
  final String id;
  final String name;
  final String company;
  final String email;
  final String phone;
  final String status;
  final String source;
  final double value;
  final DateTime createdDate;
  final DateTime lastContact;
  final String notes;
  final DateTime? followUpDate;
  final String customerId; // NEW: Added customerId

  Lead({
    required this.id,
    required this.name,
    required this.company,
    required this.email,
    required this.phone,
    required this.status,
    required this.source,
    required this.value,
    required this.createdDate,
    required this.lastContact,
    this.notes = '',
    this.followUpDate,
    required this.customerId, // NEW: Added customerId
  });
}

class Interaction {
  final String id;
  final String type;
  final String contact;
  final DateTime date;
  final String description;
  final String outcome;
  final String leadId;

  Interaction({
    this.id = '',
    required this.type,
    required this.contact,
    required this.date,
    required this.description,
    required this.outcome,
    required this.leadId,
  });
}

class PipelineData {
  final String stage;
  final double value;

  PipelineData(this.stage, this.value);
}

// Customer Detail Screen
class CustomerDetailScreen extends StatelessWidget {
  final Customer customer;

  const CustomerDetailScreen({super.key, required this.customer});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(customer.name),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCustomerHeader(),
            const SizedBox(height: 24),
            _buildContactInfo(),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          backgroundColor: Colors.purple,
          radius: 30,
          child: Text(
            customer.name[0],
            style: const TextStyle(
              fontSize: 24,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                customer.name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                customer.type,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _getStatusColor(customer.status).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  customer.status,
                  style: TextStyle(
                    color: _getStatusColor(customer.status),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContactInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Contact Information',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        _buildContactItem(Icons.email, customer.email),
        _buildContactItem(Icons.phone, customer.phone),
        _buildContactItem(Icons.location_on, customer.address),
        _buildContactItem(Icons.credit_card, 'ID: ${customer.customerId}'),
      ],
    );
  }

  Widget _buildContactItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey),
          const SizedBox(width: 16),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    return status == 'Active' ? Colors.green : Colors.grey;
  }
}