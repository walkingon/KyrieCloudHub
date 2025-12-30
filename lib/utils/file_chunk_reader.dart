import 'dart:io';
import 'dart:typed_data';
import '../models/transfer_task.dart';

/// 文件分块读取工具类
/// 用于大文件的分块读取，避免内存溢出
class FileChunkReader {
  final File file;
  final int chunkSize;
  int _currentPosition = 0;
  int _totalSize = 0;
  RandomAccessFile? _randomAccessFile;

  FileChunkReader(this.file, {this.chunkSize = 1024 * 1024}) {
    _totalSize = file.lengthSync();
  }

  /// 获取文件总大小
  int get totalSize => _totalSize;

  /// 获取分块总数
  int get totalChunks => (_totalSize / chunkSize).ceil();

  /// 是否还有更多数据可读
  bool get hasMore => _currentPosition < _totalSize;

  /// 当前读取位置
  int get currentPosition => _currentPosition;

  /// 打开文件进行随机访问读取
  Future<RandomAccessFile> _openFile() async {
    _randomAccessFile ??= await file.open(mode: FileMode.read);
    return _randomAccessFile!;
  }

  /// 读取下一个分块
  /// 返回分块数据和分块信息
  Future<({List<int> data, PartInfo partInfo})> readNextChunk() async {
    final raf = await _openFile();
    final partNumber = (_currentPosition / chunkSize).floor() + 1;
    final offset = _currentPosition;
    final remainingSize = _totalSize - _currentPosition;
    final size = remainingSize < chunkSize ? remainingSize : chunkSize;

    // 读取数据
    final bytes = <int>[];
    final buffer = List<int>.filled(size, 0);
    final bytesRead = await raf.readInto(buffer, 0, size);
    if (bytesRead > 0) {
      bytes.addAll(buffer.take(bytesRead));
    }

    _currentPosition += bytesRead;

    final partInfo = PartInfo(
      partNumber: partNumber,
      offset: offset,
      size: bytes.length,
    );

    return (data: bytes, partInfo: partInfo);
  }

  /// 读取指定偏移位置的分块
  Future<({List<int> data, PartInfo partInfo})> readChunkAt(int offset) async {
    if (offset < 0 || offset >= _totalSize) {
      throw ArgumentError('Offset out of range: $offset');
    }

    final raf = await _openFile();
    await raf.setPosition(offset);

    final partNumber = (offset / chunkSize).floor() + 1;
    final remainingSize = _totalSize - offset;
    final size = remainingSize < chunkSize ? remainingSize : chunkSize;

    // 读取数据
    final bytes = <int>[];
    final buffer = List<int>.filled(size, 0);
    final bytesRead = await raf.readInto(buffer, 0, size);
    if (bytesRead > 0) {
      bytes.addAll(buffer.take(bytesRead));
    }

    final partInfo = PartInfo(
      partNumber: partNumber,
      offset: offset,
      size: bytes.length,
    );

    return (data: bytes, partInfo: partInfo);
  }

  /// 跳转到指定分块
  Future<void> seekToChunk(int chunkNumber) async {
    if (chunkNumber < 1 || chunkNumber > totalChunks) {
      throw ArgumentError('Invalid chunk number: $chunkNumber');
    }
    _currentPosition = (chunkNumber - 1) * chunkSize;
    final raf = await _openFile();
    await raf.setPosition(_currentPosition);
  }

  /// 关闭文件
  Future<void> close() async {
    _randomAccessFile?.close();
    _randomAccessFile = null;
    _currentPosition = 0;
  }

  /// 重置读取位置
  void reset() {
    _currentPosition = 0;
  }

  /// 生成所有分片信息（不实际读取数据）
  List<PartInfo> generatePartInfoList() {
    final parts = <PartInfo>[];
    for (int i = 0; i < totalChunks; i++) {
      final offset = i * chunkSize;
      final remainingSize = _totalSize - offset;
      final size = remainingSize < chunkSize ? remainingSize : chunkSize;
      parts.add(PartInfo(
        partNumber: i + 1,
        offset: offset,
        size: size,
      ));
    }
    return parts;
  }
}

/// 内存分块读取器
/// 用于将内存中的数据分块处理
class MemoryChunkReader {
  final Uint8List data;
  final int chunkSize;

  MemoryChunkReader(this.data, {this.chunkSize = 1024 * 1024});

  /// 获取数据总大小
  int get totalSize => data.length;

  /// 获取分块总数
  int get totalChunks => (data.length / chunkSize).ceil();

  /// 读取指定分块
  List<int> readChunk(int chunkNumber) {
    if (chunkNumber < 1 || chunkNumber > totalChunks) {
      throw ArgumentError('Invalid chunk number: $chunkNumber');
    }

    final start = (chunkNumber - 1) * chunkSize;
    final end = (start + chunkSize).clamp(0, data.length);
    return data.sublist(start, end);
  }

  /// 生成分片信息列表
  List<PartInfo> generatePartInfoList() {
    final parts = <PartInfo>[];
    for (int i = 0; i < totalChunks; i++) {
      final offset = i * chunkSize;
      final remainingSize = data.length - offset;
      final size = remainingSize < chunkSize ? remainingSize : chunkSize;
      parts.add(PartInfo(
        partNumber: i + 1,
        offset: offset,
        size: size,
      ));
    }
    return parts;
  }

  /// 获取分块数据及信息
  ({List<int> data, PartInfo partInfo}) getChunkWithInfo(int chunkNumber) {
    final chunkData = readChunk(chunkNumber);
    final partInfo = PartInfo(
      partNumber: chunkNumber,
      offset: (chunkNumber - 1) * chunkSize,
      size: chunkData.length,
    );
    return (data: chunkData, partInfo: partInfo);
  }
}
