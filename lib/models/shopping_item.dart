import 'json_utils.dart';

class ShoppingItem {
  const ShoppingItem({
    required this.id,
    required this.name,
    this.userId,
    this.familyId,
    this.listId,
    this.quantity = '',
    this.category = 'other',
    this.priority = 1,
    this.checked = false,
    this.recipeName,
    this.updatedAt,
  });

  final String id;
  final String? userId;
  final String? familyId;
  final String? listId;
  final String name;
  final String quantity;
  final String category;

  /// 0 = low, 1 = normal, 2 = high.
  final int priority;
  final bool checked;
  final String? recipeName;
  final DateTime? updatedAt;

  ShoppingItem copyWith({
    String? name,
    String? quantity,
    String? category,
    int? priority,
    bool? checked,
    String? userId,
    String? familyId,
    String? listId,
  }) =>
      ShoppingItem(
        id: id,
        userId: userId ?? this.userId,
        familyId: familyId ?? this.familyId,
        listId: listId ?? this.listId,
        name: name ?? this.name,
        quantity: quantity ?? this.quantity,
        category: category ?? this.category,
        priority: priority ?? this.priority,
        checked: checked ?? this.checked,
        recipeName: recipeName,
        updatedAt: DateTime.now(),
      );

  factory ShoppingItem.fromJson(Map<String, dynamic> j) => ShoppingItem(
        id: jStr(j['id']),
        userId: jStrOrNull(j['user_id']),
        familyId: jStrOrNull(j['family_id']),
        listId: jStrOrNull(j['list_id']),
        name: jStr(j['name']),
        quantity: jStr(j['quantity']),
        category: jStr(j['category'], 'other'),
        priority: jInt(j['priority'], 1).clamp(0, 2),
        checked: jBool(j['checked']),
        recipeName: jStrOrNull(j['recipe_name']),
        updatedAt: jDate(j['updated_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'family_id': familyId,
        'list_id': listId,
        'name': name,
        'quantity': quantity,
        'category': category,
        'priority': priority,
        'checked': checked,
        'recipe_name': recipeName,
        'updated_at': (updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
      };
}
