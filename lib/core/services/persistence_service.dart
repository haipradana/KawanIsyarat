import 'package:hive_flutter/hive_flutter.dart';

/// Central persistence service — wraps Hive boxes untuk history & progress.
///
/// Data yang disimpan:
/// - `conversation_history` (Box<Map>) — riwayat terjemahan Deaf↔Hearing
/// - `learning_progress` (Box<List<String>>) — item yang sudah selesai per modul
///   key contoh: `alfabet_sibi`, `alfabet_bisindo`, `kata_bisindo`
///
/// Semua data local-first — tidak ada cloud sync, privasi pengguna terjaga.
class PersistenceService {
  PersistenceService._();
  static final PersistenceService instance = PersistenceService._();

  static const String conversationBoxName = 'conversation_history';
  static const String learningBoxName = 'learning_progress';
  static const String vocabBoxName = 'vocab_history';

  Box<Map>? _convBox;
  Box<List>? _learnBox;
  Box<Map>? _vocabBox;

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _convBox = await Hive.openBox<Map>(conversationBoxName);
    _learnBox = await Hive.openBox<List>(learningBoxName);
    _vocabBox = await Hive.openBox<Map>(vocabBoxName);
    _initialized = true;
  }

  // ─── Conversation history ───────────────────────────────────────────────

  /// Return entries sorted newest-first.
  List<Map<String, dynamic>> loadConversations() {
    final box = _convBox;
    if (box == null) return [];
    final items = box.values
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    items.sort((a, b) {
      final ta = DateTime.tryParse(a['timestamp'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final tb = DateTime.tryParse(b['timestamp'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    return items;
  }

  Future<void> addConversation(String id, Map<String, dynamic> data) async {
    await _convBox?.put(id, data);
  }

  Future<void> deleteConversation(String id) async {
    await _convBox?.delete(id);
  }

  Future<void> clearConversations() async {
    await _convBox?.clear();
  }

  // ─── Learning progress ──────────────────────────────────────────────────

  /// Return set of completed item ids for a given module key.
  Set<String> loadCompleted(String moduleKey) {
    final list = _learnBox?.get(moduleKey);
    if (list == null) return <String>{};
    return list.map((e) => e.toString()).toSet();
  }

  Future<void> setCompleted(String moduleKey, Set<String> items) async {
    await _learnBox?.put(moduleKey, items.toList());
  }

  Future<void> markItemDone(String moduleKey, String itemId) async {
    final current = loadCompleted(moduleKey)..add(itemId);
    await setCompleted(moduleKey, current);
  }

  Future<void> unmarkItem(String moduleKey, String itemId) async {
    final current = loadCompleted(moduleKey)..remove(itemId);
    await setCompleted(moduleKey, current);
  }

  Future<void> resetModule(String moduleKey) async {
    await _learnBox?.delete(moduleKey);
  }

  Future<void> resetAllProgress() async {
    await _learnBox?.clear();
  }

  // ─── Vocab history ──────────────────────────────────────────────────────

  /// Return vocab entries sorted newest-first (max 50).
  List<Map<String, dynamic>> loadVocabHistory() {
    final box = _vocabBox;
    if (box == null) return [];
    final items = box.values
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    // Sort by savedAt desc
    items.sort((a, b) {
      final ta = DateTime.tryParse(a['savedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final tb = DateTime.tryParse(b['savedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    return items.take(50).toList();
  }

  Future<void> saveVocabEntry(String word, Map<String, dynamic> data) async {
    await _vocabBox?.put(word.toLowerCase(), data);
  }

  Future<void> clearVocabHistory() async {
    await _vocabBox?.clear();
  }
}
