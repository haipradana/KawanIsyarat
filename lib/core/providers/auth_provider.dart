import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:hive_flutter/hive_flutter.dart';

class AuthState {
  final GoogleSignInAccount? user;
  final bool isLoading;
  final String? error;
  /// True if user previously signed in (persisted in Hive).
  /// Used to skip landing screen while Google restores the session.
  final bool hasSession;

  const AuthState({
    this.user,
    this.isLoading = false,
    this.error,
    this.hasSession = false,
  });

  bool get isSignedIn => user != null || hasSession;
  String get displayName => user?.displayName ?? 'Pengguna';
  String? get email => user?.email;
  String? get photoUrl => user?.photoUrl;

  AuthState copyWith({
    GoogleSignInAccount? user,
    bool? isLoading,
    String? error,
    bool? hasSession,
    bool clearUser = false,
  }) {
    return AuthState(
      user: clearUser ? null : (user ?? this.user),
      isLoading: isLoading ?? this.isLoading,
      error: error,
      hasSession: hasSession ?? this.hasSession,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState()) {
    _init();
  }

  static const String _boxName = 'settings';
  static const String _authKey = 'is_signed_in';

  Future<void> _init() async {
    try {
      // Check Hive for persisted session first
      final box = await Hive.openBox(_boxName);
      final savedSession = box.get(_authKey, defaultValue: false) as bool;

      if (savedSession) {
        // User was previously signed in — let them through immediately
        state = state.copyWith(hasSession: true);
      }

      await GoogleSignIn.instance.initialize();
      // Try to silently restore Google session
      final user = await GoogleSignIn.instance.attemptLightweightAuthentication();
      if (user != null) {
        await box.put(_authKey, true);
        state = state.copyWith(user: user, hasSession: true);
        debugPrint('[Auth] Session restored: ${user.displayName}');
      } else if (savedSession) {
        // Hive says signed in but Google token expired — still let through
        debugPrint('[Auth] Hive session found but Google token expired, keeping session');
      }
    } catch (e) {
      debugPrint('[Auth] Init error: $e');
    }
  }

  Future<void> signIn() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final user = await GoogleSignIn.instance.authenticate();
      // Persist to Hive
      final box = await Hive.openBox(_boxName);
      await box.put(_authKey, true);
      state = state.copyWith(user: user, isLoading: false, hasSession: true);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Gagal masuk. Coba lagi.',
      );
    }
  }

  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    // Clear Hive
    final box = await Hive.openBox(_boxName);
    await box.put(_authKey, false);
    state = const AuthState();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
