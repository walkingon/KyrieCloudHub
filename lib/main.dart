import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/main_screen.dart';
import 'services/cloud_platform_factory.dart';
import 'services/storage_service.dart';
import 'utils/file_path_helper.dart';
import 'utils/logger.dart';

void main() async {
  // 初始化 Flutter 绑定（必须在调用任何平台 API 之前）
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化日志系统
  await logger.init();

  // 初始化系统下载目录
  await FilePathHelper.initSystemDownloadsDirectory();

  // 设置全局错误捕获
  FlutterError.onError = (details) {
    logError('Flutter Error: ${details.exception}', details.stack);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    logError('Platform Error: $error', stack);
    return true; // 阻止应用崩溃
  };

  if (kDebugMode) {
    log('Starting KyrieCloudHub app');
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<StorageService>(create: (_) => StorageService()),
        Provider<CloudPlatformFactory>(
          create: (_) => CloudPlatformFactory(),
        ),
      ],
      child: MaterialApp(
        title: 'KyrieCloudHub',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: MainScreen(),
      ),
    );
  }
}
