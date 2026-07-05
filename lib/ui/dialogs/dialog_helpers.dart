import 'package:flutter/material.dart';

import '../../core/domain.dart';

void runConfigAction(
  BuildContext context,
  VoidCallback action,
) {
  try {
    action();
  } catch (exception) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(exception.toString())),
    );
  }
}

List<String> splitDialogLines(String text) => text
    .split(RegExp(r'[\r\n,]+'))
    .map((item) => item.trim())
    .where((item) => item.isNotEmpty)
    .toList();

String dialogRoleName(AppState state, String roleId) =>
    state.roles.firstWhere((role) => role.id == roleId).name;

String dialogModelName(AppState state, String modelId) =>
    state.models.firstWhere((model) => model.id == modelId).name;
