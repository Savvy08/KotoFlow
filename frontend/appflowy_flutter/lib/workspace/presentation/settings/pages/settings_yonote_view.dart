import 'package:appflowy/services/yonote/yonote_models.dart';
import 'package:appflowy/services/yonote/yonote_sync_manager.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_body.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_category.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

class SettingsYonoteView extends StatefulWidget {
  const SettingsYonoteView({super.key});

  @override
  State<SettingsYonoteView> createState() => _SettingsYonoteViewState();
}

class _SettingsYonoteViewState extends State<SettingsYonoteView> {
  final _syncManager = YonoteSyncManager();
  final _apiKeyController = TextEditingController();
  final _baseUrlController = TextEditingController();

  bool _isLoading = true;
  bool _isTesting = false;
  bool _isSyncing = false;
  bool? _connectionValid;
  String? _testMessage;
  DateTime? _lastSyncTime;
  YonoteSyncResult? _lastSyncResult;

  bool _autoSyncEnabled = false;
  int _autoSyncInterval = 15;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final apiKey = await _syncManager.getApiKey();
    final baseUrl = await _syncManager.getBaseUrl();
    final lastSync = await _syncManager.getLastSyncTime();
    final autoSync = await _syncManager.isAutoSyncEnabled();
    final interval = await _syncManager.getAutoSyncIntervalMinutes();

