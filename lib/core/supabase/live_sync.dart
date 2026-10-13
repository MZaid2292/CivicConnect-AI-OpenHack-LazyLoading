import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LiveSync {
  LiveSync(
    this._client, {
    required this.refreshAll,
    required this.clearAll,
    this.pollEvery = const Duration(seconds: 60),
  });

  final SupabaseClient _client;
  final Future<void> Function() refreshAll;
  final void Function() clearAll;
  final Duration pollEvery;

  static const tables = [
    'complaints',
    'complaint_updates',
    'complaint_comments',
    'complaint_support',
    'complaint_images',
    'duplicate_candidates',
    'jobs',
    'contracts',
    'bids',
    'work_evidence',
    'inspections',
    'payments',
    'contractors',
    'notifications',
  ];

  RealtimeChannel? _channel;
  Timer? _poll;
  Timer? _debounce;
  StreamSubscription<AuthState>? _authSub;
  AppLifecycleListener? _lifecycle;

  void start() {
    _authSub = _client.auth.onAuthStateChange.listen((s) {
      if (s.session == null) {
        _stop();
        clearAll();
      } else {
        _begin();
      }
    });
    _lifecycle = AppLifecycleListener(onResume: () {
      if (_client.auth.currentSession != null) _refresh();
    });
  }

  void _begin() {
    if (_channel != null) return;
    var channel = _client.channel('civicconnect-live');
    for (final table in tables) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) => _scheduleRefresh(),
      );
    }
    _channel = channel..subscribe();
    _poll = Timer.periodic(pollEvery, (_) => _refresh());
  }

  void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _refresh);
  }

  void _refresh() => refreshAll().catchError((Object _) {});

  void _stop() {
    _poll?.cancel();
    _poll = null;
    _debounce?.cancel();
    final channel = _channel;
    _channel = null;
    if (channel != null) _client.removeChannel(channel);
  }

  void dispose() {
    _stop();
    _authSub?.cancel();
    _lifecycle?.dispose();
  }
}
