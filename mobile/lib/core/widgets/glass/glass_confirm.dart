import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/app_theme.dart';
import '../buttons/gradient_button.dart';
import '../progress/stat_card.dart' show IconChip;
import 'glass_sheet.dart';

/// "Are you sure?" as a glass sheet, matching the rest of the app.
/// Returns true only when the user confirms.
Future<bool> showGlassConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  bool destructive = true,
  IconData icon = LucideIcons.trash2,
}) async {
  final ok = await showGlassSheet<bool>(
    context,
    builder: (sheet) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: IconChip(icon: icon, color: destructive ? LifeColors.danger : LifeColors.iris, size: 52)),
        const SizedBox(height: Space.lg),
        Text(title, textAlign: TextAlign.center, style: LifeText.titleSerif.copyWith(fontSize: 26)),
        const SizedBox(height: Space.sm),
        Text(message, textAlign: TextAlign.center, style: LifeText.body.copyWith(color: LifeColors.text2)),
        const SizedBox(height: Space.xl),
        Row(
          children: [
            Expanded(
              child: GradientButton(
                label: 'Cancel',
                variant: ButtonVariant.glass,
                expand: true,
                onPressed: () => Navigator.of(sheet).pop(false),
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: GradientButton(
                label: confirmLabel,
                variant: destructive ? ButtonVariant.danger : ButtonVariant.primary,
                expand: true,
                onPressed: () => Navigator.of(sheet).pop(true),
              ),
            ),
          ],
        ),
      ],
    ),
  );
  return ok ?? false;
}
