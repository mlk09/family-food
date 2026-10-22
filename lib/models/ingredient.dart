import 'json_utils.dart';

enum Freshness { fresh, expiringSoon, expired, unknown }

class Ingredient {
  const Ingredient({
    required this.id,
    required this.name,
    this.userId,
    this.familyId,
    this.quantity = 1,
    this.unit = 'pieces',
    this.category = 'other',
    this.purchaseDate,
    this.expiryDate,
    this.notes,
    this.updatedAt,
  });

  final String id;
  final String? userId;
  final String? familyId;
  final String name;
  final double quantity;
  final String unit;
  final String category;
  final DateTime? purchaseDate;
  final DateTime? expiryDate;
  final String? notes;
  final DateTime? updatedAt;

  /// Days until expiry (negative when expired). Null when no expiry date.
  int? daysLeft([DateTime? now]) {
    if (expiryDate == null) return null;
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final exp = DateTime(expiryDate!.year, expiryDate!.month, expiryDate!.day);
    return exp.difference(today).inDays;
  }

  Freshness freshness([DateTime? now]) {
    final d = daysLeft(now);
    if (d == null) return Freshness.unknown;
    if (d < 0) return Freshness.expired;
    if (d <= 2) return Freshness.expiringSoon;
    return Freshness.fresh;
  }

  String get quantityLabel {
    final q = quantity == quantity.roundToDouble() ? quantity.toInt().toString() : quantity.toStringAsFixed(1);
    return unit == 'pieces' ? q : '$q $unit';
  }

  Ingredient copyWith({
    String? name,
    double? quantity,
    String? unit,
    String? category,
    DateTime? purchaseDate,
    DateTime? expiryDate,
    bool clearExpiry = false,
    String? notes,
    String? userId,
    String? familyId,
  }) =>
      Ingredient(
        id: id,
        userId: userId ?? this.userId,
        familyId: familyId ?? this.familyId,
        name: name ?? this.name,
        quantity: quantity ?? this.quantity,
        unit: unit ?? this.unit,
        category: category ?? this.category,
        purchaseDate: purchaseDate ?? this.purchaseDate,
        expiryDate: clearExpiry ? null : (expiryDate ?? this.expiryDate),
        notes: notes ?? this.notes,
        updatedAt: DateTime.now(),
      );

  factory Ingredient.fromJson(Map<String, dynamic> j) => Ingredient(
        id: jStr(j['id']),
        userId: jStrOrNull(j['user_id']),
        familyId: jStrOrNull(j['family_id']),
        name: jStr(j['name']),
        quantity: jDouble(j['quantity'], 1),
        unit: jStr(j['unit'], 'pieces'),
        category: jStr(j['category'], 'other'),
        purchaseDate: jDate(j['purchase_date']),
        expiryDate: jDate(j['expiry_date']),
        notes: jStrOrNull(j['notes']),
        updatedAt: jDate(j['updated_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'family_id': familyId,
        'name': name,
        'quantity': quantity,
        'unit': unit,
        'category': category,
        'purchase_date': dateOnly(purchaseDate),
        'expiry_date': dateOnly(expiryDate),
        'notes': notes,
        'updated_at': (updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
      };
}
