import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

/// 日志类型枚举
enum LogType {
  ui, // 用户界面操作
  network, // 网络请求与响应
  error, // 运行时异常错误
  info, // 普通信息
}

/// 日志级别
enum LogLevel { debug, info, warning, error }

class Logger {
  static final Logger _instance = Logger._internal();
  factory Logger() => _instance;
  Logger._internal();

  static const String _logFileName = 'kyrie_cloud_hub.log';

  File? _logFile;
  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss.SSS');
  static const int _maxFileSize = 1024 * 1024; // 1MB
  static const int _maxFileCount = 2; // 最多保留2个日志文件

  bool _initialized = false;
  String? _logFilePath;

  /// 初始化日志系统
  Future<void> init() async {
    if (_initialized) return;

    if (kDebugMode) {
      final directory = await getApplicationSupportDirectory();
      _logFilePath = '${directory.path}/$_logFileName';
      print('Log file path: $_logFilePath');
      _logFile = File(_logFilePath!);

      // 同步清理旧日志（使用同步方法确保立即可用）
      try {
        final files =
            directory
                .listSync()
                .whereType<File>()
                .where(
                  (f) =>
                      f.path.endsWith('.log') &&
                      f.path.contains('kyrie_cloud_hub'),
                )
                .toList()
              ..sort(
                (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
              );

        if (files.length > _maxFileCount) {
          for (int i = _maxFileCount; i < files.length; i++) {
            files[i].deleteSync();
          }
        }
      } catch (_) {
        // 忽略清理错误
      }

      // 清空日志文件
      _logFile!.writeAsStringSync('');

      _initialized = true;
      _writeSync('Logger initialized - Application started');
    }
  }

  /// 同步写入日志
  void _writeSync(String message) {
    if (_logFilePath == null) return;

    try {
      // 检查文件大小并轮转
      final file = File(_logFilePath!);
      if (file.existsSync()) {
        final currentSize = file.lengthSync();
        if (currentSize >= _maxFileSize) {
          final oldFile = File('$_logFilePath.old');
          if (oldFile.existsSync()) oldFile.deleteSync();
          file.renameSync('$_logFilePath.old');
          file.writeAsStringSync('');
        }
      }
      file.writeAsStringSync('$message\n', mode: FileMode.append);
    } catch (e) {
      // 忽略写入错误
    }
  }

  /// 写入日志
  void log(LogType type, String message, [LogLevel level = LogLevel.debug]) {
    if (!kDebugMode) return;
    if (!_initialized) return;

    final timestamp = _dateFormat.format(DateTime.now());
    final levelStr = level.toString().split('.').last.toUpperCase().padRight(7);
    final typeStr = type.toString().split('.').first.toUpperCase().padRight(8);
    final logLine = '[$timestamp] [$levelStr] [$typeStr] $message';

    // 控制台输出
    // ignore: avoid_print
    print(logLine);

    // 同步写入文件
    _writeSync(logLine);
  }

  /// 用户界面操作日志
  void ui(String message) => log(LogType.ui, message, LogLevel.info);

  /// 网络请求日志
  void network(String message) => log(LogType.network, message);

  /// 网络请求开始
  void networkRequest(
    String method,
    String url, [
    Map<String, dynamic>? params,
  ]) {
    String paramsStr = '';
    if (params != null) {
      // 处理大型数据（如 Uint8List），避免打印巨量数据
      final processedParams = <String, dynamic>{};
      for (final entry in params.entries) {
        final value = entry.value;
        if (value is Uint8List) {
          processedParams[entry.key] = '<Uint8List: ${value.length} bytes>';
        } else if (value is List && value.isNotEmpty && value[0] is int) {
          // 可能是字节列表
          processedParams[entry.key] = '<List<int>: ${value.length} elements>';
        } else {
          processedParams[entry.key] = value;
        }
      }
      paramsStr = ' Params: $processedParams';
    }
    log(LogType.network, '[REQUEST] $method $url$paramsStr', LogLevel.info);
  }

  /// 网络响应日志
  void networkResponse(String url, int statusCode, [dynamic response]) {
    String responseStr = '';
    if (response != null) {
      final responseStrRaw = response.toString();
      // 限制响应数据长度，避免日志过大
      responseStr = responseStrRaw.length > 1000
          ? ' Response: ${responseStrRaw.substring(0, 1000)}... [${responseStrRaw.length} chars total]'
          : ' Response: $responseStrRaw';
    }
    final level = statusCode >= 400 ? LogLevel.error : LogLevel.info;
    log(
      LogType.network,
      '[RESPONSE] $url Status: $statusCode$responseStr',
      level,
    );
  }

  /// 网络错误日志
  void networkError(String url, dynamic error) {
    String errorStr = error.toString();
    // 限制错误信息长度
    if (errorStr.length > 2000) {
      errorStr =
          '${errorStr.substring(0, 2000)}... [${errorStr.length} chars total]';
    }
    log(LogType.network, '[ERROR] $url Error: $errorStr', LogLevel.error);
  }

  /// 异常错误日志
  void error(String message, [dynamic stackTrace]) {
    final stackStr = stackTrace != null ? '\nStackTrace: $stackTrace' : '';
    log(LogType.error, '$message$stackStr', LogLevel.error);
  }

  /// 警告日志
  void warning(String message) => log(LogType.info, message, LogLevel.warning);

  /// 信息日志
  void info(String message) => log(LogType.info, message, LogLevel.info);

  /// 调试日志
  void debug(String message) => log(LogType.info, message, LogLevel.debug);

  /// 获取日志文件路径
  String? getLogFilePath() => _logFilePath;

  /// 读取日志文件内容
  String? readLogs() {
    if (_logFilePath == null) return null;
    try {
      final file = File(_logFilePath!);
      if (file.existsSync()) {
        return file.readAsStringSync();
      }
    } catch (_) {}
    return null;
  }

  /// 清空日志文件
  void clearLogs() {
    if (_logFilePath != null) {
      try {
        File(_logFilePath!).writeAsStringSync('');
      } catch (_) {}
    }
  }
}

/// 全局日志实例
final logger = Logger();

/// 便捷函数：记录UI操作
void logUi(String message) => logger.ui(message);

/// 便捷函数：记录网络请求
void logNetworkRequest(
  String method,
  String url, [
  Map<String, dynamic>? params,
]) => logger.networkRequest(method, url, params);

/// 便捷函数：记录网络响应
void logNetworkResponse(String url, int statusCode, [dynamic response]) =>
    logger.networkResponse(url, statusCode, response);

/// 便捷函数：记录网络错误
void logNetworkError(String url, dynamic error) =>
    logger.networkError(url, error);

/// 便捷函数：记录错误
void logError(String message, [dynamic stackTrace]) =>
    logger.error(message, stackTrace);

/// 原始日志函数（向后兼容）- 同时输出到控制台和写入文件
void log(dynamic message) {
  if (kDebugMode) {
    // 控制台输出
    // ignore: avoid_print
    print(message);
    // 同步写入文件
    if (logger.getLogFilePath() != null) {
      logger._writeSync(message.toString());
    }
  }
}
