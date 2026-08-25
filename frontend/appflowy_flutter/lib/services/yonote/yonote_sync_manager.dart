import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/core/config/kv_keys.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/shared/markdown_to_document.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/share/import_service.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:collection/collection.dart';

import 'yonote_api_client.dart';
import 'yonote_models.dart';

/// Менеджер синхронизации данных между Yonote и KotoFlow
class YonoteSyncManager {
  static const String defaultBaseUrl = 'https://app.yonote.ru/api';
  static final YonoteSyncManager instance = YonoteSyncManager._internal();

  factory YonoteSyncManager() => instance;
  YonoteSyncManager._internal();

  Timer? _autoSyncTimer;
  bool _isAutoSyncRunning = false;

  /// Получить сохраненный API-ключ
  Future<String?> getApiKey() async {
    return getIt<KeyValueStorage>().get(KVKeys.kYonoteApiKey);
  }

  /// Сохранить API-ключ
  Future<void> saveApiKey(String key) async {
    await getIt<KeyValueStorage>().set(KVKeys.kYonoteApiKey, key.trim());
  }

  /// Получить базовый URL
  Future<String> getBaseUrl() async {
    final url = await getIt<KeyValueStorage>().get(KVKeys.kYonoteBaseUrl);
    return (url != null && url.isNotEmpty) ? url : defaultBaseUrl;
  }

  /// Сохранить базовый URL
  Future<void> saveBaseUrl(String url) async {
    await getIt<KeyValueStorage>().set(KVKeys.kYonoteBaseUrl, url.trim());
  }

  /// Получить дату последней синхронизации
  Future<DateTime?> getLastSyncTime() async {
    final raw = await getIt<KeyValueStorage>().get(KVKeys.kYonoteLastSyncTime);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  /// Включен ли автосинк
  Future<bool> isAutoSyncEnabled() async {
    final raw = await getIt<KeyValueStorage>().get(KVKeys.kYonoteAutoSync);
    return raw?.toLowerCase() == 'true';
  }

  /// Установить флаг автосинка
  Future<void> setAutoSyncEnabled(bool enabled) async {
    await getIt<KeyValueStorage>().set(KVKeys.kYonoteAutoSync, enabled.toString());
    if (enabled) {
      final interval = await getAutoSyncIntervalMinutes();
      startAutoSync(interval: Duration(minutes: interval));
    } else {
      stopAutoSync();
    }
  }

  /// Получить интервал автосинка в минутах (по умолчанию 15)
  Future<int> getAutoSyncIntervalMinutes() async {
    final raw = await getIt<KeyValueStorage>().get(KVKeys.kYonoteAutoSyncInterval);
    return int.tryParse(raw ?? '') ?? 15;
  }

  /// Сохранить интервал автосинка
  Future<void> setAutoSyncIntervalMinutes(int minutes) async {
    await getIt<KeyValueStorage>().set(KVKeys.kYonoteAutoSyncInterval, minutes.toString());
    final isEnabled = await isAutoSyncEnabled();
    if (isEnabled) {
      startAutoSync(interval: Duration(minutes: minutes));
    }
  }

  /// Запустить периодическую фоновую синхронизацию
  void startAutoSync({Duration interval = const Duration(minutes: 15)}) {
    stopAutoSync();
    Log.info('Yonote AutoSync started with interval ${interval.inMinutes} minutes');
    _autoSyncTimer = Timer.periodic(interval, (_) async {
      if (_isAutoSyncRunning) return;
      _isAutoSyncRunning = true;
      try {
        final key = await getApiKey();
        if (key != null && key.isNotEmpty) {
          Log.info('Yonote AutoSync: starting periodic sync...');
          await syncFromYonote();
        }
      } catch (e) {
        Log.error('Yonote AutoSync error: $e');
      } finally {
        _isAutoSyncRunning = false;
      }
    });
  }

  /// Остановить автосинхронизацию
  void stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    _isAutoSyncRunning = false;
  }

  /// Проверить подключение с текущими или переданными учетными данными
  Future<bool> testConnection({String? customApiKey, String? customBaseUrl}) async {
    final key = customApiKey ?? await getApiKey();
    final url = customBaseUrl ?? await getBaseUrl();

    if (key == null || key.trim().isEmpty) {
      return false;
    }

    final client = YonoteApiClient(apiKey: key, baseUrl: url);
    return client.testConnection();
  }

