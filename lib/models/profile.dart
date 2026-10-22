import 'json_utils.dart';

class UserProfile {
  const UserProfile({
    required this.id,
    this.name = '',
    this.avatarUrl,
    this.ageGroup = 'adult',
    this.diet = 'vegetarian',
    this.foodPreferences = const [],
    this.allergies = const [],
    this.favoriteFoods = const [],
    this.dislikedFoods = const [],
    this.spiceLevel = 2,
    this.familyId,
    this.cookingStreak = 0,
    this.lastCookedOn,
  });

  final String id;
  final String name;
  final String? avatarUrl;
  final String ageGroup;
  final String diet;
  final List<String> foodPreferences;
  final List<String> allergies;
  final List<String> favoriteFoods;
  final List<String> dislikedFoods;

  /// 0 (none) … 4 (extra hot).
  final int spiceLevel;
  final String? familyId;
  final int cookingStreak;
  final DateTime? lastCookedOn;

  bool get isChild => ageGroup == 'child';
  String get firstName => name.trim().isEmpty ? 'Chef' : name.trim().split(' ').first;

  /// Streak is only "alive" if the family cooked today or yesterday.
  int currentStreak([DateTime? now]) {
    if (lastCookedOn == null) return 0;
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final last = DateTime(lastCookedOn!.year, lastCookedOn!.month, lastCookedOn!.day);
    return today.difference(last).inDays <= 1 ? cookingStreak : 0;
  }

  UserProfile recordCooked([DateTime? now]) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    int streak;
    if (lastCookedOn == null) {
      streak = 1;
    } else {
      final last = DateTime(lastCookedOn!.year, lastCookedOn!.month, lastCookedOn!.day);
      final gap = today.difference(last).inDays;
      streak = gap == 0 ? cookingStreak : (gap == 1 ? cookingStreak + 1 : 1);
    }
    return copyWith(cookingStreak: streak, lastCookedOn: today);
  }

  UserProfile copyWith({
    String? name,
    String? avatarUrl,
    String? ageGroup,
    String? diet,
    List<String>? foodPreferences,
    List<String>? allergies,
    List<String>? favoriteFoods,
    List<String>? dislikedFoods,
    int? spiceLevel,
    String? familyId,
    bool clearFamily = false,
    int? cookingStreak,
    DateTime? lastCookedOn,
  }) =>
      UserProfile(
        id: id,
        name: name ?? this.name,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        ageGroup: ageGroup ?? this.ageGroup,
        diet: diet ?? this.diet,
        foodPreferences: foodPreferences ?? this.foodPreferences,
        allergies: allergies ?? this.allergies,
        favoriteFoods: favoriteFoods ?? this.favoriteFoods,
        dislikedFoods: dislikedFoods ?? this.dislikedFoods,
        spiceLevel: spiceLevel ?? this.spiceLevel,
        familyId: clearFamily ? null : (familyId ?? this.familyId),
        cookingStreak: cookingStreak ?? this.cookingStreak,
        lastCookedOn: lastCookedOn ?? this.lastCookedOn,
      );

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        id: jStr(j['id']),
        name: jStr(j['name']),
        avatarUrl: jStrOrNull(j['avatar_url']),
        ageGroup: jStr(j['age_group'], 'adult'),
        diet: jStr(j['diet'], 'vegetarian'),
        foodPreferences: jStrList(j['food_preferences']),
        allergies: jStrList(j['allergies']),
        favoriteFoods: jStrList(j['favorite_foods']),
        dislikedFoods: jStrList(j['disliked_foods']),
        spiceLevel: jInt(j['spice_level'], 2).clamp(0, 4),
        familyId: jStrOrNull(j['family_id']),
        cookingStreak: jInt(j['cooking_streak']),
        lastCookedOn: jDate(j['last_cooked_on']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'avatar_url': avatarUrl,
        'age_group': ageGroup,
        'diet': diet,
        'food_preferences': foodPreferences,
        'allergies': allergies,
        'favorite_foods': favoriteFoods,
        'disliked_foods': dislikedFoods,
        'spice_level': spiceLevel,
        'family_id': familyId,
        'cooking_streak': cookingStreak,
        'last_cooked_on': dateOnly(lastCookedOn),
      };
}

class Family {
  const Family({required this.id, required this.name, this.inviteCode = '', this.members = const []});
  final String id;
  final String name;
  final String inviteCode;
  final List<FamilyMember> members;

  factory Family.fromJson(Map<String, dynamic> j) => Family(
        id: jStr(j['id']),
        name: jStr(j['name']),
        inviteCode: jStr(j['invite_code']),
        members: jMapList(j['members'] ?? j['family_members']).map(FamilyMember.fromJson).toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'invite_code': inviteCode,
        'members': members.map((m) => m.toJson()).toList(),
      };
}

class FamilyMember {
  const FamilyMember({required this.userId, required this.displayName, this.role = 'member', this.isAdmin = false});
  final String userId;
  final String displayName;
  final String role;
  final bool isAdmin;

  factory FamilyMember.fromJson(Map<String, dynamic> j) => FamilyMember(
        userId: jStr(j['user_id']),
        displayName: jStr(j['display_name'], 'Member'),
        role: jStr(j['role'], 'member'),
        isAdmin: jBool(j['is_admin']),
      );

  Map<String, dynamic> toJson() =>
      {'user_id': userId, 'display_name': displayName, 'role': role, 'is_admin': isAdmin};
}

class ChatMessage {
  const ChatMessage({required this.role, required this.content, this.pending = false});
  final String role; // 'user' | 'assistant'
  final String content;
  final bool pending;

  bool get isUser => role == 'user';

  ChatMessage copyWith({String? content, bool? pending}) =>
      ChatMessage(role: role, content: content ?? this.content, pending: pending ?? this.pending);

  factory ChatMessage.fromJson(Map<String, dynamic> j) =>
      ChatMessage(role: jStr(j['role'], 'assistant'), content: jStr(j['content']));

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}
