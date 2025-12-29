import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/platform_type.dart';
import '../services/cloud_platform_factory.dart';
import '../services/storage_service.dart';
import 'platform_selection_screen.dart';
import 'transfer_queue_screen.dart';
import 'settings_screen.dart';
import 'about_screen.dart';
import 'bucket_objects_screen.dart';

class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  PlatformType? _currentPlatform;
  List<dynamic> _buckets = [];

  @override
  void initState() {
    super.initState();
    _loadLastPlatform();
  }

  Future<void> _loadLastPlatform() async {
    final storage = Provider.of<StorageService>(context, listen: false);
    final lastPlatform = await storage.getLastPlatform();
    if (lastPlatform != null) {
      setState(() {
        _currentPlatform = lastPlatform;
      });
      _loadBuckets();
    }
  }

  Future<void> _loadBuckets() async {
    if (_currentPlatform == null) return;
    final factory = Provider.of<CloudPlatformFactory>(context, listen: false);
    final api = factory.createApi(_currentPlatform!);
    if (api != null) {
      final result = await api.listBuckets();
      if (result.success) {
        setState(() {
          _buckets = result.data ?? [];
        });
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
