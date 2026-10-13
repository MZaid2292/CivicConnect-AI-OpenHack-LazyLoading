import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Whether the app runs against the live Supabase backend or the local
/// sample workflow (development and tests). Screens use it only to keep
/// labels truthful — e.g. no "demo" wording on real accounts.
class BackendMode {
  const BackendMode({required this.live});
  const BackendMode.local() : live = false;
  final bool live;
}

extension BackendModeContext on BuildContext {
  /// True when data comes from Supabase. Defaults to local when no mode is
  /// provided (isolated widget tests).
  bool get isLiveBackend {
    try {
      return read<BackendMode>().live;
    } catch (_) {
      return false;
    }
  }
}
