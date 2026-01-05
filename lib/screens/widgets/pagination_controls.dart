import 'package:flutter/material.dart';

/// 排序模式枚举
enum SortMode { none, nameAsc, nameDesc, timeAsc, timeDesc }

/// 分页控制器组件
class PaginationControls extends StatelessWidget {
  final int currentPage;
  final bool hasMore;
  final bool isLoadingMore;
  final SortMode sortMode;
  final VoidCallback onPreviousPage;
  final VoidCallback onNextPage;
  final VoidCallback onSortByName;
  final VoidCallback onSortByTime;

  const PaginationControls({
    super.key,
    required this.currentPage,
    required this.hasMore,
    required this.isLoadingMore,
    required this.sortMode,
    required this.onPreviousPage,
    required this.onNextPage,
    required this.onSortByName,
    required this.onSortByTime,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          // 左侧排序按钮
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton.icon(
                icon: Icon(
                  sortMode == SortMode.nameAsc
                      ? Icons.arrow_upward
                      : sortMode == SortMode.nameDesc
                          ? Icons.arrow_downward
                          : Icons.sort_by_alpha,
                ),
                label: const Text('名称'),
                onPressed: onSortByName,
              ),
              TextButton.icon(
                icon: Icon(
                  sortMode == SortMode.timeAsc
                      ? Icons.arrow_upward
                      : sortMode == SortMode.timeDesc
                          ? Icons.arrow_downward
                          : Icons.schedule,
                ),
                label: const Text('时间'),
                onPressed: onSortByTime,
              ),
            ],
          ),
          // 分页导航
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 上一页
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: currentPage > 1 ? onPreviousPage : null,
                tooltip: '上一页',
              ),
              // 页码信息
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text('$currentPage', style: const TextStyle(fontSize: 14)),
              ),
              // 下一页
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: hasMore ? onNextPage : null,
                tooltip: '下一页',
                disabledColor: Colors.grey.shade400,
              ),
              // 加载更多指示器
              if (isLoadingMore)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          // 右侧占位
          const Spacer(),
        ],
      ),
    );
  }
}
