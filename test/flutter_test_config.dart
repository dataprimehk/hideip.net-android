import 'dart:async';

import 'package:hideip_vpn/core/secret_prefs.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  SecretPrefs.installKeyVaultForTesting(MemorySecureKeyVault());
  await testMain();
}
