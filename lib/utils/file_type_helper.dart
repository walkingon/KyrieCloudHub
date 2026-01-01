import 'package:flutter/material.dart';
import '../models/object_file.dart';

/// 文件类型辅助工具类
/// 提供文件图标、颜色等配置信息
class FileTypeHelper {
  /// 图片文件扩展名列表
  static const _imageExtensions = {
    'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg',
  };

  /// 视频文件扩展名列表
  static const _videoExtensions = {
    'mp4', 'avi', 'mkv', 'mov', 'wmv', 'flv', 'webm',
  };

  /// 音频文件扩展名列表
  static const _audioExtensions = {
    'mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a',
  };

  /// 文档文件扩展名列表
  static const _documentExtensions = {
    'pdf',
  };

  /// Word文档扩展名
  static const _wordExtensions = {
    'doc', 'docx', 'txt', 'rtf',
  };

  /// Excel表格扩展名
  static const _excelExtensions = {
    'xls', 'xlsx', 'csv',
  };

  /// PPT演示文稿扩展名
  static const _pptExtensions = {
    'ppt', 'pptx',
  };

  /// 压缩文件扩展名列表
  static const _archiveExtensions = {
    'zip', 'rar', '7z', 'tar', 'gz',
  };

  /// 代码文件扩展名列表
  static const _codeExtensions = {
    'dart', 'js', 'ts', 'py', 'java', 'c', 'cpp', 'h',
    'html', 'css', 'json', 'yaml', 'yml',
  };

  /// 可执行文件扩展名列表
  static const _executableExtensions = {
    'exe', 'app', 'dmg',
  };

  /// 根据文件对象获取图标
  static IconData getIcon(ObjectFile obj) {
    if (obj.type == ObjectType.folder) {
      return Icons.folder;
    }

    return _getIconByExtension(obj.extension.toLowerCase());
  }

  /// 根据扩展名获取图标
  static IconData _getIconByExtension(String ext) {
    if (_imageExtensions.contains(ext)) {
      return Icons.image;
    }
    if (_videoExtensions.contains(ext)) {
      return Icons.video_file;
    }
    if (_audioExtensions.contains(ext)) {
      return Icons.audio_file;
    }
    if (_documentExtensions.contains(ext)) {
      return Icons.picture_as_pdf;
    }
    if (_wordExtensions.contains(ext)) {
      return Icons.description;
    }
    if (_excelExtensions.contains(ext)) {
      return Icons.table_chart;
    }
    if (_pptExtensions.contains(ext)) {
      return Icons.slideshow;
    }
    if (_archiveExtensions.contains(ext)) {
      return Icons.archive;
    }
    if (_codeExtensions.contains(ext)) {
      return Icons.code;
    }
    if (_executableExtensions.contains(ext)) {
      return Icons.play_circle_filled;
    }
    return Icons.insert_drive_file;
  }

  /// 根据文件对象获取颜色
  static Color getColor(ObjectFile obj) {
    if (obj.type == ObjectType.folder) {
      return Colors.amber.shade700;
    }

    return _getColorByExtension(obj.extension.toLowerCase());
  }

  /// 根据扩展名获取颜色
  static Color _getColorByExtension(String ext) {
    if (_imageExtensions.contains(ext)) {
      return Colors.purple;
    }
    if (_videoExtensions.contains(ext)) {
      return Colors.pink;
    }
    if (_audioExtensions.contains(ext)) {
      return Colors.cyan;
    }
    if (_documentExtensions.contains(ext) || _wordExtensions.contains(ext)) {
      return Colors.blue;
    }
    if (_excelExtensions.contains(ext)) {
      return Colors.green;
    }
    if (_pptExtensions.contains(ext)) {
      return Colors.orange;
    }
    if (_archiveExtensions.contains(ext)) {
      return Colors.brown;
    }
    if (_codeExtensions.contains(ext)) {
      return Colors.indigo;
    }
    if (_executableExtensions.contains(ext)) {
      return Colors.red;
    }
    return Colors.grey;
  }

  /// 判断是否为图片文件
  static bool isImage(String extension) {
    return _imageExtensions.contains(extension.toLowerCase());
  }

  /// 判断是否为视频文件
  static bool isVideo(String extension) {
    return _videoExtensions.contains(extension.toLowerCase());
  }

  /// 判断是否为音频文件
  static bool isAudio(String extension) {
    return _audioExtensions.contains(extension.toLowerCase());
  }

  /// 判断是否为文档文件
  static bool isDocument(String extension) {
    final ext = extension.toLowerCase();
    return _documentExtensions.contains(ext) ||
        _wordExtensions.contains(ext) ||
        _excelExtensions.contains(ext) ||
        _pptExtensions.contains(ext);
  }

  /// 判断是否为压缩文件
  static bool isArchive(String extension) {
    return _archiveExtensions.contains(extension.toLowerCase());
  }

  /// 判断是否为代码文件
  static bool isCode(String extension) {
    return _codeExtensions.contains(extension.toLowerCase());
  }
}
