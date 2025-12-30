import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/platform_credential.dart';
import '../models/platform_type.dart';
import '../services/cloud_platform_factory.dart';
import '../services/storage_service.dart';
import '../utils/logger.dart';

// ignore_for_file: library_private_types_in_public_api, use_build_context_synchronously

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
  void initState() {
    super.initState();
    logUi('LoginDialog initialized for: ${widget.platform.displayName}');
  }

  @override
  Widget build(BuildContext context) {
    // 根据平台类型选择合适的占位符文本
    final isAliyun = widget.platform == PlatformType.aliCloud;
    final idLabel = isAliyun ? 'AccessKey ID' : 'SecretID';
    final keyLabel = isAliyun ? 'AccessKey Secret' : 'SecretKey';

    return AlertDialog(
      title: Text('登录 ${widget.platform.displayName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _secretIdController,
            decoration: InputDecoration(labelText: idLabel),
          ),
          TextField(
            controller: _secretKeyController,
            decoration: InputDecoration(labelText: keyLabel),
            obscureText: true,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            logUi('User cancelled login for: ${widget.platform.displayName}');
            Navigator.pop(context);
          },
          child: Text('取消'),
        ),
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

    logUi('Starting login for: ${widget.platform.displayName}');

    // 使用 PlatformCredential 的默认地域（ap-beijing）
    // 阿里云API会根据平台类型自动转换为正确的地域格式
    final credential = PlatformCredential(
      platformType: widget.platform,
      secretId: _secretIdController.text,
      secretKey: _secretKeyController.text,
    );

    final factory = Provider.of<CloudPlatformFactory>(context, listen: false);
    final api = factory.createApi(widget.platform, credential: credential);
    if (api != null) {
      final result = await api.listBuckets();
      if (result.success) {
        logUi('Login successful for: ${widget.platform.displayName}');
        final storage = Provider.of<StorageService>(context, listen: false);
        await storage.saveCredential(credential);
        await storage.saveLastPlatform(widget.platform);
        if (mounted) {
          Navigator.pop(context, true);
        }
      } else {
        logError('Login failed for: ${widget.platform.displayName} - ${result.errorMessage}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('登录失败: ${result.errorMessage}')),
          );
        }
      }
    } else {
      logError('Failed to create API for: ${widget.platform.displayName}');
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }
}
