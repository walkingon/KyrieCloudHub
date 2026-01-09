import 'package:flutter/material.dart';
import '../models/object_file.dart';

/// 文件类型辅助工具类
/// 提供文件图标、颜色等配置信息
class FileTypeHelper {
  /// 图片文件扩展名列表
  static const _imageExtensions = {'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg'};

  /// 视频文件扩展名列表
  static const _videoExtensions = {'mp4', 'avi', 'mkv', 'mov', 'wmv', 'flv', 'webm'};

  /// 音频文件扩展名列表
  static const _audioExtensions = {'mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a'};

  /// Word文档扩展名
  static const _wordExtensions = {'doc', 'docx', 'txt', 'rtf'};

  /// Excel表格扩展名
  static const _excelExtensions = {'xls', 'xlsx', 'csv'};

  /// PPT演示文稿扩展名
  static const _pptExtensions = {'ppt', 'pptx'};

  /// 文档文件扩展名列表
  static const _documentExtensions = {'pdf'};

  /// 压缩文件扩展名列表
  static const _archiveExtensions = {'zip', 'rar', '7z', 'tar', 'gz'};

  /// 代码文件扩展名列表
  static const _codeExtensions = {
    'dart', 'js', 'ts', 'py', 'java', 'c', 'cpp', 'h',
    'html', 'css', 'json', 'yaml', 'yml',
  };

  /// 可执行文件扩展名列表
  static const _executableExtensions = {'exe', 'app', 'dmg'};

  /// 扩展名到图标的映射
  static final Map<String, IconData> _extensionIcons = {
    // 图片
    for (final ext in _imageExtensions) ext: Icons.image,
    // 视频
    for (final ext in _videoExtensions) ext: Icons.video_file,
    // 音频
    for (final ext in _audioExtensions) ext: Icons.audio_file,
    // 文档 - PDF
    for (final ext in _documentExtensions) ext: Icons.picture_as_pdf,
    // 文档 - Word
    for (final ext in _wordExtensions) ext: Icons.description,
    // 文档 - Excel
    for (final ext in _excelExtensions) ext: Icons.table_chart,
    // 文档 - PPT
    for (final ext in _pptExtensions) ext: Icons.slideshow,
    // 压缩文件
    for (final ext in _archiveExtensions) ext: Icons.archive,
    // 代码文件
    for (final ext in _codeExtensions) ext: Icons.code,
    // 可执行文件
    for (final ext in _executableExtensions) ext: Icons.play_circle_filled,
  };

  /// 扩展名到颜色的映射
  static final Map<String, Color> _extensionColors = {
    // 图片
    for (final ext in _imageExtensions) ext: Colors.purple,
    // 视频
    for (final ext in _videoExtensions) ext: Colors.pink,
    // 音频
    for (final ext in _audioExtensions) ext: Colors.cyan,
    // 文档 - PDF/Word
    for (final ext in {..._documentExtensions, ..._wordExtensions}) ext: Colors.blue,
    // 文档 - Excel
    for (final ext in _excelExtensions) ext: Colors.green,
    // 文档 - PPT
    for (final ext in _pptExtensions) ext: Colors.orange,
    // 压缩文件
    for (final ext in _archiveExtensions) ext: Colors.brown,
    // 代码文件
    for (final ext in _codeExtensions) ext: Colors.indigo,
    // 可执行文件
    for (final ext in _executableExtensions) ext: Colors.red,
  };

  /// 根据文件对象获取图标
  static IconData getIcon(ObjectFile obj) {
    if (obj.type == ObjectType.folder) return Icons.folder;
    return _extensionIcons[obj.extension.toLowerCase()] ?? Icons.insert_drive_file;
  }

  /// 根据文件对象获取颜色
  static Color getColor(ObjectFile obj) {
    if (obj.type == ObjectType.folder) return Colors.amber.shade700;
    return _extensionColors[obj.extension.toLowerCase()] ?? Colors.grey;
  }

  /// 判断是否为图片文件
  static bool isImage(String extension) => _imageExtensions.contains(extension.toLowerCase());

  /// 判断是否为视频文件
  static bool isVideo(String extension) => _videoExtensions.contains(extension.toLowerCase());

  /// 判断是否为音频文件
  static bool isAudio(String extension) => _audioExtensions.contains(extension.toLowerCase());

  /// 判断是否为文档文件
  static bool isDocument(String extension) {
    final ext = extension.toLowerCase();
    return _documentExtensions.contains(ext) ||
        _wordExtensions.contains(ext) ||
        _excelExtensions.contains(ext) ||
        _pptExtensions.contains(ext);
  }

  /// 判断是否为压缩文件
  static bool isArchive(String extension) => _archiveExtensions.contains(extension.toLowerCase());

  /// 判断是否为代码文件
  static bool isCode(String extension) => _codeExtensions.contains(extension.toLowerCase());
}
