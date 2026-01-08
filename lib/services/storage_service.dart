import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/platform_type.dart';
import '../models/platform_credential.dart';
import '../models/storage_class.dart';

class StorageService {
  static const String _keyLastPlatform = 'last_platform';
  static const String _keyCredentialPrefix = 'credential_';
  static const String _keyDownloadDirectory = 'download_directory';
  static const String _keyBucketStorageClassPrefix = 'bucket_storage_class_';

  Future<void> saveLastPlatform(PlatformType platformType) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastPlatform, platformType.value);
  }

  Future<PlatformType?> getLastPlatform() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_keyLastPlatform);
    if (value == null) return null;
    try {
      return PlatformTypeExtension.fromValue(value);
    } catch (e) {
      return null;
    }
  }

  Future<void> clearLastPlatform() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLastPlatform);
  }

  Future<void> saveCredential(PlatformCredential credential) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _keyCredentialPrefix + credential.platformType.value;
    final jsonString = jsonEncode(credential.toJson());
    await prefs.setString(key, jsonString);
  }

  Future<PlatformCredential?> getCredential(PlatformType platformType) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _keyCredentialPrefix + platformType.value;
    final jsonString = prefs.getString(key);
    if (jsonString == null) return null;
    try {
      final json = jsonDecode(jsonString);
      return PlatformCredential.fromJson(json);
    } catch (e) {
      return null;
    }
  }

  Future<void> clearCredential(PlatformType platformType) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _keyCredentialPrefix + platformType.value;
    await prefs.remove(key);
  }

  Future<bool> hasCredential(PlatformType platformType) async {
    final credential = await getCredential(platformType);
    return credential != null;
  }

  // ==================== 下载目录设置 ====================

  Future<void> saveDownloadDirectory(String directoryPath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDownloadDirectory, directoryPath);
  }

  Future<String?> getDownloadDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyDownloadDirectory);
  }

  Future<void> clearDownloadDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyDownloadDirectory);
  }

  // ==================== 存储桶存储类型设置 ====================

  /// 生成存储桶存储类型的 Key
  String _getBucketStorageClassKey(PlatformType platform, String bucketName) {
    return '$_keyBucketStorageClassPrefix${platform.value}_$bucketName';
  }

  /// 保存存储桶的存储类型设置
  Future<void> setBucketStorageClass(
    PlatformType platform,
    String bucketName,
    StorageClass storageClass,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getBucketStorageClassKey(platform, bucketName);
    await prefs.setString(key, storageClass.name);
  }

  /// 获取存储桶的存储类型设置
  Future<StorageClass?> getBucketStorageClass(
    PlatformType platform,
    String bucketName,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getBucketStorageClassKey(platform, bucketName);
    final value = prefs.getString(key);
    if (value == null) return null;
    try {
      return StorageClass.values.firstWhere(
        (e) => e.name == value,
        orElse: () => StorageClass.standard,
      );
    } catch (e) {
      return null;
    }
  }

  /// 清除存储桶的存储类型设置
  Future<void> clearBucketStorageClass(
    PlatformType platform,
    String bucketName,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getBucketStorageClassKey(platform, bucketName);
    await prefs.remove(key);
  }
}