  /// Выполнить синхронизацию всех заметок из Yonote в KotoFlow с группировкой по коллекциям
  Future<YonoteSyncResult> syncFromYonote({String? targetParentViewId}) async {
    final key = await getApiKey();
    final url = await getBaseUrl();

    if (key == null || key.trim().isEmpty) {
      return YonoteSyncResult.failure('API-ключ Yonote не установлен. Укажите ключ в настройках.');
    }

    try {
      final client = YonoteApiClient(apiKey: key, baseUrl: url);

      // 1. Проверяем доступность
      final isAlive = await client.testConnection();
      if (!isAlive) {
        return YonoteSyncResult.failure('Не удалось подключиться к Yonote API. Проверьте правильность ключа.');
      }

      // 2. Получаем список коллекций и документов
      final collections = await client.fetchCollections().catchError((_) => <YonoteCollection>[]);
      final docSummaries = await client.fetchDocumentsList(limit: 200);
      if (docSummaries.isEmpty) {
        return YonoteSyncResult.success(totalFound: 0, importedCount: 0);
      }

      // 3. Определяем корневое пространство в KotoFlow
      String rootParentViewId = targetParentViewId ?? '';
      if (rootParentViewId.isEmpty) {
        rootParentViewId = (await getIt<KeyValueStorage>().get(KVKeys.lastOpenedSpaceId)) ?? '';
      }
      List<ViewPB> existingViews = [];
      final allViews = await FolderEventGetAllViews().send();
      allViews.fold(
        (repeatedView) {
          existingViews = repeatedView.items;
          if (rootParentViewId.isEmpty && repeatedView.items.isNotEmpty) {
            rootParentViewId = repeatedView.items.first.id;
          }
        },
        (_) {},
      );

      // 4. Создаем или находим папки для коллекций
      final collectionFolderMap = <String, String>{};
      for (final col in collections) {
        final folderName = '📁 ${col.name}';
        final existing = existingViews.firstWhereOrNull((v) => v.name == folderName || v.name == col.name);
        if (existing != null) {
          collectionFolderMap[col.id] = existing.id;
        } else {
          final res = await ViewBackendService.createView(
            layoutType: ViewLayoutPB.Document,
            parentViewId: rootParentViewId,
            name: folderName,
          );
          res.fold((createdView) {
            collectionFolderMap[col.id] = createdView.id;
          }, (_) {});
        }
      }

      // 5. Подготавливаем документы и группируем по папкам
      final payloadsByFolder = <String, List<ImportItemPayloadPB>>{};
      final importedTitles = <String>[];

      // Вычисляем базовый хост для картинок
      final uri = Uri.parse(url);
      final hostBase = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';

      for (final summary in docSummaries) {
        try {
          var title = summary.title.isNotEmpty ? summary.title : 'Yonote Note';
          if (summary.emoji != null && summary.emoji!.isNotEmpty && !title.startsWith(summary.emoji!)) {
            title = '${summary.emoji!} $title';
          }

          // Экспортируем богатый Markdown через официальный эндпоинт /documents.export
          final markdownContent = await client.exportDocumentMarkdown(summary.id).timeout(
            const Duration(seconds: 10),
            onTimeout: () => summary.text,
          );

          final effectiveMarkdown = markdownContent.isNotEmpty ? markdownContent : summary.text;
          final bytes = _convertMarkdownToDocumentBytes(effectiveMarkdown, hostBase);

          if (bytes != null) {
            final payload = ImportItemPayloadPB.create()
              ..name = title
              ..data = bytes
              ..viewLayout = ViewLayoutPB.Document
              ..importType = ImportTypePB.Markdown;

            final targetFolder = (summary.collectionId != null && collectionFolderMap.containsKey(summary.collectionId))
                ? collectionFolderMap[summary.collectionId]!
                : rootParentViewId;

            payloadsByFolder.putIfAbsent(targetFolder, () => []).add(payload);
            importedTitles.add(title);
          }
        } catch (e) {
          Log.warn('Не удалось подготовить заметку ${summary.id} (${summary.title}): $e');
        }
      }

      // 6. Импортируем пачки документов по папкам
      int totalImported = 0;
      for (final entry in payloadsByFolder.entries) {
        if (entry.value.isNotEmpty) {
          final result = await ImportBackendService.importPages(
            entry.key,
            entry.value,
          );
          if (result.isSuccess) {
            totalImported += entry.value.length;
          }
        }
      }

      // 7. Запоминаем время успешного синка
      await getIt<KeyValueStorage>().set(
        KVKeys.kYonoteLastSyncTime,
        DateTime.now().toIso8601String(),
      );

      return YonoteSyncResult.success(
        totalFound: docSummaries.length,
        importedCount: totalImported,
        syncedTitles: importedTitles,
      );
    } catch (e) {
      Log.error('Yonote sync error: $e');
      return YonoteSyncResult.failure(e.toString());
    }
  }

  /// Экспорт страницы из KotoFlow в Yonote (создание или обновление)
  Future<String> exportPageToYonote({
    required String title,
    required String markdown,
    String? existingYonoteId,
    String? collectionId,
  }) async {
    final key = await getApiKey();
    final url = await getBaseUrl();

    if (key == null || key.trim().isEmpty) {
      throw Exception('API-ключ Yonote не установлен в настройках.');
    }

    final client = YonoteApiClient(apiKey: key, baseUrl: url);

    if (existingYonoteId != null && existingYonoteId.isNotEmpty) {
      await client.updateDocument(
        id: existingYonoteId,
        title: title,
        text: markdown,
      );
      return existingYonoteId;
    } else {
      return await client.createDocument(
        title: title,
        text: markdown,
        collectionId: collectionId,
      );
    }
  }

