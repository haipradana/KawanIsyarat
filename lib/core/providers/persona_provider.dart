import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../shared/models/user_persona.dart';

final personaProvider = StateNotifierProvider<PersonaNotifier, UserPersona?>((ref) {
  return PersonaNotifier();
});

class PersonaNotifier extends StateNotifier<UserPersona?> {
  PersonaNotifier() : super(null) {
    _loadPersona();
  }

  static const String _boxName = 'settings';
  static const String _personaKey = 'selected_persona';

  Future<void> _loadPersona() async {
    final box = await Hive.openBox(_boxName);
    final savedPersona = box.get(_personaKey);
    if (savedPersona != null) {
      state = UserPersona.values.firstWhere(
        (p) => p.name == savedPersona,
        orElse: () => UserPersona.tuli,
      );
    }
  }

  Future<void> setPersona(UserPersona persona) async {
    state = persona;
    final box = await Hive.openBox(_boxName);
    await box.put(_personaKey, persona.name);
  }

  Future<void> resetPersona() async {
    state = null;
    final box = await Hive.openBox(_boxName);
    await box.delete(_personaKey);
  }

  bool get hasSelectedPersona => state != null;
}
