import 'package:flutter/foundation.dart';

/// 自定义日志函数，仅在debug模式下打印
void log(dynamic message) {
  if (kDebugMode) {
    print(message);
  }
}