  /// Умная нормализация Markdown из Yonote перед разбором в блоки KotoFlow
  static String normalizeYonoteMarkdown(String raw, [String baseHost = 'https://app.yonote.ru']) {
    if (raw.isEmpty) return raw;

    // 1. Нормализуем переводы строк
    var text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    // 2. Преобразуем относительные ссылки на изображения в абсолютные
    text = text.replaceAllMapped(
      RegExp(r'!\[(.*?)\]\(/(api/attachments\.redirect\?[^\)]+)\)'),
      (match) => '![${match.group(1)}]($baseHost/${match.group(2)})',
    );
    text = text.replaceAllMapped(
      RegExp(r'!\[(.*?)\]\(/([^\)]+\.(?:png|jpg|jpeg|gif|webp|svg))\)'),
      (match) => '![${match.group(1)}]($baseHost/${match.group(2)})',
    );

    // 3. Преобразуем коллауты Yonote (:::info / :::warning / :::tip / :::danger / :::note) в цитаты
    text = text.replaceAllMapped(
      RegExp(r':::(?:info|warning|tip|danger|note|success)?\s*\n([\s\S]*?)\n:::', multiLine: true),
      (match) {
        final content = match.group(1)?.trim() ?? '';
        final lines = content.split('\n');
        final quotedLines = lines.map((l) => '> $l').join('\n');
        return '\n\n$quotedLines\n\n';
      },
    );

    // 4. Преобразуем маркерное выделение ==текст== в жирный **текст**
    text = text.replaceAllMapped(
      RegExp(r'==([^=\n]+)=='),
      (match) => '**${match.group(1)}**',
    );

    // 5. Исправляем прилипшие заголовки (напр. "###Заголовок" -> "### Заголовок")
    text = text.replaceAllMapped(
      RegExp(r'^(#{1,6})([^\s#])', multiLine: true),
      (match) => '${match.group(1)} ${match.group(2)}',
    );

    // 6. Нормализуем чекбоксы (напр. "* [ ] " или "+ [x]" -> "- [ ]")
    text = text.replaceAllMapped(
      RegExp(r'^(\s*)[\*\+]\s+\[([ xX])\]\s+', multiLine: true),
      (match) => '${match.group(1)}- [${match.group(2)}] ',
    );

    // 7. Убираем HTML-комментарии <!-- ... -->
    text = text.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

    // 8. Обеспечиваем гарантированные пустые строки между структурными блоками
    final rawLines = text.split('\n');
    final formattedLines = <String>[];
    bool inCodeBlock = false;

    final headingRegex = RegExp(r'^#{1,6}\s');
    final listRegex = RegExp(r'^(\s*[-*+]|\s*\d+\.)\s');

    for (int i = 0; i < rawLines.length; i++) {
      final line = rawLines[i];
      final trimmed = line.trim();

      // Блоки кода ```
      if (trimmed.startsWith('```')) {
        inCodeBlock = !inCodeBlock;
        if (inCodeBlock && formattedLines.isNotEmpty && formattedLines.last.isNotEmpty) {
          formattedLines.add('');
        }
        formattedLines.add(line);
        if (!inCodeBlock) {
          formattedLines.add('');
        }
        continue;
      }

      if (inCodeBlock) {
        formattedLines.add(line);
        continue;
      }

      // Заголовки: обязательно пустая строка перед и после
      if (headingRegex.hasMatch(trimmed)) {
        if (formattedLines.isNotEmpty && formattedLines.last.isNotEmpty) {
          formattedLines.add('');
        }
        formattedLines.add(line);
        formattedLines.add('');
        continue;
      }

      // Списки: пустая строка перед началом списка, если перед ним обычный текст
      if (listRegex.hasMatch(line)) {
        if (formattedLines.isNotEmpty &&
            formattedLines.last.isNotEmpty &&
            !listRegex.hasMatch(formattedLines.last)) {
          formattedLines.add('');
        }
        formattedLines.add(line);
        continue;
      }

      // Таблицы: пустая строка перед началом таблицы
      if (trimmed.startsWith('|') && trimmed.endsWith('|')) {
        if (formattedLines.isNotEmpty &&
            formattedLines.last.isNotEmpty &&
            !(formattedLines.last.trim().startsWith('|') && formattedLines.last.trim().endsWith('|'))) {
          formattedLines.add('');
        }
        formattedLines.add(line);
        continue;
      }

      formattedLines.add(line);
    }

    var result = formattedLines.join('\n');
    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return result.trim();
  }

  /// Преобразование Markdown-текста в Protobuf-байты документа AppFlowy
  Uint8List? _convertMarkdownToDocumentBytes(String markdownText, [String baseHost = 'https://app.yonote.ru']) {
    try {
      final normalized = normalizeYonoteMarkdown(markdownText, baseHost);
      final document = customMarkdownToDocument(normalized);
      return DocumentDataPBFromTo.fromDocument(document)?.writeToBuffer();
    } catch (e) {
      Log.error('Ошибка конвертации Markdown в DocumentData: $e');
      return null;
    }
  }
}
