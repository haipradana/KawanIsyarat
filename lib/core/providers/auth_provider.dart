import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthState {
  final GoogleSignInAccount? user;
  final bool isLoading;
  final String? error;

  const AuthState({this.user, this.isLoading = false, this.error});

  bool get isSignedIn => user != null;
  String get displayName => user?.displayName ?? 'Pengguna';
  String? get email => user?.email;
  String? get photoUrl => user?.photoUrl;

  AuthState copyWith({
    GoogleSignInAccount? user,
    bool? isLoading,
    String? error,
    bool clearUser = false,
  }) {
    return AuthState(
      user: clearUser ? null : (user ?? this.user),
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState()) {
    _init();
  }

  Future<void> _init() async {
    try {
      await GoogleSignIn.instance.initialize();
      // Check for existing session
      final user = await GoogleSignIn.instance.attemptLightweightAuthentication();
      if (user != null) {
        state = state.copyWith(user: user);
      }
    } catch (_) {
      // No existing session or init failed
    }
  }

  Future<void> signIn() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final user = await GoogleSignIn.instance.authenticate();
      state = state.copyWith(user: user, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Gagal masuk. Coba lagi.',
      );
    }
  }

  Future<void> signOut() async {
    await GoogleSignIn.instance.signOut();
    state = const AuthState();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
