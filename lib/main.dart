import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/ui_prefs.dart';
import 'state/app_state.dart';
import 'ui/brand.dart';
import 'ui/redesign/shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The whole UI is a vertical composition (hero over content); landscape
  // is not a supported layout. Revisit for iPad, which frowns on locked
  // orientation.
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final state = AppState();
  state.init();
  runApp(HideipApp(state: state));
}

class HideipApp extends StatelessWidget {
  final AppState state;
  const HideipApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    // The palette is a setting with three states, and "System" is the
    // default. Both themes are handed to MaterialApp so the platform answer
    // is applied by the framework; the redesign's own tokens resolve against
    // the same choice inside the shell.
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => MaterialApp(
        title: 'hideip',
        debugShowCheckedModeBanner: false,
        theme: Brand.theme(Brightness.light),
        darkTheme: Brand.theme(Brightness.dark),
        themeMode: _materialMode(state.prefs.themeMode),
        home: HipShell(state: state),
      ),
    );
  }

  static ThemeMode _materialMode(AppThemeMode mode) => switch (mode) {
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
        AppThemeMode.system => ThemeMode.system,
      };
}
