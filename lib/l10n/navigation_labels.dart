import 'app_localizations.dart';

extension NavigationLabels on AppLocalizations {
  // Compact destination names only. Screen titles and explanatory text keep
  // their full translations; the bottom bar never reduces the label font.
  String navigationLabel(String key) =>
      _navigationLabels[localeCode]?[key] ?? text(key);

  static const _navigationLabels = <String, Map<String, String>>{
    'en': {'reminders': 'Alerts'},
    'mk': {'items': 'Артикли', 'reminders': 'Рокови', 'settings': 'Опции'},
    'de': {'add': 'Neu', 'reminders': 'Fristen', 'settings': 'Optionen'},
    'es': {'reminders': 'Avisos'},
    'it': {'reminders': 'Avvisi', 'settings': 'Opzioni'},
    'tr': {'reminders': 'Uyarılar'},
    'el': {'items': 'Είδη', 'add': 'Νέο', 'reminders': 'Λήξεις'},
    'pl': {'reminders': 'Alerty', 'settings': 'Opcje'},
    'cs': {'reminders': 'Termíny'},
    'pt-PT': {'reminders': 'Alertas', 'settings': 'Opções'},
    'pt-BR': {'reminders': 'Alertas', 'settings': 'Ajustes'},
  };

}
