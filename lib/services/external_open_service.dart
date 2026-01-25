import 'dart:async';

import 'package:flutter/services.dart';

class ExternalOpenService {
  ExternalOpenService._();

  static final ExternalOpenService instance = ExternalOpenService._();

  static const MethodChannel _channel = MethodChannel(
    'com.sholo.imageconverter/external_open',
  );

  final StreamController<String> _streamController =
      StreamController<String>.broadcast();

  bool _initialized = false;

  Stream<String> get stream => _streamController.stream;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onOpenFile') {
        final path = call.arguments as String?;
        if (path != null && path.isNotEmpty) {
          _streamController.add(path);
        }
      }
    });
  }

  Future<String?> consumeInitialPath() async {
    return _channel.invokeMethod<String>('getInitialPath');
  }
}
