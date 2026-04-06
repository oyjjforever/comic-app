/// 文件夹信息模型 - 对应 Electron 端 FolderInfo
class FolderInfo {
  final String name;
  final String fullPath;
  final bool isLeaf;
  final String contentType;
  final int fileCount;
  final String? coverPath;
  final String? modifiedTime;
  final bool isBookmarked;

  FolderInfo({
    required this.name,
    required this.fullPath,
    this.isLeaf = true,
    this.contentType = 'loading',
    this.fileCount = 0,
    this.coverPath,
    this.modifiedTime,
    this.isBookmarked = false,
  });

  factory FolderInfo.fromJson(Map<String, dynamic> json) {
    return FolderInfo(
      name: json['name'] as String? ?? '',
      fullPath: json['fullPath'] as String? ?? '',
      isLeaf: json['isLeaf'] as bool? ?? true,
      contentType: json['contentType'] as String? ?? 'loading',
      fileCount: json['fileCount'] as int? ?? 0,
      coverPath: json['coverPath'] as String?,
      modifiedTime: json['modifiedTime'] as String?,
      isBookmarked: json['isBookmarked'] as bool? ?? false,
    );
  }

  /// 获取封面图的 API URL
  String coverUrl(String baseUrl) {
    if (coverPath == null || coverPath!.isEmpty) return '';
    return '$baseUrl/api/file?path=${Uri.encodeComponent(coverPath!)}';
  }
}
