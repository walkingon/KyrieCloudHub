import 'dart:io';

import 'package:android_path_provider/android_path_provider.dart';
import 'package:path_provider/path_provider.dart' as path_provider;

/// 文件路径辅助工具类
/// 提供下载目录、系统路径等文件路径相关的工具方法
class FilePathHelper {
  /// 应用下载子目录名称
  static const String kDownloadSubDir = 'KyrieCloudHubDownload';

  /// 系统下载目录缓存（应用启动后初始化）
  static String? _systemDownloadsDirectory;

  /// 初始化系统下载目录
  /// 应用启动时调用一次，后续通过 systemDownloadsDirectory 获取
  static Future<void> initSystemDownloadsDirectory() async {
    _systemDownloadsDirectory = await _getSystemDownloadsDirectory();
  }

  /// 获取缓存的系统下载目录
  /// 必须在 initSystemDownloadsDirectory() 调用后才能使用
  static String? get systemDownloadsDirectory => _systemDownloadsDirectory;

  /// 同步获取系统下载目录路径（使用缓存值，失败时回退到同步获取）
  static String getSystemDownloadsDirectorySync() {
    if (_systemDownloadsDirectory != null) {
      return _systemDownloadsDirectory!;
    }
    // 回退到原始同步获取逻辑
    if (Platform.isWindows) {
      final downloads = Platform.environment['USERPROFILE'];
      return downloads != null ? '$downloads\\Downloads' : '';
    } else if (Platform.isMacOS || Platform.isLinux) {
      final home = Platform.environment['HOME'];
      return home != null ? '$home/Downloads' : '';
    }
    return '';
  }

  /// 内部方法：获取系统下载目录路径（原始实现）
  static Future<String?> _getSystemDownloadsDirectory() async {
    if (Platform.isWindows) {
      // Windows: 使用环境变量
      return Platform.environment['USERPROFILE'] != null
          ? '${Platform.environment['USERPROFILE']}\\Downloads'
          : null;
    } else if (Platform.isMacOS) {
      return '${Platform.environment['HOME']}/Downloads';
    } else if (Platform.isLinux) {
      return '${Platform.environment['HOME']}/Downloads';
    } else if (Platform.isAndroid || Platform.isIOS) {
      // Android/iOS: 使用公共外部存储的 Downloads 目录
      try {
        return await AndroidPathProvider.downloadsPath;
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  /// 获取默认下载根目录（包含 ${FilePathHelper.kDownloadSubDir} 子目录）
  /// 如果系统下载目录不可用，返回应用数据目录
  static Future<String> getDefaultDownloadRoot() async {
    final downloads = await _getSystemDownloadsDirectory();
    if (downloads != null && downloads.isNotEmpty) {
      return downloads;
    }
    // 如果获取不到，返回应用数据目录下的默认路径
    final directory = await path_provider.getApplicationSupportDirectory();
    return directory.path;
  }

  /// 构建完整的本地文件路径
  ///
  /// 参数:
  /// - [downloadRoot]: 下载根目录（用户配置或系统默认）
  /// - [platformName]: 云平台显示名称
  /// - [bucketName]: 存储桶名称
  /// - [objectKey]: 对象键（文件在云端的路径）
  ///
  /// 返回: 完整的本地文件路径
  /// 格式: downloadRoot/${FilePathHelper.kDownloadSubDir}/platformName/bucketName/objectKey
  static String buildLocalFilePath({
    required String downloadRoot,
    required String platformName,
    required String bucketName,
    required String objectKey,
  }) {
    // 将 objectKey 中的路径分隔符转换为适合本地系统的格式
    final relativePath = objectKey
        .split('/')
        .where((e) => e.isNotEmpty)
        .join('/');
    return '$downloadRoot/${FilePathHelper.kDownloadSubDir}/$platformName/$bucketName/$relativePath';
  }

  /// 构建存储桶的本地目录路径
  ///
  /// 参数:
  /// - [downloadRoot]: 下载根目录
  /// - [platformName]: 云平台显示名称
  /// - [bucketName]: 存储桶名称
  ///
  /// 返回: 存储桶的本地目录路径
  static String buildBucketLocalPath({
    required String downloadRoot,
    required String platformName,
    required String bucketName,
  }) {
    return '$downloadRoot/${FilePathHelper.kDownloadSubDir}/$platformName/$bucketName';
  }
}
