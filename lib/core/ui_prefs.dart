import 'package:shared_preferences/shared_preferences.dart';

/// Small persisted UI preferences for the redesign (all default false except
/// nothing; the app starts in Simple view, on the onboarding flow).
class UiPrefs {
  static const _kAdvanced = 'ui_advanced_v1';
  static const _kOnboarded = 'ui_onboarded_v1';
  static const _kAutoConnect = 'ui_autoconnect_v1';
  static const _kAutoSelect = 'ui_autoselect_v1';
  static const _kDarkMode = 'ui_darkmode_v1';
  static const _kHomeMap = 'ui_homemap_v1';
  static const _kAlwaysOn = 'ui_alwayson_v1';

  final bool advanced;
  final bool onboarded;
  final bool autoConnect;
  final bool autoSelect;
  final bool darkMode;
  final bool homeMap; // home shows the map view instead of the server list
  // Opt-in for Android's Always-on VPN: when true the native service may
  // reconnect the last server on a system-initiated start.
  final bool alwaysOn;

  const UiPrefs({
    this.advanced = false,
    this.onboarded = false,
    this.autoConnect = false,
    this.autoSelect = true,
    this.darkMode = false,
    this.homeMap = false,
    this.alwaysOn = false,
  });

  UiPrefs copyWith({
    bool? advanced,
    bool? onboarded,
    bool? autoConnect,
    bool? autoSelect,
    bool? darkMode,
    bool? homeMap,
    bool? alwaysOn,
  }) =>
      UiPrefs(
        advanced: advanced ?? this.advanced,
        onboarded: onboarded ?? this.onboarded,
        autoConnect: autoConnect ?? this.autoConnect,
        autoSelect: autoSelect ?? this.autoSelect,
        darkMode: darkMode ?? this.darkMode,
        homeMap: homeMap ?? this.homeMap,
        alwaysOn: alwaysOn ?? this.alwaysOn,
      );

  static Future<UiPrefs> load() async {
    final p = await SharedPreferences.getInstance();
    return UiPrefs(
      advanced: p.getBool(_kAdvanced) ?? false,
      onboarded: p.getBool(_kOnboarded) ?? false,
      autoConnect: p.getBool(_kAutoConnect) ?? false,
      autoSelect: p.getBool(_kAutoSelect) ?? true,
      darkMode: p.getBool(_kDarkMode) ?? false,
      homeMap: p.getBool(_kHomeMap) ?? false,
      alwaysOn: p.getBool(_kAlwaysOn) ?? false,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kAdvanced, advanced);
    await p.setBool(_kOnboarded, onboarded);
    await p.setBool(_kAutoConnect, autoConnect);
    await p.setBool(_kAutoSelect, autoSelect);
    await p.setBool(_kDarkMode, darkMode);
    await p.setBool(_kHomeMap, homeMap);
    await p.setBool(_kAlwaysOn, alwaysOn);
  }
}
