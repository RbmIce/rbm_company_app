// sales_models.dart
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
}

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
}