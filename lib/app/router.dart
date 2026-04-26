import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/providers/persona_provider.dart';
import '../core/providers/auth_provider.dart';
import '../features/onboarding/screens/landing_screen.dart';
import '../features/onboarding/screens/persona_selection_screen.dart';
import '../features/onboarding/screens/ai_init_screen.dart';
import '../features/home/screens/home_dashboard_screen.dart';
import '../features/communication/screens/comm_direction_picker_screen.dart';
import '../features/communication/screens/comm_deaf_to_hearing_screen.dart';
import '../features/communication/screens/comm_hearing_to_deaf_screen.dart';
import '../features/learning/screens/learning_hub_screen.dart';
import '../features/learning/screens/learn_kata_screen.dart';
import '../features/learning/screens/learn_kata_picker_screen.dart';
import '../features/learning/screens/learn_alfabet_screen.dart';
import '../features/learning/screens/alphabet_practice_screen.dart'
    show AlphabetMode;
import '../features/learning/screens/learn_idiom_screen.dart';
import '../features/learning/screens/learn_artikulasi_screen.dart';
import '../features/learning/screens/vocabulary_helper_screen.dart';
import '../features/history/screens/history_screen.dart';
import '../features/settings/screens/settings_screen.dart';
import '../features/emergency/screens/emergency_quick_sign_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final persona = ref.watch(personaProvider);
  final auth = ref.watch(authProvider);

  String initialLocation;
  if (!auth.isSignedIn) {
    initialLocation = '/';
  } else if (persona == null) {
    initialLocation = '/persona';
  } else {
    initialLocation = '/home';
  }

  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      // Landing / Hero page (entry point)
      GoRoute(
        path: '/',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: LandingScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),
      // Persona selection
      GoRoute(
        path: '/persona',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: PersonaSelectionScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),
      // AI model download/init
      GoRoute(
        path: '/ai-init',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: AIInitScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),
      // Home dashboard
      GoRoute(
        path: '/home',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: HomeDashboardScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),
      _slideRoute('/comm-picker', CommDirectionPickerScreen()),
      _slideRoute('/comm-deaf', CommDeafToHearingScreen()),
      _slideRoute('/comm-hearing', CommHearingToDeafScreen()),
      _slideRoute('/learn', LearningHubScreen()),
      _slideRoute('/learn/kata', LearnKataPickerScreen()),
      GoRoute(
        path: '/learn/kata/practice',
        pageBuilder: (context, state) {
          final extra = state.extra;
          String word = 'terima_kasih';
          if (extra is Map && extra['word'] is String) {
            word = extra['word'] as String;
          }
          return CustomTransitionPage(
            key: state.pageKey,
            child: LearnKataScreen(word: word),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              final slideAnimation = Tween<Offset>(
                begin: Offset(0, 0.05),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOut,
              ));
              return SlideTransition(
                position: slideAnimation,
                child: FadeTransition(opacity: animation, child: child),
              );
            },
          );
        },
      ),
      _slideRoute('/learn/alfabet', LearnAlfabetScreen()),
      _slideRoute('/learn/alfabet/sibi',
          LearnAlfabetScreen(initialMode: AlphabetMode.sibi)),
      _slideRoute('/learn/alfabet/bisindo',
          LearnAlfabetScreen(initialMode: AlphabetMode.bisindo)),
      _slideRoute('/learn/idiom', LearnIdiomScreen()),
      _slideRoute('/learn/artikulasi', LearnArtikulasiScreen()),
      _slideRoute('/learn/kamus', VocabularyHelperScreen()),
      _slideRoute('/sos', EmergencyQuickSignScreen()),
      _slideRoute('/history', HistoryScreen()),
      _slideRoute('/settings', SettingsScreen()),
    ],
  );
});

GoRoute _slideRoute(String path, Widget child) {
  return GoRoute(
    path: path,
    pageBuilder: (context, state) => CustomTransitionPage(
      key: state.pageKey,
      child: child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final slideAnimation = Tween<Offset>(
          begin: Offset(0, 0.05),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        ));
        return SlideTransition(
          position: slideAnimation,
          child: FadeTransition(opacity: animation, child: child),
        );
      },
    ),
  );
}
