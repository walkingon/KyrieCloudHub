import 'package:flutter/material.dart';
import '../../../../models/object_file.dart';
import '../../../../utils/file_type_helper.dart';

/// 列表项组件
class ObjectListItem extends StatelessWidget {
  final ObjectFile objectFile;
  final bool isSelected;
  final bool isSelectionMode;
  final bool isFolder;
  final bool isDownloaded;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onCheckboxChanged;

  const ObjectListItem({
    super.key,
    required this.objectFile,
    required this.isSelected,
    required this.isSelectionMode,
    required this.isFolder,
    this.isDownloaded = false,
    required this.onTap,
    required this.onLongPress,
    required this.onCheckboxChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isDownloaded && !isFolder)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.check_circle, color: Colors.green, size: 20),
            ),
          Icon(FileTypeHelper.getIcon(objectFile),
              color: FileTypeHelper.getColor(objectFile)),
        ],
      ),
      title:
          Text(objectFile.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: isFolder
          ? null
          : _buildSubtitle(),
      selected: isSelected,
      selectedTileColor: Colors.blue.withValues(alpha: 0.1),
      trailing: isFolder
          ? null
          : Checkbox(
              value: isSelected,
              onChanged: (value) => onCheckboxChanged(),
            ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }

  /// 构建副标题：显示大小、日期和非标准存储类型
  Widget _buildSubtitle() {
    final parts = <String>[
      _formatBytes(objectFile.size),
      _formatDate(objectFile.lastModified),
    ];

    // 非标准存储显示存储类型
    if (objectFile.shouldShowStorageClass) {
      parts.add(objectFile.storageClass!.displayName);
    }

    return Text(
      parts.join(' • '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: objectFile.shouldShowStorageClass ? Colors.grey.shade600 : null,
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '未知';
    final beijingTime = date.add(const Duration(hours: 8));
    return '${beijingTime.year}-${_pad(beijingTime.month)}-${_pad(beijingTime.day)} ${_pad(beijingTime.hour)}:${_pad(beijingTime.minute)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}
