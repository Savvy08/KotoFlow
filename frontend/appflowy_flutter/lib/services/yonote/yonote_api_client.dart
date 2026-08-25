import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:appflowy_backend/log.dart';
import 'yonote_models.dart';

/// Сетевой клиент для взаимодействия с Yonote API
class YonoteApiClient {
  final String apiKey;
  final String baseUrl;
  final Duration timeout;

  YonoteApiClient({
    required this.apiKey,
    this.baseUrl = 'https://app.yonote.ru/api',
    this.timeout = const Duration(seconds: 15),
  });

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${apiKey.trim()}',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  Uri _uri(String path) {
    final cleanBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$cleanBase$cleanPath');
  }

  /// Проверить валидность API-ключа
  Future<bool> testConnection() async {
    try {
      final response = await http
          .post(
            _uri('/collections.list'),
            headers: _headers,
            body: jsonEncode({'limit': 1}),
          )
          .timeout(timeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body);
        return json['ok'] == true || json['status'] == 200 || json['data'] != null;
      }
      Log.warn('Yonote testConnection failed with status: ${response.statusCode}');
      return false;
    } catch (e) {
      Log.error('Yonote testConnection error: $e');
      return false;
    }
  }

  /// Загрузить список коллекций
  Future<List<YonoteCollection>> fetchCollections() async {
    try {
      final response = await http
          .post(
            _uri('/collections.list'),
            headers: _headers,
            body: jsonEncode({'limit': 50, 'offset': 0}),
          )
          .timeout(timeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body);
        final list = json['data'] as List<dynamic>? ?? [];
        return list.map((item) => YonoteCollection.fromJson(item as Map<String, dynamic>)).toList();
      }
      throw Exception('Не удалось загрузить коллекции (Код: ${response.statusCode})');
    } catch (e) {
      Log.error('Yonote fetchCollections error: $e');
      rethrow;
    }
  }

  /// Загрузить список документов (краткая информация)
  Future<List<YonoteDocument>> fetchDocumentsList({
    String? collectionId,
    String? parentDocumentId,
    int limit = 100,
    int offset = 0,
  }) async {
    try {
      final body = <String, dynamic>{
        'limit': limit,
        'offset': offset,
        if (collectionId != null && collectionId.isNotEmpty) 'collectionId': collectionId,
        if (parentDocumentId != null && parentDocumentId.isNotEmpty)
          'parentDocumentId': parentDocumentId,
      };

      final response = await http
          .post(
            _uri('/documents.list'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(timeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body);
        final list = json['data'] as List<dynamic>? ?? [];
        return list.map((item) => YonoteDocument.fromJson(item as Map<String, dynamic>)).toList();
      }
      throw Exception('Не удалось загрузить список документов (Код: ${response.statusCode})');
    } catch (e) {
      Log.error('Yonote fetchDocumentsList error: $e');
      rethrow;
    }
  }

  /// Загрузить полный документ с текстом заметки
  Future<YonoteDocument> fetchDocumentDetail(String documentId) async {
    try {
      final response = await http
          .post(
            _uri('/documents.info'),
            headers: _headers,
            body: jsonEncode({'id': documentId}),
          )
          .timeout(timeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body);
        final data = json['data'] as Map<String, dynamic>?;
        if (data != null) {
          return YonoteDocument.fromJson(data);
        }
      }
      throw Exception('Не удалось загрузить документ $documentId (Код: ${response.statusCode})');
    } catch (e) {
      Log.error('Yonote fetchDocumentDetail error: $e');
      rethrow;
    }
  }

  /// Экспортировать документ в виде полноценного форматированного Markdown
  Future<String> exportDocumentMarkdown(String documentId) async {
    try {
      final response = await http
          .post(
            _uri('/documents.export'),
            headers: _headers,
            body: jsonEncode({'id': documentId}),
          )
          .timeout(timeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body);
        if (json['data'] is String) {
          final content = json['data'] as String;
          if (content.trim().isNotEmpty) {
            return content;
          }
        }
      }
    } catch (e) {
      Log.warn('Yonote /documents.export warn: $e, falling back to /documents.info');
    }

    // Fallback: загрузка через documents.info
    try {
      final detail = await fetchDocumentDetail(documentId);
      return detail.text;
    } catch (e) {
      Log.error('Yonote fallback fetchDocumentDetail error: $e');
      return '';
    }
  }

  /// Создать новую заметку в Yonote
  Future<String> createDocument({
    required String title,
    required String text,
    String? collectionId,
    String? parentDocumentId,
  }) async {
    try {
      final body = <String, dynamic>{
        'title': title,
        'text': text,
        'publish': true,
        if (collectionId != null && collectionId.isNotEmpty) 'collectionId': collectionId,
        if (parentDocumentId != null && parentDocumentId.isNotEmpty)
          'parentDocumentId': parentDocumentId,
      };

      final response = await http
          .post(
            _uri('/documents.create'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(timeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body);
        final data = json['data'] as Map<String, dynamic>?;
        if (data != null && data['id'] != null) {
          return data['id'] as String;
        }
      }
      throw Exception('Ошибка создания документа в Yonote: ${response.body}');
    } catch (e) {
      Log.error('Yonote createDocument error: $e');
      rethrow;
    }
  }

  /// Обновить существующую заметку в Yonote
  Future<bool> updateDocument({
    required String id,
    String? title,
    String? text,
  }) async {
    try {
      final body = <String, dynamic>{
        'id': id,
        if (title != null) 'title': title,
        if (text != null) 'text': text,
        'append': false,
      };

      final response = await http
          .post(
            _uri('/documents.update'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(timeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body);
        return json['ok'] == true || json['status'] == 200 || json['data'] != null;
      }
      throw Exception('Ошибка обновления документа в Yonote: ${response.body}');
    } catch (e) {
      Log.error('Yonote updateDocument error: $e');
      rethrow;
    }
  }
}
