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

  /// 获取文件的 API URL
  String fileUrl(String baseUrl) {
    return '$baseUrl/api/file?path=${Uri.encodeComponent(fullPath)}';
  }
}
