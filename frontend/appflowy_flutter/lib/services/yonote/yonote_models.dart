import 'dart:convert';

/// Модель документа Yonote
class YonoteDocument {
  final String id;
  final String title;
  final String text;
  final String? emoji;
  final String? collectionId;
  final String? parentDocumentId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  YonoteDocument({
    required this.id,
    required this.title,
    required this.text,
    this.emoji,
    this.collectionId,
    this.parentDocumentId,
    this.createdAt,
    this.updatedAt,
  });

  factory YonoteDocument.fromJson(Map<String, dynamic> json) {
    return YonoteDocument(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Untitled',
      text: json['text'] as String? ?? '',
      emoji: json['emoji'] as String?,
      collectionId: json['collectionId'] as String?,
      parentDocumentId: json['parentDocumentId'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'text': text,
      if (collectionId != null) 'collectionId': collectionId,
      if (parentDocumentId != null) 'parentDocumentId': parentDocumentId,
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }
}

/// Модель коллекции (базы/папки) Yonote
class YonoteCollection {
  final String id;
  final String name;
  final String? description;
  final String? color;

  YonoteCollection({
    required this.id,
    required this.name,
    this.description,
    this.color,
  });

  factory YonoteCollection.fromJson(Map<String, dynamic> json) {
    return YonoteCollection(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      color: json['color'] as String?,
    );
  }
}

/// Результат выполнения синхронизации
class YonoteSyncResult {
  final bool isSuccess;
  final int totalFound;
  final int importedCount;
  final String? errorMessage;
  final List<String> syncedTitles;

  const YonoteSyncResult({
    required this.isSuccess,
    this.totalFound = 0,
    this.importedCount = 0,
    this.errorMessage,
    this.syncedTitles = const [],
  });

  factory YonoteSyncResult.success({
    required int totalFound,
    required int importedCount,
    List<String> syncedTitles = const [],
  }) {
    return YonoteSyncResult(
      isSuccess: true,
      totalFound: totalFound,
      importedCount: importedCount,
      syncedTitles: syncedTitles,
    );
  }

  factory YonoteSyncResult.failure(String errorMessage) {
    return YonoteSyncResult(
      isSuccess: false,
      errorMessage: errorMessage,
    );
  }
}
