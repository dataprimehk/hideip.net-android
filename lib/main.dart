import 'package:flutter/material.dart';

import 'state/app_state.dart';
import 'ui/brand.dart';
import 'ui/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  state.init();
  runApp(HideipApp(state: state));
}

class HideipApp extends StatelessWidget {
  final AppState state;
  const HideipApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'hideip',
      debugShowCheckedModeBanner: false,
      // Light + dark, following the system setting (matches the website,
      // which ships both :root and .dark token sets).
      theme: Brand.theme(Brightness.light),
      darkTheme: Brand.theme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: HomeScreen(state: state),
    );
  }
}
