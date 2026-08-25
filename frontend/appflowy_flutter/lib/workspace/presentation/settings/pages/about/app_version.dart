import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

class SettingsAppVersion extends StatelessWidget {
  const SettingsAppVersion({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Установлена актуальная версия',
          style: theme.textStyle.body.enhanced(
            color: theme.textColorScheme.primary,
          ),
        ),
        VSpace(theme.spacing.s),
        Row(
          children: [
            Text(
              'Версия: KotoFlow 0.13.2',
              style: theme.textStyle.caption.standard(
                color: theme.textColorScheme.secondary,
              ),
            ),
            const HSpace(12),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  afLaunchUrlString('https://github.com/Savvy08/KotoFlow');
                },
                child: FlowyText.regular(
                  'GitHub репозиторий',
                  decoration: TextDecoration.underline,
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 12,
                  figmaLineHeight: 13,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
