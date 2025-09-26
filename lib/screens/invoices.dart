import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'dart:io';
import '../services/shared_data_service.dart';
import 'package:flutter/services.dart';
import 'dart:typed_data';

class InvoicesModule extends StatefulWidget {
  const InvoicesModule({super.key});

  @override
  State<InvoicesModule> createState() => _InvoicesModuleState();
}

class _InvoicesModuleState extends State<InvoicesModule> {
  int _currentTabIndex = 0;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Invoice> _invoices = [];
  List<Customer> _clients = [];
  List<Product> _products = [];
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isCreatingInvoice = false;
  final TextEditingController _searchController = TextEditingController();

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

    await _loadInvoices();
    await _loadClientsAndProducts();
  }

  Future<void> _loadClientsAndProducts() async {
    final sharedData = Provider.of<SharedDataService>(context, listen: false);
    _clients = sharedData.customers;
    _products = sharedData.products;
  }

  Future<void> _loadInvoices() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // MODIFIED: Use collectionGroup to search all customer invoice collections
      final invoicesSnapshot = await _firestore
          .collectionGroup('customer_invoices')
          .orderBy('date', descending: true)
          .limit(100)
          .get();

      _invoices = invoicesSnapshot.docs.map((doc) {
        final data = doc.data();
        return Invoice(
          id: doc.id,
          number: data['number'] ?? '',
          customer: data['customer'] ?? '',
          customerId: data['customerId'] ?? '',
          customerEmail: data['customerEmail'] ?? '',
          customerPhone: data['customerPhone'] ?? '',
          customerAddress: data['customerAddress'] ?? '',
          date: data['date']?.toDate() ?? DateTime.now(),
          dueDate: data['dueDate']?.toDate() ?? DateTime.now(),
          amount: (data['amount'] ?? 0.0).toDouble(),
          tax: (data['tax'] ?? 0.0).toDouble(),
          total: (data['total'] ?? 0.0).toDouble(),
          status: data['status'] ?? 'Pending',
          items: List<InvoiceItem>.from((data['items'] ?? []).map((item) => InvoiceItem(
            description: item['description'] ?? '',
            quantity: (item['quantity'] ?? 0).toInt(),
            unitPrice: (item['unitPrice'] ?? 0.0).toDouble(),
            total: (item['total'] ?? 0.0).toDouble(),
          ))),
          payments: List<Payment>.from((data['payments'] ?? []).map((payment) => Payment(
            date: payment['date']?.toDate() ?? DateTime.now(),
            amount: (payment['amount'] ?? 0.0).toDouble(),
            method: payment['method'] ?? '',
            reference: payment['reference'] ?? '',
          ))),
          notes: data['notes'] ?? '',
          terms: data['terms'] ?? '',
          taxId: data['taxId'] ?? '',
          discount: (data['discount'] ?? 0.0).toDouble(),
          fees: (data['fees'] ?? 0.0).toDouble(),
          createdAt: data['createdAt']?.toDate(),
          updatedAt: data['updatedAt']?.toDate(),
        );
      }).toList();

      // Update status for overdue invoices
      _updateOverdueInvoices();

    } catch (e) {
      print('Error loading invoices: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error loading invoices')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _updateOverdueInvoices() {
    final now = DateTime.now();
    for (final invoice in _invoices) {
      if (invoice.status == 'Pending' && invoice.dueDate.isBefore(now)) {
        invoice.status = 'Overdue';
      }
    }
  }

  Future<void> _createInvoice(Invoice invoice) async {
    setState(() {
      _isCreatingInvoice = true;
    });

    try {
      // Generate invoice number if not provided
      String invoiceNumber = invoice.number;
      if (invoiceNumber.isEmpty) {
        // MODIFIED: Search all customer invoice collections for the highest number
        final invoicesSnapshot = await _firestore
            .collectionGroup('customer_invoices')
            .orderBy('number', descending: true)
            .limit(1)
            .get();

        if (invoicesSnapshot.docs.isNotEmpty) {
          final lastNumber = invoicesSnapshot.docs.first.data()['number'] ?? '';
          if (lastNumber.startsWith('INV-')) {
            final lastNum = int.tryParse(lastNumber.split('-').last) ?? 0;
            invoiceNumber = 'INV-${(lastNum + 1).toString().padLeft(4, '0')}';
          } else {
            invoiceNumber = 'INV-0001';
          }
        } else {
          invoiceNumber = 'INV-0001';
        }
      }

      // MODIFIED: Save invoice in invoices/customerId/customer_invoices structure
      final customerInvoicesRef = _firestore
          .collection('invoices')
          .doc(invoice.customerId)
          .collection('customer_invoices');

      await customerInvoicesRef.add({
        'number': invoiceNumber,
        'customer': invoice.customer,
        'customerId': invoice.customerId,
        'customerEmail': invoice.customerEmail,
        'customerPhone': invoice.customerPhone,
        'customerAddress': invoice.customerAddress,
        'date': Timestamp.fromDate(invoice.date),
        'dueDate': Timestamp.fromDate(invoice.dueDate),
        'amount': invoice.amount,
        'tax': invoice.tax,
        'total': invoice.total,
        'status': 'Pending',
        'items': invoice.items.map((item) => ({
          'description': item.description,
          'quantity': item.quantity,
          'unitPrice': item.unitPrice,
          'total': item.total,
        })).toList(),
        'payments': [],
        'notes': invoice.notes,
        'terms': invoice.terms,
        'taxId': invoice.taxId,
        'discount': invoice.discount,
        'fees': invoice.fees,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invoice created successfully'),
          backgroundColor: Colors.green,
        ),
      );

      await _loadInvoices();
    } catch (e) {
      print('Error creating invoice: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error creating invoice')),
      );
    } finally {
      setState(() {
        _isCreatingInvoice = false;
      });
    }
  }

  Future<void> _updateInvoiceStatus(String invoiceId, String status) async {
    setState(() {
      _isSaving = true;
    });

    try {
      // MODIFIED: Find the invoice to get customerId for the correct path
      final invoice = _invoices.firstWhere((inv) => inv.id == invoiceId);

      // MODIFIED: Update using the customer-specific path
      await _firestore
          .collection('invoices')
          .doc(invoice.customerId)
          .collection('customer_invoices')
          .doc(invoiceId)
          .update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invoice marked as $status')),
      );

      await _loadInvoices();
    } catch (e) {
      print('Error updating invoice status: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error updating invoice status')),
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<void> _deleteInvoice(String invoiceId) async {
    final confirmed = await _showConfirmationDialog(
        'Delete Invoice',
        'Are you sure you want to delete this invoice? This action cannot be undone.'
    );

    if (!confirmed) return;

    setState(() {
      _isSaving = true;
    });

    try {
      // MODIFIED: Find the invoice to get customerId for the correct path
      final invoice = _invoices.firstWhere((inv) => inv.id == invoiceId);

      // MODIFIED: Delete using the customer-specific path
      await _firestore
          .collection('invoices')
          .doc(invoice.customerId)
          .collection('customer_invoices')
          .doc(invoiceId)
          .delete();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invoice deleted successfully'),
        backgroundColor: Colors.green),
      );

      await _loadInvoices();
    } catch (e) {
      print('Error deleting invoice: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error deleting invoice')),
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

  Future<void> _generatePdfInvoice(Invoice invoice) async {
    try {
      final pdf = pw.Document();

      // Load company logo
      final logo = await _loadCompanyLogo();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header with logo and company info
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Rbm Ice Company', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                        pw.Text('Limbe City - Batoke'),
                        pw.Text('Phone: +237 681099071'),
                        pw.Text('Email: Rbmicelimbe.com'),
                        pw.Text('Tax ID: ${invoice.taxId}'),
                      ],
                    ),
                    pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          _buildLogoSection(logo),
                        ]
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('INVOICE', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                        pw.Text('Number: ${invoice.number}'),
                        pw.Text('Date: ${DateFormat('yyyy-MM-dd').format(invoice.date)}'),
                        pw.Text('Due Date: ${DateFormat('yyyy-MM-dd').format(invoice.dueDate)}'),
                      ],
                    ),
                  ],
                ),

                pw.SizedBox(height: 20),

                // Client Information
                pw.Text('Bill To:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.Text(invoice.customer),
                pw.Text(invoice.customerAddress),
                pw.Text('Email: ${invoice.customerEmail}'),
                pw.Text('Phone: ${invoice.customerPhone}'),

                pw.SizedBox(height: 20),

                // Invoice Items Table
                pw.Table(
                  border: pw.TableBorder.all(),
                  children: [
                    pw.TableRow(
                      children: [
                        pw.Text('Description', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        pw.Text('Qty', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        pw.Text('Unit Price', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        pw.Text('Total', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                    ...invoice.items.map((item) => pw.TableRow(
                      children: [
                        pw.Text(item.description),
                        pw.Text(item.quantity.toString()),
                        pw.Text('${item.unitPrice.toStringAsFixed(2)} FCFA'),
                        pw.Text('${item.total.toStringAsFixed(2)} FCFA'),
                      ],
                    )),
                  ],
                ),

                pw.SizedBox(height: 20),

                // Totals
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('Subtotal: ${invoice.amount.toStringAsFixed(0)} FCFA'),
                        if (invoice.discount > 0) pw.Text('Discount (${invoice.discount}%): -${(invoice.amount * invoice.discount / 100).toStringAsFixed(0)} FCFA'),
                        if (invoice.fees > 0) pw.Text('Fees: ${invoice.fees.toStringAsFixed(0)} FCFA'),
                        pw.Text('Tax: ${invoice.tax.toStringAsFixed(0)} FCFA'),
                        pw.Divider(),
                        pw.Text('TOTAL: ${invoice.total.toStringAsFixed(0)} FCFA', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ],
                ),

                pw.SizedBox(height: 20),

                // Payment Terms and Notes
                pw.Text('Payment Terms: ${invoice.terms}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                if (invoice.notes.isNotEmpty) pw.Text('Notes: ${invoice.notes}'),
              ],
            );
          },
        ),
      );

      // Save the PDF
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/invoice_${invoice.number}.pdf');
      await file.writeAsBytes(await pdf.save());

      // Open the PDF
      await OpenFile.open(file.path);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF invoice generated successfully'),
        backgroundColor: Colors.green),
      );

    } catch (e) {
      print('Error generating PDF: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error generating PDF invoice')),
      );
    }
  }

  pw.Widget _buildLogoSection(pw.MemoryImage? logo) {
    if (logo != null) {
      return pw.Image(logo, width: 200, height: 150);
    } else {
      return pw.Container(
        width: 200,
        height: 150,
        decoration: pw.BoxDecoration(
          color: PdfColors.blue,
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Center(
          child: pw.Text(
            'RBM ICE',
            style: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      );
    }
  }

  Future<pw.MemoryImage?> _loadCompanyLogo() async {
    try {
      final ByteData logoData = await rootBundle.load('assets/icons/rbm_ice_logo.png');
      final Uint8List logoBytes = logoData.buffer.asUint8List();
      return pw.MemoryImage(logoBytes);
    } catch (e) {
      print('Error loading logo: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Filter invoices by status categories
    final pendingInvoices = _invoices.where((inv) => inv.status == 'Pending').toList();
    final paidInvoices = _invoices.where((inv) => inv.status == 'Paid').toList();
    final overdueInvoices = _invoices.where((inv) => inv.status == 'Overdue').toList();

    final totalOutstanding = _invoices
        .where((inv) => inv.status == 'Pending' || inv.status == 'Overdue')
        .fold(0.0, (sum, inv) => sum + inv.total);

    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Invoices Module'),
        backgroundColor: Colors.green[800],
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _showSearchDialog(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadInvoices,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildInvoicesOverview(paidInvoices.length, pendingInvoices.length, overdueInvoices.length, totalOutstanding),
          const SizedBox(height: 16),
          _buildTabBar(),
          Expanded(
            child: _isSaving
                ? const Center(child: CircularProgressIndicator())
                : _buildCurrentTab(pendingInvoices, paidInvoices, overdueInvoices),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateInvoiceDialog(),
        backgroundColor: Colors.green[800],
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }


  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Search Invoices'),
        content: TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            labelText: 'Search by client name',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) {
            setState(() {});
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              _searchController.clear();
              setState(() {});
              Navigator.pop(context);
            },
            child: const Text('Clear'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  List<Invoice> _getFilteredInvoices(List<Invoice> invoices) {
    if (_searchController.text.isEmpty) {
      return invoices;
    }
    return invoices.where((invoice) =>
        invoice.customer.toLowerCase().contains(_searchController.text.toLowerCase())
    ).toList();
  }

  Widget _buildInvoicesOverview(int paid, int pending, int overdue, double outstanding) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildInvoiceMetric('Paid', paid, Icons.check_circle, Colors.green),
          _buildInvoiceMetric('Pending', pending, Icons.pending, Colors.orange),
          _buildInvoiceMetric('Overdue', overdue, Icons.warning, Colors.red),
          _buildInvoiceMetric('Outstanding', outstanding, Icons.attach_money, Colors.blue, isCurrency: true),
        ],
      ),
    );
  }

  Widget _buildInvoiceMetric(String label, dynamic value, IconData icon, Color color, {bool isCurrency = false}) {
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
          _buildTabButton('Pending', 0),
          _buildTabButton('Paid', 1),
          _buildTabButton('Overdue', 2),
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
          foregroundColor: isSelected ? Colors.green[800] : Colors.grey,
          backgroundColor: isSelected ? Colors.green[50] : Colors.transparent,
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

  Widget _buildCurrentTab(List<Invoice> pendingInvoices, List<Invoice> paidInvoices, List<Invoice> overdueInvoices) {
    List<Invoice> currentInvoices;
    String tabTitle;

    switch (_currentTabIndex) {
      case 0:
        currentInvoices = _getFilteredInvoices(pendingInvoices);
        tabTitle = 'Pending Invoices';
        break;
      case 1:
        currentInvoices = _getFilteredInvoices(paidInvoices);
        tabTitle = 'Paid Invoices';
        break;
      case 2:
        currentInvoices = _getFilteredInvoices(overdueInvoices);
        tabTitle = 'Overdue Invoices';
        break;
      default:
        currentInvoices = [];
        tabTitle = 'Invoices';
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_searchController.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              'Search results for "${_searchController.text}" (${currentInvoices.length} found)',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
        Text(
          tabTitle,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        ...currentInvoices.map((invoice) => _buildInvoiceCard(invoice)),
      ],
    );
  }

  Widget _buildInvoiceCard(Invoice invoice) {
    Color statusColor;
    IconData statusIcon;

    switch (invoice.status) {
      case 'Paid':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'Pending':
        statusColor = Colors.orange;
        statusIcon = Icons.pending;
        break;
      case 'Overdue':
        statusColor = Colors.red;
        statusIcon = Icons.warning;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help;
    }

    final isOverdue = invoice.status == 'Overdue';
    final daysOverdue = isOverdue ? DateTime.now().difference(invoice.dueDate).inDays : 0;

    return GestureDetector(
      onLongPress: () => _deleteInvoice(invoice.id),
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
                    invoice.number,
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
                          invoice.status,
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
                invoice.customer,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildInvoiceDetail('Issue Date', DateFormat('MMM d, y').format(invoice.date)),
                  const SizedBox(width: 16),
                  _buildInvoiceDetail('Due Date', DateFormat('MMM d, y').format(invoice.dueDate)),
                ],
              ),
              const SizedBox(height: 8),
              if (isOverdue)
                Text(
                  '$daysOverdue days overdue',
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Amount',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '${invoice.total.toStringAsFixed(0)} FCFA',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (invoice.status == 'Pending' || invoice.status == 'Overdue')
                    ElevatedButton.icon(
                      onPressed: () => _updateInvoiceStatus(invoice.id, 'Paid'),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Mark as Paid'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.visibility, size: 18),
                        onPressed: () => _viewInvoiceDetails(invoice),
                      ),
                      IconButton(
                        icon: const Icon(Icons.picture_as_pdf, size: 18),
                        onPressed: () => _generatePdfInvoice(invoice),
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

  Widget _buildInvoiceDetail(String label, String value) {
    return Column(
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
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  void _showCreateInvoiceDialog() {
    Customer? selectedClient;
    final List<InvoiceItem> invoiceItems = [];
    final termsController = TextEditingController(text: 'Net 30');
    final taxIdController = TextEditingController(text: 'TAX-123456789');
    final discountController = TextEditingController(text: '0');
    final feesController = TextEditingController(text: '0');
    final notesController = TextEditingController();
    DateTime selectedDueDate = DateTime.now().add(const Duration(days: 30));

    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Create New Invoice'),
            content: isSubmitting
                ? SizedBox(
              height: 150,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.green[800]!),
                    ),
                    const SizedBox(height: 16),
                    const Text('Creating invoice...'),
                  ],
                ),
              ),
            )
                : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<Customer>(
                    value: selectedClient,
                    decoration: const InputDecoration(labelText: 'Client'),
                    items: _clients.map((client) {
                      return DropdownMenuItem<Customer>(
                        value: client,
                        child: Text(client.name),
                      );
                    }).toList(),
                    onChanged: (Customer? newValue) {
                      setState(() {
                        selectedClient = newValue;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  // Due Date Picker
                  InkWell(
                    onTap: () async {
                      final pickedDate = await showDatePicker(
                        context: context,
                        initialDate: selectedDueDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (pickedDate != null) {
                        setState(() {
                          selectedDueDate = pickedDate;
                        });
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Due Date',
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(DateFormat('MMM d, y').format(selectedDueDate)),
                          const Icon(Icons.calendar_today),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Invoice Items:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...invoiceItems.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    return ListTile(
                      title: Text('${item.quantity}x ${item.description}'),
                      subtitle: Text('${item.total.toStringAsFixed(0)} FCFA'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, size: 18),
                        onPressed: () {
                          setState(() {
                            invoiceItems.removeAt(index);
                          });
                        },
                      ),
                    );
                  }),
                  ElevatedButton(
                    onPressed: () => _showAddInvoiceItemDialog(invoiceItems, setState),
                    child: const Text('Add Item'),
                  ),
                  TextField(
                    controller: termsController,
                    decoration: const InputDecoration(labelText: 'Payment Terms'),
                  ),
                  TextField(
                    controller: taxIdController,
                    decoration: const InputDecoration(labelText: 'Tax Identification Number'),
                  ),
                  TextField(
                    controller: discountController,
                    decoration: const InputDecoration(labelText: 'Discount (%)'),
                    keyboardType: TextInputType.number,
                  ),
                  TextField(
                    controller: feesController,
                    decoration: const InputDecoration(labelText: 'Additional Fees'),
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
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
                onPressed: selectedClient == null || invoiceItems.isEmpty ? null : () async {
                  // Validate required fields
                  if (selectedClient == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please select a client')),
                    );
                    return;
                  }

                  if (invoiceItems.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please add at least one item')),
                    );
                    return;
                  }

                  setState(() {
                    isSubmitting = true;
                  });

                  final subtotal = invoiceItems.fold(0.0, (sum, item) => sum + item.total);
                  final discount = double.tryParse(discountController.text) ?? 0.0;
                  final fees = double.tryParse(feesController.text) ?? 0.0;
                  final discountedAmount = subtotal - (subtotal * discount / 100);
                  final tax = discountedAmount * 0.1;
                  final total = discountedAmount + fees + tax;

                  final invoice = Invoice(
                    id: '',
                    number: '',
                    customer: selectedClient!.name,
                    customerId: selectedClient!.customerId,
                    customerEmail: selectedClient!.email,
                    customerPhone: selectedClient!.phone,
                    customerAddress: selectedClient!.address,
                    date: DateTime.now(),
                    dueDate: selectedDueDate,
                    amount: subtotal,
                    tax: tax,
                    total: total,
                    status: 'Pending',
                    items: invoiceItems,
                    payments: [],
                    notes: notesController.text,
                    terms: termsController.text,
                    taxId: taxIdController.text,
                    discount: discount,
                    fees: fees,
                  );

                  await _createInvoice(invoice);

                  if (mounted) {
                    Navigator.pop(context);
                  }
                },
                child: const Text('Create Invoice'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddInvoiceItemDialog(List<InvoiceItem> invoiceItems, StateSetter setState) {
    Product? selectedProduct;
    final quantityController = TextEditingController(text: '1');
    final descriptionController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, dialogSetState) {
          return AlertDialog(
            title: const Text('Add Invoice Item'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<Product>(
                  value: selectedProduct,
                  decoration: const InputDecoration(labelText: 'Product'),
                  items: _products.map((product) {
                    return DropdownMenuItem<Product>(
                      value: product,
                      child: Text('${product.name} (${product.price.toStringAsFixed(0)}) FCFA'),
                    );
                  }).toList(),
                  onChanged: (Product? newValue) {
                    dialogSetState(() {
                      selectedProduct = newValue;
                      if (newValue != null) {
                        descriptionController.text = newValue.name;
                      }
                    });
                  },
                ),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                TextField(
                  controller: quantityController,
                  decoration: const InputDecoration(labelText: 'Quantity'),
                  keyboardType: TextInputType.number,
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
                  final unitPrice = selectedProduct!.price;
                  final total = quantity * unitPrice;

                  invoiceItems.add(InvoiceItem(
                    description: descriptionController.text,
                    quantity: quantity,
                    unitPrice: unitPrice,
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

  void _viewInvoiceDetails(Invoice invoice) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Invoice ${invoice.number}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Customer: ${invoice.customer}'),
              Text('Email: ${invoice.customerEmail}'),
              Text('Phone: ${invoice.customerPhone}'),
              Text('Address: ${invoice.customerAddress}'),
              const SizedBox(height: 16),
              Text('Amount: ${invoice.amount.toStringAsFixed(0)} FCFA'),
              if (invoice.discount > 0) Text('Discount: ${invoice.discount}%'),
              if (invoice.fees > 0) Text('Fees: ${invoice.fees.toStringAsFixed(0)} FCFA'),
              Text('Tax: ${invoice.tax.toStringAsFixed(0)} FCFA'),
              Text('Total: ${invoice.total.toStringAsFixed(0)} FCFA'),
              Text('Status: ${invoice.status}'),
              Text('Due Date: ${DateFormat('MMM d, y').format(invoice.dueDate)}'),
              Text('Tax ID: ${invoice.taxId}'),
              Text('Terms: ${invoice.terms}'),
              if (invoice.notes.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Notes: ${invoice.notes}'),
              ],
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
class Invoice {
  String id;
  final String number;
  final String customer;
  final String customerId; // NEW: Added customerId
  final String customerEmail;
  final String customerPhone;
  final String customerAddress;
  final DateTime date;
  final DateTime dueDate;
  final double amount;
  final double tax;
  final double total;
  String status; // CHANGED: Made mutable for status updates
  final List<InvoiceItem> items;
  final List<Payment> payments;
  final String notes;
  final String terms;
  final String taxId;
  final double discount;
  final double fees;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Invoice({
    required this.id,
    required this.number,
    required this.customer,
    required this.customerId, // NEW: Added customerId
    this.customerEmail = '',
    this.customerPhone = '',
    this.customerAddress = '',
    required this.date,
    required this.dueDate,
    required this.amount,
    required this.tax,
    required this.total,
    required this.status,
    required this.items,
    required this.payments,
    this.notes = '',
    this.terms = '',
    this.taxId = '',
    this.discount = 0.0,
    this.fees = 0.0,
    this.createdAt,
    this.updatedAt,
  });

  double get paidAmount => payments.fold(0.0, (sum, payment) => sum + payment.amount);
}

class InvoiceItem {
  final String description;
  final int quantity;
  final double unitPrice;
  final double total;

  InvoiceItem({
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.total,
  });
}

class Payment {
  final DateTime date;
  final double amount;
  final String method;
  final String reference;

  Payment({
    required this.date,
    required this.amount,
    required this.method,
    required this.reference,
  });
}