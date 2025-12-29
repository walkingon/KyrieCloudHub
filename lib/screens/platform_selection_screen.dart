import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/platform_type.dart';
import '../services/storage_service.dart';
import 'login_dialog.dart';

class PlatformSelectionScreen extends StatefulWidget {
  @override
  _PlatformSelectionScreenState createState() =>
      _PlatformSelectionScreenState();
}

class _PlatformSelectionScreenState extends State<PlatformSelectionScreen> {
  Map<PlatformType, bool> _loginStatus = {};

  @override
  void initState() {
    super.initState();
    _loadLoginStatus();
  }

  Future<void> _loadLoginStatus() async {
    final storage = Provider.of<StorageService>(context, listen: false);
    final status = <PlatformType, bool>{};
    for (final platform in PlatformType.values) {
      final credential = await storage.getCredential(platform);
      status[platform] = credential != null;
    }
    setState(() {
      _loginStatus = status;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('选择平台')),
      body: ListView(
        children: PlatformType.values.map((platform) {
          final isLoggedIn = _loginStatus[platform] ?? false;
          return ListTile(
            title: Text(platform.displayName),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLoggedIn) Icon(Icons.check, color: Colors.green),
                if (isLoggedIn)
                  TextButton(
                    onPressed: () async {
                      final storage = Provider.of<StorageService>(
                        context,
                        listen: false,
                      );
                      await storage.clearCredential(platform);
                      _loadLoginStatus();
                    },
                    child: Text('登出'),
                  ),
              ],
            ),
            onTap: () async {
              if (!isLoggedIn) {
                final result = await showDialog(
                  context: context,
                  builder: (context) => LoginDialog(platform: platform),
                );
                if (result == true) {
                  _loadLoginStatus();
                  Navigator.pop(context);
                }
              } else {
                // 直接登录
                Navigator.pop(context);
              }
            },
          );
        }).toList(),
      ),
    );
  }
}
