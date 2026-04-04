import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF006D6D);
  static const Color primaryDark = Color(0xFF005353);
  static const Color primaryContainer = Color(0xFF006D6D);
  static const Color primaryLight = Color(0xFF82D4D4);
  static const Color accent = Color(0xFFF5A623);
  static const Color accentContainer = Color(0xFFFEAE2C);
  static const Color background = Color(0xFFF9F9F7);
  static const Color surface = Color(0xFFF9F9F7);
  static const Color surfaceContainerLow = Color(0xFFF4F4F2);
  static const Color surfaceContainer = Color(0xFFEEEEEC);
  static const Color surfaceContainerHigh = Color(0xFFE8E8E6);
  static const Color surfaceContainerHighest = Color(0xFFE2E3E1);
  static const Color darkSurface = Color(0xFF1A2332);
  static const Color textPrimary = Color(0xFF1A1C1B);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFBA1A1A);
  static const Color outline = Color(0xFF6E7979);
  static const Color outlineVariant = Color(0xFFBEC9C8);
  static const Color tertiary = Color(0xFF733A1A);
  static const Color tertiaryContainer = Color(0xFF90512F);
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color inverseSurface = Color(0xFF2F3130);
  static const Color onInverseSurface = Color(0xFFF1F1EF);
}

class AppSpacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;
  static const double xxxl = 32.0;
  static const double huge = 48.0;
}

class AppRadius {
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;
  static const double xxxl = 32.0;
  static const double full = 999.0;
}

class AppStrings {
  static const String appName = 'KawanIsyarat';
  static const String tagline = 'Jembatan Komunikasi Inklusif';
}

class BisindoData {
  static const List<Map<String, String>> kataList = [
    {'word': 'TERIMA KASIH', 'instruction': 'Sentuh dagu lalu gerakkan tangan ke depan bawah'},
    {'word': 'TOLONG', 'instruction': 'Letakkan telapak tangan kanan di dada, gerakkan melingkar'},
    {'word': 'HALO', 'instruction': 'Angkat tangan kanan setinggi bahu, lambaikan'},
    {'word': 'NAMA', 'instruction': 'Ketuk dahi dua kali dengan jari telunjuk dan tengah'},
    {'word': 'SAYA', 'instruction': 'Tunjuk dada dengan jari telunjuk'},
    {'word': 'MAKAN', 'instruction': 'Gerakkan tangan ke mulut berulang kali'},
    {'word': 'MINUM', 'instruction': 'Gerakkan tangan seperti memegang gelas ke mulut'},
    {'word': 'RUMAH', 'instruction': 'Satukan kedua telapak tangan membentuk segitiga atap'},
    {'word': 'SEKOLAH', 'instruction': 'Tepuk telapak tangan dua kali'},
    {'word': 'MAAF', 'instruction': 'Letakkan telapak tangan di dada, gerakkan melingkar pelan'},
  ];

  static const List<String> alfabet = [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J',
    'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T',
    'U', 'V', 'W', 'X', 'Y', 'Z',
  ];

  static const List<Map<String, String>> idiomList = [
    {
      'idiom': 'Panjang tangan',
      'meaning': 'Suka mencuri',
      'explanation': '"Panjang tangan" bukan berarti tangannya panjang secara fisik. Dalam bahasa sehari-hari, ini artinya seseorang suka mengambil barang milik orang lain. Isyaratnya sama dengan isyarat "Mencuri".',
    },
    {
      'idiom': 'Kepala batu',
      'meaning': 'Keras kepala, susah dibilangin',
      'explanation': '"Kepala batu" artinya seseorang yang sangat keras kepala dan tidak mau mendengarkan pendapat orang lain. Bukan berarti kepalanya terbuat dari batu.',
    },
    {
      'idiom': 'Buah tangan',
      'meaning': 'Oleh-oleh atau hadiah',
      'explanation': '"Buah tangan" artinya hadiah atau oleh-oleh yang dibawa saat berkunjung. Tidak ada hubungannya dengan buah yang dipegang tangan.',
    },
    {
      'idiom': 'Ringan tangan',
      'meaning': 'Suka memukul atau suka menolong',
      'explanation': '"Ringan tangan" punya dua arti tergantung konteks. Bisa berarti suka memukul (negatif) atau suka menolong orang lain (positif).',
    },
    {
      'idiom': 'Mata duitan',
      'meaning': 'Hanya mementingkan uang',
      'explanation': '"Mata duitan" menggambarkan orang yang hanya peduli pada uang. Seolah-olah matanya hanya melihat uang saja.',
    },
  ];

  static const List<String> artikulasiWords = [
    'Bapak', 'Ibu', 'Terima kasih', 'Selamat pagi',
    'Apa kabar', 'Tolong', 'Maaf', 'Permisi',
    'Nama saya', 'Senang bertemu',
  ];
}

class MockData {
  static const List<String> glossSequence = [
    'NAMA', 'SAYA', 'APA', 'TERIMA', 'KASIH', 'TOLONG', 'BANTU',
  ];

  static const Map<String, String> glossToSentence = {
    'NAMA_SAYA_APA': 'Siapa nama kamu?',
    'TERIMA_KASIH': 'Terima kasih banyak!',
    'TOLONG_BANTU': 'Tolong bantu saya.',
    'SAYA_SENANG': 'Saya senang bertemu denganmu!',
  };

  static const String defaultSentence = 'Maaf, saya tidak mengerti. Bisa diulang?';

  static const String mockRawTranscription =
      'Halo apa kabar nama saya Budi, saya sedang mencari jalan menuju stasiun terdekat dari sini...';

  static const String mockSummarized =
      'Halo, Budi ingin tahu jalan ke stasiun.';
}
