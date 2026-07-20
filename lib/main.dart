import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    return MaterialApp(
      title: 'hideip',
      debugShowCheckedModeBanner: false,
      // The 2.0 redesign ships one fixed palette on every platform: light
      // content surfaces under a dark hero panel. A system-driven dark
      // variant of the content surfaces is a later, deliberate pass.
      theme: Brand.theme(Brightness.light),
      home: HipShell(state: state),
    );
  }
}
