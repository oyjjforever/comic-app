/// 文件信息模型 - 对应 Electron 端 FileInfo
class FileInfo {
  final String name;
  final String fullPath;
  final String extension;
  final int size;
  final String modifiedTime;

  FileInfo({
    required this.name,
    required this.fullPath,
    required this.extension,
    required this.size,
    required this.modifiedTime,
  });

  factory FileInfo.fromJson(Map<String, dynamic> json) {
    return FileInfo(
      name: json['name'] as String? ?? '',
      fullPath: json['fullPath'] as String? ?? '',
      extension: json['extension'] as String? ?? '',
      size: json['size'] as int? ?? 0,
      modifiedTime: json['modifiedTime'] as String? ?? '',
    );
  }

  /// 判断是否为图片文件
  bool get isImage {
    const imageExtensions = [
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.bmp',
      '.webp',
      '.svg',
    ];
    return imageExtensions.contains(extension.toLowerCase());
  }

  /// 判断是否为视频文件
  bool get isVideo {
    const videoExtensions = [
      '.mp4',
      '.avi',
      '.mov',
      '.mkv',
      '.wmv',
      '.flv',
      '.webm',
      '.m4v',
      '.ogg',
      '.ogv',
    ];
    return videoExtensions.contains(extension.toLowerCase());
  }

  /// 获取文件的 API URL（图片加载、视频流式播放）
  String fileUrl(String baseUrl) {
    return '$baseUrl/api/file?path=${Uri.encodeComponent(fullPath)}';
  }

  /// 获取缩略图 URL
  String thumbnailUrl(String baseUrl) {
    return '$baseUrl/api/thumbnail?path=${Uri.encodeComponent(fullPath)}';
  }

  /// 格式化文件大小
  String get formattedSize {
    if (size == 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    const k = 1024;
    int unitIdx = 0;
    double sz = size.toDouble();
    while (sz >= k && unitIdx < units.length - 1) {
      sz /= k;
      unitIdx++;
    }
    return '${sz.toStringAsFixed(1)} ${units[unitIdx]}';
  }
}
