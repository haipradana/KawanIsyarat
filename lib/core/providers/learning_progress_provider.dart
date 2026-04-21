import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/persistence_service.dart';

/// Module keys untuk tracking progress.
class LearningModule {
  static const String alfabetSibi = 'alfabet_sibi';
  static const String alfabetBisindo = 'alfabet_bisindo';
  static const String kataBisindo = 'kata_bisindo';
  static const String idiom = 'idiom';
  static const String artikulasi = 'artikulasi';

  /// Total item per modul untuk hitung persentase.
  static const Map<String, int> totals = {
    alfabetSibi: 24, // A-Y skip J, Z
    alfabetBisindo: 26, // A-Z
    kataBisindo: 6, // maaf, saya, terima_kasih, tuli, dengar, rumah
    idiom: 5,
    artikulasi: 10,
  };

  static int totalFor(String moduleKey) => totals[moduleKey] ?? 0;
}

/// State: map of moduleKey -> set of completed item ids.
class LearningProgressState {
  final Map<String, Set<String>> completed;
  const LearningProgressState(this.completed);

  LearningProgressState copyWith(Map<String, Set<String>> completed) =>
      LearningProgressState(completed);

  Set<String> itemsFor(String moduleKey) =>
      completed[moduleKey] ?? const <String>{};

  int countFor(String moduleKey) => itemsFor(moduleKey).length;

  double progressFor(String moduleKey) {
    final total = LearningModule.totalFor(moduleKey);
    if (total == 0) return 0.0;
    return (countFor(moduleKey) / total).clamp(0.0, 1.0);
  }

  bool isDone(String moduleKey, String itemId) =>
      itemsFor(moduleKey).contains(itemId);
}

class LearningProgressNotifier extends StateNotifier<LearningProgressState> {
  final PersistenceService _svc;

  LearningProgressNotifier(this._svc)
      : super(const LearningProgressState({})) {
    _load();
  }

  void _load() {
    final map = <String, Set<String>>{};
    for (final key in LearningModule.totals.keys) {
      map[key] = _svc.loadCompleted(key);
    }
    state = LearningProgressState(map);
  }

  Future<void> markDone(String moduleKey, String itemId) async {
    await _svc.markItemDone(moduleKey, itemId);
    final next = Map<String, Set<String>>.from(state.completed);
    next[moduleKey] = {...(next[moduleKey] ?? {}), itemId};
    state = LearningProgressState(next);
  }

  Future<void> unmark(String moduleKey, String itemId) async {
    await _svc.unmarkItem(moduleKey, itemId);
    final next = Map<String, Set<String>>.from(state.completed);
    next[moduleKey] = {...(next[moduleKey] ?? {})}..remove(itemId);
    state = LearningProgressState(next);
  }

  Future<void> resetModule(String moduleKey) async {
    await _svc.resetModule(moduleKey);
    final next = Map<String, Set<String>>.from(state.completed);
    next[moduleKey] = <String>{};
    state = LearningProgressState(next);
  }

  Future<void> resetAll() async {
    await _svc.resetAllProgress();
    final next = <String, Set<String>>{
      for (final key in LearningModule.totals.keys) key: <String>{},
    };
    state = LearningProgressState(next);
  }
}

final learningProgressProvider =
    StateNotifierProvider<LearningProgressNotifier, LearningProgressState>(
  (ref) => LearningProgressNotifier(PersistenceService.instance),
);
