class Validators {
  Validators._();

  static final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  static String? email(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Please enter your email';
    if (!_email.hasMatch(s)) return 'That email looks incomplete';
    return null;
  }

  static String? password(String? v) {
    if ((v ?? '').isEmpty) return 'Please enter your password';
    if (v!.length < 6) return 'At least 6 characters';
    return null;
  }

  static String? name(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Please enter a name';
    if (s.length > 40) return 'Keep it under 40 characters';
    return null;
  }

  static String? ingredientName(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'What is it called?';
    if (s.length > 40) return 'Keep it short (max 40 characters)';
    return null;
  }

  static String? quantity(String? v) {
    final q = double.tryParse((v ?? '').trim());
    if (q == null) return 'Enter a number';
    if (q <= 0) return 'Must be more than 0';
    if (q > 100000) return 'That seems too large';
    return null;
  }
}
