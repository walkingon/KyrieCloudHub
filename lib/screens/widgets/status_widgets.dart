import 'package:flutter/material.dart';

/// 加载状态枚举
enum LoadingState { idle, loading, success, error }

/// 状态显示组件（仅用于 loading/error 状态）
class StatusWidgets extends StatelessWidget {
  final LoadingState loadingState;
  final String errorMessage;
  final VoidCallback onRetry;

  const StatusWidgets({
    super.key,
    required this.loadingState,
    required this.errorMessage,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    switch (loadingState) {
      case LoadingState.loading:
        return const LinearProgressIndicator();
      case LoadingState.error:
        return Container(
          padding: const EdgeInsets.all(16),
          color: Colors.red.shade50,
          child: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.red),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '加载失败',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      errorMessage,
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ),
        );
      case LoadingState.success:
      case LoadingState.idle:
        return Container();
    }
  }
}
