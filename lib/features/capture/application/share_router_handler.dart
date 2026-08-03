import 'package:flutter/material.dart';
import 'package:var_app/features/capture/domain/capture_payload.dart';
import 'package:var_app/features/capture/presentation/quick_capture_dialog.dart';

Future<bool?> showQuickCaptureForShare(
  BuildContext context,
  CapturePayload initialPayload,
) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (context) => QuickCaptureDialog(initialPayload: initialPayload),
  );
}
