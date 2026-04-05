import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/providers/persona_provider.dart';
import '../features/onboarding/screens/login_screen.dart';
import '../features/onboarding/screens/persona_selection_screen.dart';
import '../features/onboarding/screens/ai_init_screen.dart';
import '../features/home/screens/home_dashboard_screen.dart';
import '../features/communication/screens/comm_direction_picker_screen.dart';
import '../features/communication/screens/comm_deaf_to_hearing_screen.dart';
import '../features/communication/screens/comm_hearing_to_deaf_screen.dart';
import '../features/learning/screens/learning_hub_screen.dart';
import '../features/learning/screens/learn_kata_screen.dart';
import '../features/learning/screens/learn_alfabet_screen.dart';
import '../features/learning/screens/learn_idiom_screen.dart';
import '../features/learning/screens/learn_artikulasi_screen.dart';
import '../features/history/screens/history_screen.dart';
import '../features/settings/screens/settings_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final persona = ref.watch(personaProvider);

  String initialLocation;
  if (persona == null) {
    initialLocation = '/onboarding';
  } else {
    initialLocation = '/home';
  }

  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: LoginScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),
      GoRoute(
        path: '/onboarding',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: PersonaSelectionScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),
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
      _slideRoute('/comm-picker', CommDirectionPickerScreen()),
      _slideRoute('/comm-deaf', CommDeafToHearingScreen()),
      _slideRoute('/comm-hearing', CommHearingToDeafScreen()),
      _slideRoute('/learn', LearningHubScreen()),
      _slideRoute('/learn/kata', LearnKataScreen()),
      _slideRoute('/learn/alfabet', LearnAlfabetScreen()),
      _slideRoute('/learn/idiom', LearnIdiomScreen()),
      _slideRoute('/learn/artikulasi', LearnArtikulasiScreen()),
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
