import 'package:flutter/material.dart';
import '../../../../models/object_file.dart';
import '../../../../utils/file_type_helper.dart';

/// 网格项组件
class ObjectGridItem extends StatelessWidget {
  final ObjectFile objectFile;
  final bool isSelected;
  final bool isSelectionMode;
  final bool isFolder;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onCheckboxChanged;

  const ObjectGridItem({
    super.key,
    required this.objectFile,
    required this.isSelected,
    required this.isSelectionMode,
    required this.isFolder,
    required this.onTap,
    required this.onLongPress,
    required this.onCheckboxChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey.shade300,
          ),
          borderRadius: BorderRadius.circular(8),
          color:
              isSelected ? Colors.blue.withValues(alpha: 0.1) : Colors.white,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FileTypeHelper.getIcon(objectFile),
              size: 48,
              color: FileTypeHelper.getColor(objectFile),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                objectFile.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: isSelected ? Colors.blue : Colors.black87,
                ),
              ),
            ),
            if (!isFolder)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _formatBytes(objectFile.size),
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ),
            if (isFolder && isSelectionMode)
              Checkbox(
                value: isSelected,
                onChanged: (value) => onCheckboxChanged(),
              ),
          ],
        ),
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
}
