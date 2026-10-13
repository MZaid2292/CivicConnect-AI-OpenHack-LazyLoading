import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class BackendMode {
  const BackendMode({required this.live});
  const BackendMode.local() : live = false;
  final bool live;
}

extension BackendModeContext on BuildContext {
  bool get isLiveBackend {
    try {
      return read<BackendMode>().live;
    } catch (_) {
      return false;
    }
  }
}
