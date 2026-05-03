import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// flutter_gemma disabled — using Cactus SDK for Gemma now.
// Uncomment if switching back to LiteRT LM fallback:
// import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'app/router.dart';
import 'app/theme.dart';
import 'core/providers/ai_providers.dart';
import 'core/services/persistence_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // flutter_gemma disabled — using Cactus SDK for Gemma now.
  // Uncomment if switching back to LiteRT LM fallback:
  // await FlutterGemma.initialize();

  // Initialize Hive for local storage
  await Hive.initFlutter();
  await PersistenceService.instance.initialize();

  // Initialize Indonesian locale data for DateFormat (history timestamps)
  await initializeDateFormatting('id', null);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFFF9F9F7),
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // Lock to portrait mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(
    ProviderScope(
      child: KawanIsyaratApp(),
    ),
  );
}

class KawanIsyaratApp extends ConsumerStatefulWidget {
  const KawanIsyaratApp({super.key});

  @override
  ConsumerState<KawanIsyaratApp> createState() => _KawanIsyaratAppState();
}

class _KawanIsyaratAppState extends ConsumerState<KawanIsyaratApp> {
  @override
  void initState() {
    super.initState();
    // Auto-load Gemma 4 model in background after first frame.
    // Tidak perlu user tap manual di Settings — langsung load saat app start.
    // initializeAll() early-returns jika sudah ready/working.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(aiInitProvider.notifier).initializeAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'KawanIsyarat',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: router,
    );
  }
}
