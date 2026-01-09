import 'package:flutter/material.dart';
import '../../../../models/object_file.dart';

/// 新建文件夹对话框
Future<void> showCreateFolderDialog(
  BuildContext context, {
  required List<ObjectFile> existingObjects,
  required Future<void> Function(String folderName) onCreate,
}) async {
  final TextEditingController controller = TextEditingController();
  final formKey = GlobalKey<FormState>();
  String? errorText;

  await showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('新建文件夹'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: '文件夹名称',
              hintText: '请输入文件夹名称',
              errorText: errorText,
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return '请输入文件夹名称';
              }
              if (value.contains('/') || value.contains('\\')) {
                return '名称不能包含 / 或 \\';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!(formKey.currentState?.validate() ?? false)) return;

              final folderName = controller.text.trim();
              if (existingObjects.any(
                (obj) => obj.name == folderName && obj.type == ObjectType.folder,
              )) {
                setState(() {
                  errorText = '文件夹已存在';
                });
                return;
              }

              Navigator.pop(context);
              await onCreate(folderName);
            },
            child: const Text('创建'),
          ),
        ],
      ),
    ),
  );
}

/// 重命名对话框
Future<void> showRenameDialog(
  BuildContext context, {
  required ObjectFile objectFile,
  required List<ObjectFile> existingObjects,
  required Future<void> Function(String newName) onRename,
}) async {
  final isFolder = objectFile.type == ObjectType.folder;
  final TextEditingController controller =
      TextEditingController(text: objectFile.name);
  final formKey = GlobalKey<FormState>();
  String? errorText;

  await showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(isFolder ? '重命名文件夹' : '重命名文件'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: isFolder ? '文件夹名称' : '文件名称',
              hintText: '请输入新名称',
              errorText: errorText,
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return '请输入名称';
              }
              if (value.contains('/') || value.contains('\\')) {
                return '名称不能包含 / 或 \\';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!(formKey.currentState?.validate() ?? false)) return;

              final newName = controller.text.trim();

              if (newName == objectFile.name) {
                Navigator.pop(context);
                return;
              }

              if (existingObjects.any((o) => o.name == newName)) {
                setState(() {
                  errorText = isFolder ? '文件夹已存在' : '文件已存在';
                });
                return;
              }

              Navigator.pop(context);
              await onRename(newName);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    ),
  );
}

/// 删除确认结果
class DeleteConfirmResult {
  final bool confirmed;
  final bool deleteLocal;

  DeleteConfirmResult({required this.confirmed, this.deleteLocal = false});
}

/// 删除确认对话框
Future<DeleteConfirmResult> showDeleteConfirmDialog(
  BuildContext context, {
  required String objectName,
  bool hasLocalFile = false,
}) async {
  return _showDeleteConfirmDialogImpl(
    context,
    title: '确认删除',
    message: '确定要删除 $objectName 吗？',
    hasLocalFile: hasLocalFile,
  );
}

/// 批量删除确认对话框
Future<DeleteConfirmResult> showBatchDeleteConfirmDialog(
  BuildContext context, {
  required int fileCount,
  bool hasLocalFiles = false,
}) async {
  return _showDeleteConfirmDialogImpl(
    context,
    title: '确认删除',
    message: '确定要删除选中的 $fileCount 个文件吗？此操作不可恢复。',
    hasLocalFile: hasLocalFiles,
  );
}

/// 通用删除确认对话框实现
Future<DeleteConfirmResult> _showDeleteConfirmDialogImpl(
  BuildContext context, {
  required String title,
  required String message,
  required bool hasLocalFile,
}) async {
  bool deleteLocal = false;

  final confirmed = await showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message),
            if (hasLocalFile) ...[
              const SizedBox(height: 16),
              CheckboxListTile(
                title: const Text('同时删除本地文件'),
                value: deleteLocal,
                onChanged: (value) {
                  setState(() {
                    deleteLocal = value ?? false;
                  });
                },
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    ),
  );
  return DeleteConfirmResult(confirmed: confirmed == true, deleteLocal: deleteLocal);
}
