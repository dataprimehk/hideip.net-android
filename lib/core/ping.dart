import 'dart:async';
import 'dart:io';

/// Result of a latency probe to a server's host:port.
sealed class PingResult {
  const PingResult();
}

class PingOk extends PingResult {
  final int ms;
  const PingOk(this.ms);
}

class PingFail extends PingResult {
  const PingFail();
}

/// Measures TCP connect time to [host]:[port], a practical proxy for server
/// latency that needs no special permission and no tunnel. This is the round
/// trip to *open* a socket, not an ICMP echo (Android blocks raw ICMP), so it
/// reflects reachability + RTT the way the proxy handshake will experience it.
class Ping {
  static Future<PingResult> measure(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final sw = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      sw.stop();
      return PingOk(sw.elapsedMilliseconds);
    } on SocketException {
      return const PingFail();
    } on TimeoutException {
      return const PingFail();
    } finally {
      socket?.destroy();
    }
  }
}
