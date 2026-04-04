enum UserPersona {
  tuli,
  mendengar,
}

extension UserPersonaExtension on UserPersona {
  String get displayName {
    switch (this) {
      case UserPersona.tuli:
        return 'Pengguna Tuli';
      case UserPersona.mendengar:
        return 'Pengguna Mendengar';
    }
  }

  String get emoji {
    switch (this) {
      case UserPersona.tuli:
        return '🤟';
      case UserPersona.mendengar:
        return '👂';
    }
  }

  String get description {
    switch (this) {
      case UserPersona.tuli:
        return 'Gunakan kamera untuk menerjemahkan isyarat menjadi teks & suara';
      case UserPersona.mendengar:
        return 'Bicara atau ketik untuk diterjemahkan menjadi bahasa isyarat';
    }
  }
}
