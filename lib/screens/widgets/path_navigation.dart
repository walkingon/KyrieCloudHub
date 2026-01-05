import 'package:flutter/material.dart';

/// 路径导航组件
class PathNavigation extends StatelessWidget {
  final List<String> pathSegments;
  final VoidCallback onNavigateToRoot;
  final Function(String prefix) onNavigateToPrefix;

  const PathNavigation({
    super.key,
    required this.pathSegments,
    required this.onNavigateToRoot,
    required this.onNavigateToPrefix,
  });

  @override
  Widget build(BuildContext context) {
    if (pathSegments.isEmpty) {
      return Container();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.grey.shade100,
      child: Row(
        children: [
          // 返回根目录按钮
          TextButton.icon(
            icon: const Icon(Icons.home, size: 18),
            label: const Text('根目录'),
            onPressed: onNavigateToRoot,
          ),
          const Text(' / '),
          // 路径分段
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: _buildPathChips(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPathChips() {
    final chips = <Widget>[];

    for (int i = 0; i < pathSegments.length; i++) {
      if (i > 0) {
        chips.add(const Text(' / '));
      }

      final isLast = i == pathSegments.length - 1;
      // 构建到当前 segment 的前缀路径：segments[0..i] + '/'
      final prefix = '${pathSegments.sublist(0, i + 1).join('/')}/';

      chips.add(
        ActionChip(
          label: Text(
            pathSegments[i],
            style: TextStyle(
              color: isLast ? Colors.blue : Colors.black87,
              fontWeight: isLast ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
          onPressed: isLast ? null : () => onNavigateToPrefix(prefix),
          avatar: isLast ? null : const Icon(Icons.folder, size: 16),
        ),
      );
    }

    return chips;
  }
}
