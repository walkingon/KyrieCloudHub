import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/platform_credential.dart';
import '../models/platform_type.dart';
import '../services/cloud_platform_factory.dart';
import '../services/storage_service.dart';

class LoginDialog extends StatefulWidget {
  final PlatformType platform;

  const LoginDialog({super.key, required this.platform});

  @override
  _LoginDialogState createState() => _LoginDialogState();
}

class _LoginDialogState extends State<LoginDialog> {
  final _secretIdController = TextEditingController();
  final _secretKeyController = TextEditingController();
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('登录 ${widget.platform.displayName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _secretIdController,
            decoration: InputDecoration(labelText: 'SecretID'),
          ),
          TextField(
            controller: _secretKeyController,
            decoration: InputDecoration(labelText: 'SecretKey'),
            obscureText: true,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('取消')),
        ElevatedButton(
          onPressed: _isLoading ? null : _login,
          child: _isLoading ? CircularProgressIndicator() : Text('登录'),
        ),
      ],
    );
  }

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
    });

    final credential = PlatformCredential(
      platformType: widget.platform,
      secretId: _secretIdController.text,
      secretKey: _secretKeyController.text,
      region: 'ap-beijing', // 默认区域
    );

    final factory = Provider.of<CloudPlatformFactory>(context, listen: false);
    final api = factory.createApi(widget.platform, credential: credential);
    if (api != null) {
      final result = await api.listBuckets();
      if (result.success) {
        final storage = Provider.of<StorageService>(context, listen: false);
        await storage.saveCredential(credential);
        await storage.saveLastPlatform(widget.platform);
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('登录失败: ${result.errorMessage}')));
      }
    }

    setState(() {
      _isLoading = false;
    });
  }
}
