import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/main_screen.dart';
import 'services/cloud_platform_factory.dart';
import 'services/storage_service.dart';
import 'services/api/http_client.dart';
import 'utils/logger.dart';

void main() {
  log('Starting KyrieCloudHub app');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<StorageService>(create: (_) => StorageService()),
        Provider<HttpClient>(create: (_) => HttpClient()),
        Provider<CloudPlatformFactory>(
          create: (context) => CloudPlatformFactory(
            Provider.of<HttpClient>(context, listen: false),
          ),
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
