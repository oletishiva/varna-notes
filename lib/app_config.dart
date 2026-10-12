/// Single source of truth for the app name, tagline, ids, free limits and
/// prices. Nothing else in the code base should hard-code these values.
///
/// OAuth client ids are never committed; they are injected at build time:
/// `flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=... --dart-define=...`
class AppConfig {
  AppConfig._();

  static const String appName = 'Varna';
  static const String tagline = 'Your notes, kept in your own cloud.';
  static const String packageId = 'com.qavedik.varna';
  static const String iCloudContainerId = 'iCloud.com.qavedik.varna';

  /// OAuth client id of type "Web application" (used on web).
  static const String googleWebClientId =
      String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  /// OAuth client id of type "iOS" (used on iOS).
  static const String googleIosClientId =
      String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  /// Web client id used as `serverClientId` on Android/iOS (optional).
  static const String googleServerClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  // Free plan limits.
  static const int freeNotebookLimit = 5;
  static const int freeScansPerMonth = 10;
  static const int freeTranscriptsPerMonth = 5;

  // Plus plan.
  static const String plusPrice = '₹299/year';
  static const int plusPriceInr = 299;
  static const int trialDays = 7;
  static const String trialCopy = '7-day free trial';

  /// Folders offered for scanned papers, in display order. The last entry is
  /// the fallback bucket.
  static const List<String> paperFolders = <String>[
    'Insurance',
    'Vehicle',
    'Warranties',
    'Bills',
    'Other',
  ];
}
