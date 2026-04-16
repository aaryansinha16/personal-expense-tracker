import 'dart:async';

import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../screens/import_email_screen.dart';

/// Listens for text/HTML shared into the app from other apps (email clients,
/// browsers). Opens ImportEmailScreen pre-filled with the shared body.
class ShareReceiver {
  final GlobalKey<NavigatorState> navigatorKey;
  StreamSubscription<List<SharedMediaFile>>? _sub;

  ShareReceiver(this.navigatorKey);

  Future<void> start() async {
    // Cold-start share: app was launched by a share action.
    final initial = await ReceiveSharingIntent.instance.getInitialMedia();
    _handle(initial);
    ReceiveSharingIntent.instance.reset();

    // Warm-start share: app was already running.
    _sub = ReceiveSharingIntent.instance.getMediaStream().listen(_handle);
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  void _handle(List<SharedMediaFile> items) {
    if (items.isEmpty) return;
    // receive_sharing_intent surfaces plain text and HTML shares through
    // SharedMediaFile with type == text, and the content lives in `path`.
    final first = items.firstWhere(
      (m) => m.type == SharedMediaType.text || m.type == SharedMediaType.url,
      orElse: () => items.first,
    );
    final content = first.path;
    if (content.trim().isEmpty) return;

    // Best-effort: if the share has multiple parts the first might be the
    // subject and the rest body, but email clients vary. We just pipe
    // everything into the body and let the parser figure it out.
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    navigator.push(MaterialPageRoute(
      builder: (_) => ImportEmailScreen(initialBody: content),
    ));
  }
}
