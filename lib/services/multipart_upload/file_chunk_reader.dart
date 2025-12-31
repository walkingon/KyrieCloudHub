import 'dart:io';
import 'dart:typed_data';

import '../../utils/logger.dart';

/// 文件分块信息
class FileChunk {
  /// 分块编号 (从1开始)
  final int partNumber;

  /// 分块数据
  final Uint8List data;

  /// 分块大小 (字节)
  int get size => data.length;

  /// 分块在文件中的起始偏移量
  final int offset;

  FileChunk({
    required this.partNumber,
    required this.data,
    required this.offset,
  });

  @override
  String toString() {
    return 'FileChunk(partNumber: $partNumber, offset: $offset, size: $size)';
  }
}

/// 文件分块读取器
///
/// 用于将大文件分块读取，避免一次性加载到内存导致OOM
class FileChunkReader {
  /// 默认分块大小: 64MB（适合大文件上传，减少请求次数）
  static const int defaultChunkSize = 64 * 1024 * 1024;

  /// 最小分块大小: 64KB
  static const int minChunkSize = 64 * 1024;

  /// 最大分块大小: 5GB
  static const int maxChunkSize = 5 * 1024 * 1024 * 1024;

  int _chunkSize;

  FileChunkReader({int chunkSize = defaultChunkSize}) : _chunkSize = chunkSize {
    if (_chunkSize < minChunkSize) {
      log('[FileChunkReader] 分块大小 $_chunkSize 小于最小值 $minChunkSize，使用最小值');
      _chunkSize = minChunkSize;
    }
  }

  /// 获取当前分块大小
  int get chunkSize => _chunkSize;

  /// 读取文件的全部分块
  ///
  /// [file] 要分块的文件
  /// [onProgress] 进度回调 (已读取字节数, 总字节数)
  /// 返回分块列表
  Future<List<FileChunk>> readAllChunks(
    File file, {
    void Function(int bytesRead, int totalBytes)? onProgress,
  }) async {
    final fileSize = await file.length();
    final chunks = <FileChunk>[];

    log('[FileChunkReader] 开始分块读取文件: ${file.path}, 文件大小: $fileSize bytes, 分块大小: $_chunkSize bytes');

    final raf = await file.open(mode: FileMode.read);
    try {
      int partNumber = 1;
      int totalBytesRead = 0;

      while (totalBytesRead < fileSize) {
        final remainingBytes = fileSize - totalBytesRead;
        final bytesToRead = remainingBytes < _chunkSize ? remainingBytes : _chunkSize;

        final buffer = Uint8List(bytesToRead);
        final bytesRead = await raf.readInto(buffer);

        if (bytesRead == 0) {
          break;
        }

        final chunk = FileChunk(
          partNumber: partNumber,
          data: buffer,
          offset: totalBytesRead,
        );
        chunks.add(chunk);

        totalBytesRead += bytesRead;
        partNumber++;

        log('[FileChunkReader] 读取分块 $partNumber, 大小: $bytesRead bytes, 进度: $totalBytesRead/$fileSize');

        onProgress?.call(totalBytesRead, fileSize);
      }

      log('[FileChunkReader] 分块读取完成, 共 ${chunks.length} 个分块');
      return chunks;
    } finally {
      await raf.close();
    }
  }

  /// 流式读取文件分块 (适合超大文件，使用回调方式)
  ///
  /// [file] 要分块的文件
  /// [onChunk] 每个分块的回调（等待回调完成后再处理下一个分块）
  /// [onProgress] 进度回调 (已读取字节数, 总字节数)
  /// 返回分块数量
  Future<int> streamChunks(
    File file, {
    required Future<void> Function(FileChunk chunk) onChunk,
    void Function(int bytesRead, int totalBytes)? onProgress,
  }) async {
    final fileSize = await file.length();
    int partNumber = 0;
    int totalBytesRead = 0;

    log('[FileChunkReader] 开始流式分块读取: ${file.path}, 文件大小: $fileSize bytes');

    final raf = await file.open(mode: FileMode.read);
    try {
      while (totalBytesRead < fileSize) {
        final remainingBytes = fileSize - totalBytesRead;
        final bytesToRead = remainingBytes < _chunkSize ? remainingBytes : _chunkSize;

        final buffer = Uint8List(bytesToRead);
        final bytesRead = await raf.readInto(buffer);

        if (bytesRead == 0) {
          break;
        }

        partNumber++;
        totalBytesRead += bytesRead;

        final chunk = FileChunk(
          partNumber: partNumber,
          data: buffer,
          offset: totalBytesRead - bytesRead,
        );

        // 等待 onChunk 完成后再处理下一个分块
        await onChunk(chunk);
        log('[FileChunkReader] 流式读取分块 $partNumber, 大小: $bytesRead bytes');
        onProgress?.call(totalBytesRead, fileSize);
      }

      log('[FileChunkReader] 流式分块读取完成, 共 $partNumber 个分块');
      return partNumber;
    } finally {
      await raf.close();
    }
  }

  /// 获取文件分块的 Stream (适合超大文件)
  ///
  /// [file] 要分块的文件
  /// 返回分块 Stream
  Stream<FileChunk> chunkStream(File file) async* {
    final fileSize = await file.length();
    int partNumber = 0;
    int totalBytesRead = 0;

    log('[FileChunkReader] 开始流式分块读取: ${file.path}, 文件大小: $fileSize bytes');

    final raf = await file.open(mode: FileMode.read);
    try {
      while (totalBytesRead < fileSize) {
        final remainingBytes = fileSize - totalBytesRead;
        final bytesToRead = remainingBytes < _chunkSize ? remainingBytes : _chunkSize;

        final buffer = Uint8List(bytesToRead);
        final bytesRead = await raf.readInto(buffer);

        if (bytesRead == 0) {
          break;
        }

        partNumber++;
        totalBytesRead += bytesRead;

        final chunk = FileChunk(
          partNumber: partNumber,
          data: buffer,
          offset: totalBytesRead - bytesRead,
        );

        yield chunk;
        log('[FileChunkReader] 流式读取分块 $partNumber, 大小: $bytesRead bytes');
      }

      log('[FileChunkReader] 流式分块读取完成, 共 $partNumber 个分块');
    } finally {
      await raf.close();
    }
  }

  /// 计算分块数量
  ///
  /// [fileSize] 文件大小 (字节)
  /// 返回分块数量
  static int calculateChunkCount(int fileSize, {int? chunkSize}) {
    final size = chunkSize ?? defaultChunkSize;
    return (fileSize / size).ceil();
  }

  /// 获取推荐的最小分块大小
  ///
  /// 根据文件大小返回推荐的最小分块大小
  /// - 小文件 (<20MB): 64KB
  /// - 中等文件 (20MB-100MB): 256KB
  /// - 大文件 (100MB-1GB): 1MB
  /// - 超大文件 (>1GB): 2MB
  static int getRecommendedChunkSize(int fileSize) {
    if (fileSize < 20 * 1024 * 1024) {
      return 64 * 1024; // 64KB
    } else if (fileSize < 100 * 1024 * 1024) {
      return 256 * 1024; // 256KB
    } else if (fileSize < 1024 * 1024 * 1024) {
      return 1024 * 1024; // 1MB
    } else {
      return 2 * 1024 * 1024; // 2MB
    }
  }
}
