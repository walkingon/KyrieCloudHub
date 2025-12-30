import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/platform_type.dart';
import '../services/cloud_platform_factory.dart';
import '../services/storage_service.dart';
import '../utils/logger.dart';
import 'platform_selection_screen.dart';
import 'transfer_queue_screen.dart';
import 'settings_screen.dart';
import 'about_screen.dart';
import 'bucket_objects_screen.dart';

// ignore_for_file: library_private_types_in_public_api

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  PlatformType? _currentPlatform;
  List<dynamic> _buckets = [];

  @override
  void initState() {
    super.initState();
    logUi('MainScreen initialized');
    _loadLastPlatform();
  }

  Future<void> _loadLastPlatform() async {
    final storage = Provider.of<StorageService>(context, listen: false);
    final lastPlatform = await storage.getLastPlatform();
    if (lastPlatform != null) {
      setState(() {
        _currentPlatform = lastPlatform;
      });
      logUi('Auto-loaded last platform: ${lastPlatform.displayName}');
      _loadBuckets();
    } else {
      logUi('No last platform found, showing empty state');
    }
  }

  Future<void> _loadBuckets() async {
    if (_currentPlatform == null) return;
    logUi('Loading buckets for platform: ${_currentPlatform!.displayName}');
    final factory = Provider.of<CloudPlatformFactory>(context, listen: false);
    final api = factory.createApi(_currentPlatform!);
    if (api != null) {
      final result = await api.listBuckets();
      if (result.success) {
        setState(() {
          _buckets = result.data ?? [];
        });
        logUi('Loaded ${_buckets.length} buckets');
      } else {
        logError('Failed to load buckets: ${result.errorMessage}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentPlatform?.displayName ?? ''),
        centerTitle: true,
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            DrawerHeader(
              decoration: BoxDecoration(color: Theme.of(context).primaryColor),
              child: Text(
                'KyrieCloudHub',
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
            ),
            ListTile(
              leading: Icon(Icons.swap_horiz),
              title: Text('平台切换'),
              onTap: () {
                logUi('User tapped: 平台切换');
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PlatformSelectionScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.queue),
              title: Text('传输队列'),
              onTap: () {
                logUi('User tapped: 传输队列');
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TransferQueueScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.settings),
              title: Text('设置'),
              onTap: () {
                logUi('User tapped: 设置');
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => SettingsScreen()),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.info),
              title: Text('关于'),
              onTap: () {
                logUi('User tapped: 关于');
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => AboutScreen()),
                );
              },
            ),
          ],
        ),
      ),
      body: _currentPlatform == null
          ? Center(
              child: ElevatedButton(
                onPressed: () {
                  logUi('User tapped: 去选择平台');
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PlatformSelectionScreen(),
                    ),
                  );
                },
                child: Text('去选择平台'),
              ),
            )
          : ListView.builder(
              itemCount: _buckets.length,
              itemBuilder: (context, index) {
                final bucket = _buckets[index];
                return ListTile(
                  title: Text(bucket.name),
                  onTap: () {
                    logUi('User tapped bucket: ${bucket.name}');
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => BucketObjectsScreen(
                          bucket: bucket,
                          platform: _currentPlatform!,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
