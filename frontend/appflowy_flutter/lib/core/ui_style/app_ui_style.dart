import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/core/config/kv_keys.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:flutter/material.dart';

/// Варианты внешнего стиля и макета приложения
enum AppUiStyle {
  /// Классический стиль KotoFlow (Notion-like)
  classic,

  /// Нативный строгий макет macOS 26 (Apple Notes, SF Pro, янтарный/синий акцент)
  macos26,

  /// Нативный макет Windows 11 Fluent (WinUI 3 Navigation, Segoe UI, акцентная полоса слева)
  windows11;

  String get label {
    switch (this) {
      case AppUiStyle.classic:
        return 'Классический KotoFlow';
      case AppUiStyle.macos26:
        return 'MacOS26';
      case AppUiStyle.windows11:
        return 'Windows 11';
    }
  }

  String get description {
    switch (this) {
      case AppUiStyle.classic:
        return 'Фирменный блочный интерфейс KotoFlow с классической структурой панелей';
      case AppUiStyle.macos26:
        return 'Стиль Apple Notes / MacOS26: скругленный сайдбар, янтарный акцент, шрифт SF Pro';
      case AppUiStyle.windows11:
        return 'Стиль Windows 11 Fluent: акцентная полоса-индикатор, Segoe UI, скругления';
    }
  }

  Color sidebarBackground(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (this) {
      case AppUiStyle.macos26:
        return isDark ? const Color(0xFF18181B) : const Color(0xFFEBEBF0);
      case AppUiStyle.windows11:
        return isDark ? const Color(0xFF202020) : const Color(0xFFF3F3F3);
      case AppUiStyle.classic:
        return Theme.of(context).colorScheme.surfaceContainerHighest;
    }
  }

  Color itemSelectedBackground(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (this) {
      case AppUiStyle.macos26:
        // Фирменный янтарный цвет выделения Apple Notes (как на скриншоте пользователя)
        return isDark ? const Color(0xFFD97706) : const Color(0xFFE08A00);
      case AppUiStyle.windows11:
        return isDark ? const Color(0x2260CDFF) : const Color(0x180067C0);
      case AppUiStyle.classic:
        return Theme.of(context).colorScheme.secondary;
    }
  }

  Color itemTextColor(BuildContext context, bool isSelected) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (this) {
      case AppUiStyle.macos26:
        if (isSelected) return Colors.white;
        return isDark ? const Color(0xFFE4E4E7) : const Color(0xFF27272A);
      case AppUiStyle.windows11:
        if (isSelected) return isDark ? const Color(0xFF60CDFF) : const Color(0xFF0067C0);
        return isDark ? const Color(0xFFFFFFFF) : const Color(0xFF1A1A1A);
      case AppUiStyle.classic:
        return Theme.of(context).colorScheme.onSurface;
    }
  }

  BorderRadius get itemBorderRadius {
    switch (this) {
      case AppUiStyle.macos26:
        return BorderRadius.circular(6.0);
      case AppUiStyle.windows11:
        return BorderRadius.circular(6.0);
      case AppUiStyle.classic:
        return BorderRadius.circular(6.0);
    }
  }
}

/// Синглтон-нотификатор для мгновенного переключения стиля интерфейса
class AppUiStyleNotifier extends ChangeNotifier {
  static final AppUiStyleNotifier instance = AppUiStyleNotifier._internal();
  factory AppUiStyleNotifier() => instance;

  AppUiStyleNotifier._internal() {
    _loadStyle();
  }

  AppUiStyle _currentStyle = AppUiStyle.classic;
  AppUiStyle get currentStyle => _currentStyle;

  bool get isMacOsStyle => _currentStyle == AppUiStyle.macos26;
  bool get isWindows11Style => _currentStyle == AppUiStyle.windows11;
  bool get isClassicStyle => _currentStyle == AppUiStyle.classic;

  Future<void> _loadStyle() async {
    try {
      final saved = await getIt<KeyValueStorage>().get(KVKeys.kAppUiStyle);
      if (saved != null) {
        _currentStyle = AppUiStyle.values.firstWhere(
          (e) => e.name == saved,
          orElse: () => AppUiStyle.classic,
        );
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> setStyle(AppUiStyle style) async {
    if (_currentStyle == style) return;
    _currentStyle = style;
    await getIt<KeyValueStorage>().set(KVKeys.kAppUiStyle, style.name);
    notifyListeners();
  }
}
