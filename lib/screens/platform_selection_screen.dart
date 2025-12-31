import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/platform_type.dart';
import '../services/storage_service.dart';
import '../utils/logger.dart';
import 'login_dialog.dart';

// ignore_for_file: library_private_types_in_public_api, use_build_context_synchronously

class PlatformSelectionScreen extends StatefulWidget {
  const PlatformSelectionScreen({super.key});

  @override
  _PlatformSelectionScreenState createState() =>
      _PlatformSelectionScreenState();
}

class _PlatformSelectionScreenState extends State<PlatformSelectionScreen> {
  Map<PlatformType, bool> _loginStatus = {};

  @override
  void initState() {
    super.initState();
    logUi('PlatformSelectionScreen initialized');
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
                      logUi('User tapped logout for: ${platform.displayName}');
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
                logUi('User selected platform: ${platform.displayName} - showing login dialog');
                final result = await showDialog(
                  context: context,
                  builder: (context) => LoginDialog(platform: platform),
                );
                if (result == true) {
                  logUi('User logged in successfully: ${platform.displayName}');
                  _loadLoginStatus();
                  if (mounted) {
                    Navigator.pop(context);
                  }
                } else {
                  logUi('User cancelled login for: ${platform.displayName}');
                }
              } else {
                logUi('User selected already logged in platform: ${platform.displayName} - returning');
                // 保存最后选择的平台
                final storage = Provider.of<StorageService>(context, listen: false);
                await storage.saveLastPlatform(platform);
                if (mounted) {
                  Navigator.pop(context);
                }
              }
            },
          );
        }).toList(),
      ),
    );
  }
}
