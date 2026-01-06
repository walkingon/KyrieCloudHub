import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/platform_type.dart';
import '../models/platform_credential.dart';

class StorageService {
  static const String _keyLastPlatform = 'last_platform';
  static const String _keyCredentialPrefix = 'credential_';
  static const String _keyDownloadDirectory = 'download_directory';
  static const String _keyDownloadedFiles = 'downloaded_files';

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

  Future<void> saveTransferTask(String taskId, Map<String, dynamic> taskData) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'transfer_task_$taskId';
    await prefs.setString(key, jsonEncode(taskData));
  }

  Future<Map<String, dynamic>?> getTransferTask(String taskId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'transfer_task_$taskId';
    final jsonString = prefs.getString(key);
    if (jsonString == null) return null;
    try {
      return jsonDecode(jsonString);
    } catch (e) {
      return null;
    }
  }

  Future<void> clearTransferTask(String taskId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'transfer_task_$taskId';
    await prefs.remove(key);
  }

  Future<List<String>> getAllTransferTaskIds() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    return keys
        .where((key) => key.startsWith('transfer_task_'))
        .map((key) => key.replaceFirst('transfer_task_', ''))
        .toList();
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

  // ==================== 已下载文件记录 ====================

  Future<void> addDownloadedFile(String platform, String bucketName, String objectKey, String localPath) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '${_keyDownloadedFiles}_${platform}_$bucketName';
    final existing = prefs.getString(key);
    Set<String> files = {};
    if (existing != null) {
      files = Set<String>.from(jsonDecode(existing));
    }
    files.add(objectKey);
    await prefs.setString(key, jsonEncode(files.toList()));
  }

  Future<Set<String>> getDownloadedFiles(String platform, String bucketName) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '${_keyDownloadedFiles}_${platform}_$bucketName';
    final existing = prefs.getString(key);
    if (existing == null) return {};
    try {
      final List<dynamic> list = jsonDecode(existing);
      return Set<String>.from(list);
    } catch (e) {
      return {};
    }
  }

  Future<void> removeDownloadedFile(String platform, String bucketName, String objectKey) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '${_keyDownloadedFiles}_${platform}_$bucketName';
    final existing = prefs.getString(key);
    if (existing != null) {
      final List<dynamic> list = jsonDecode(existing);
      final updated = list.where((item) => item != objectKey).toList();
      await prefs.setString(key, jsonEncode(updated));
    }
  }
}