    if (mounted) {
      setState(() {
        _apiKeyController.text = apiKey ?? '';
        _baseUrlController.text = baseUrl;
        _lastSyncTime = lastSync;
        _autoSyncEnabled = autoSync;
        _autoSyncInterval = interval;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveAndTestConnection() async {
    final apiKey = _apiKeyController.text.trim();
    final baseUrl = _baseUrlController.text.trim();

    if (apiKey.isEmpty) {
      setState(() {
        _connectionValid = false;
        _testMessage = 'Введите API-ключ Yonote';
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _testMessage = 'Проверка подключения...';
      _connectionValid = null;
    });

    await _syncManager.saveApiKey(apiKey);
    await _syncManager.saveBaseUrl(baseUrl.isNotEmpty ? baseUrl : YonoteSyncManager.defaultBaseUrl);

    final isValid = await _syncManager.testConnection(
      customApiKey: apiKey,
      customBaseUrl: baseUrl,
    );

    if (mounted) {
      setState(() {
        _isTesting = false;
        _connectionValid = isValid;
        _testMessage = isValid
            ? 'Подключение успешно установлено!'
            : 'Ошибка подключения: проверьте правильность API-ключа или сетевой доступ.';
      });
    }
  }

  Future<void> _triggerSync() async {
    if (_apiKeyController.text.trim().isEmpty) {
      setState(() {
        _testMessage = 'Сначала сохраните корректный API-ключ';
        _connectionValid = false;
      });
      return;
    }

    setState(() {
      _isSyncing = true;
      _lastSyncResult = null;
    });

    try {
      final result = await _syncManager.syncFromYonote().timeout(
        const Duration(seconds: 30),
        onTimeout: () => YonoteSyncResult.failure('Таймаут синхронизации (30 секунд). Проверьте интернет-соединение.'),
      );
      final lastSync = await _syncManager.getLastSyncTime();

      if (mounted) {
        setState(() {
          _lastSyncResult = result;
          _lastSyncTime = lastSync;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _lastSyncResult = YonoteSyncResult.failure('Ошибка: $e');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  Future<void> _toggleAutoSync(bool enabled) async {
    await _syncManager.setAutoSyncEnabled(enabled);
    setState(() {
      _autoSyncEnabled = enabled;
    });
  }

  Future<void> _changeInterval(int minutes) async {
    await _syncManager.setAutoSyncIntervalMinutes(minutes);
    setState(() {
      _autoSyncInterval = minutes;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SettingsBody(
      title: 'Синхронизация Yonote',
      description: 'Интеграция с базой знаний Yonote через официальный API. Документы сохраняются в рабочее пространство KotoFlow.',
      children: [
        // Секция 1: Настройки подключения
        SettingsCategory(
          title: 'Параметры API Yonote',
          description: 'Укажите API-ключ (создаётся в настройках вашего аккаунта на app.yonote.ru/settings)',
          children: [
            const VSpace(8),
            // Поле ввода API ключа
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FlowyText.medium('API-ключ (Bearer Token):', fontSize: 13),
                const VSpace(6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: theme.surfaceContainerColorScheme.layer01,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.borderColorScheme.primary),
                  ),
                  child: TextField(
                    controller: _apiKeyController,
                    obscureText: true,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.textColorScheme.primary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'sk_live_... или ваш API-ключ',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: theme.textColorScheme.tertiary,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
            const VSpace(12),
            // Поле ввода Base URL
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FlowyText.medium('API URL:', fontSize: 13),
                const VSpace(6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: theme.surfaceContainerColorScheme.layer01,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.borderColorScheme.primary),
                  ),
                  child: TextField(
                    controller: _baseUrlController,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.textColorScheme.primary,
                    ),
                    decoration: InputDecoration(
                      hintText: YonoteSyncManager.defaultBaseUrl,
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: theme.textColorScheme.tertiary,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
            const VSpace(16),
            // Кнопки сохранения и проверки
            Row(
              children: [
                PrimaryRoundedButton(
                  text: _isTesting ? 'Проверка...' : 'Сохранить и проверить',
                  onTap: _isTesting ? null : _saveAndTestConnection,
                ),
                if (_testMessage != null) ...[
                  const HSpace(12),
                  Expanded(
                    child: FlowyText.regular(
                      _testMessage!,
                      fontSize: 12,
                      color: _connectionValid == true
                          ? Colors.green
                          : (_connectionValid == false ? Colors.redAccent : theme.textColorScheme.secondary),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),

        // Секция 2: Фоновый автосинк
        SettingsCategory(
          title: 'Автоматическая синхронизация',
          description: 'Фоновое обновление заметок из облака Yonote без необходимости ручного запуска',
          children: [
            Row(
              children: [
                Switch(
                  value: _autoSyncEnabled,
                  onChanged: _toggleAutoSync,
                ),
                const HSpace(12),
                FlowyText.medium(
                  _autoSyncEnabled ? 'Автосинхронизация включена' : 'Автосинхронизация выключена',
                  fontSize: 13,
                ),
              ],
            ),
            if (_autoSyncEnabled) ...[
              const VSpace(10),
              Row(
                children: [
                  FlowyText.regular('Период проверки: ', fontSize: 13),
                  const HSpace(8),
                  DropdownButton<int>(
                    value: _autoSyncInterval,
                    dropdownColor: theme.surfaceContainerColorScheme.layer01,
                    items: const [
                      DropdownMenuItem(value: 5, child: Text('Каждые 5 минут')),
                      DropdownMenuItem(value: 15, child: Text('Каждые 15 минут')),
                      DropdownMenuItem(value: 30, child: Text('Каждые 30 минут')),
                      DropdownMenuItem(value: 60, child: Text('Каждый час')),
                    ],
                    onChanged: (val) {
                      if (val != null) _changeInterval(val);
                    },
                  ),
                ],
              ),
            ],
          ],
        ),

        // Секция 3: Ручной запуск синхронизации
        SettingsCategory(
          title: 'Ручная синхронизация',
          description: 'Загрузить все документы из Yonote в текущее рабочее пространство KotoFlow',
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                PrimaryRoundedButton(
                  text: _isSyncing ? 'Синхронизация...' : 'Синхронизировать сейчас',
                  onTap: _isSyncing ? null : _triggerSync,
                ),
                if (_lastSyncTime != null)
                  FlowyText.regular(
                    'Посл. синхронизация: ${_formatDateTime(_lastSyncTime!)}',
                    fontSize: 12,
                    color: theme.textColorScheme.secondary,
                  ),
              ],
            ),
            if (_lastSyncResult != null) ...[
              const VSpace(12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _lastSyncResult!.isSuccess
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.redAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _lastSyncResult!.isSuccess
                        ? Colors.green.withValues(alpha: 0.3)
                        : Colors.redAccent.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FlowyText.semibold(
                      _lastSyncResult!.isSuccess
                          ? 'Успешно импортировано документов: ${_lastSyncResult!.importedCount} из ${_lastSyncResult!.totalFound}'
                          : 'Ошибка: ${_lastSyncResult!.errorMessage}',
                      fontSize: 13,
                      color: _lastSyncResult!.isSuccess ? Colors.green : Colors.redAccent,
                    ),
                    if (_lastSyncResult!.syncedTitles.isNotEmpty) ...[
                      const VSpace(6),
                      FlowyText.regular(
                        'Заметки: ${_lastSyncResult!.syncedTitles.take(5).join(", ")}${_lastSyncResult!.syncedTitles.length > 5 ? " и еще..." : ""}',
                        fontSize: 12,
                        color: theme.textColorScheme.secondary,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
