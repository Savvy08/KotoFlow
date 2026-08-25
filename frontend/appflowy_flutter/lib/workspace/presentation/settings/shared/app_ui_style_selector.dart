import 'package:appflowy/core/ui_style/app_ui_style.dart';
import 'package:appflowy/workspace/presentation/settings/shared/af_dropdown_menu_entry.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_dropdown.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

/// Виджет выбора стиля и макета интерфейса (Классика / macOS 26 / Windows 11)
class AppUiStyleSelector extends StatelessWidget {
  const AppUiStyleSelector({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppUiStyleNotifier.instance,
      builder: (context, _) {
        final current = AppUiStyleNotifier.instance.currentStyle;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsDropdown<AppUiStyle>(
              key: const Key('AppUiStyleDropdown'),
              expandWidth: false,
              selectedOption: current,
              onChanged: (style) {
                if (style != null) {
                  AppUiStyleNotifier.instance.setStyle(style);
                }
              },
              options: AppUiStyle.values
                  .map(
                    (style) => buildDropdownMenuEntry<AppUiStyle>(
                      context,
                      value: style,
                      label: style.label,
                    ),
                  )
                  .toList(),
            ),
            const VSpace(6),
            FlowyText.regular(
              current.description,
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ],
        );
      },
    );
  }
}
