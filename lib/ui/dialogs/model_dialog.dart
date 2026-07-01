import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../core/domain.dart';
import '../../core/model_gateway.dart';
import 'dialog_frame.dart';

Future<void> showModelDialog(
  BuildContext context,
  AppController controller, {
  ModelProfile? model,
}) async {
  final name = TextEditingController(text: model?.name ?? '');
  final baseUrl = TextEditingController(
    text: model?.baseUrl ?? 'https://api.openai.com/v1',
  );
  final modelName = TextEditingController(text: model?.modelName ?? '');
  final apiKey = TextEditingController(text: model?.apiKey ?? '');
  final temperature = TextEditingController(
    text: (model?.temperature ?? 0.4).toString(),
  );
  final maxTokens = TextEditingController(
    text: (model?.maxTokens ?? 1600).toString(),
  );
  var streaming = model?.streaming ?? true;
  var reasoningEffort = model?.reasoningEffort ?? reasoningEffortOffValue;
  String? validationError;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => ConfigDialog(
        title: model == null ? '新增模型配置' : '编辑模型配置',
        subtitle: '维护 OpenAI 兼容模型、密钥和请求参数。',
        icon: Icons.memory_rounded,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (validationError != null) DialogError(validationError!),
            DialogSection(
              title: '基础信息',
              child: Column(
                children: [
                  DialogField(controller: name, label: '名称'),
                  DialogField(controller: baseUrl, label: 'Base URL'),
                  DialogField(controller: modelName, label: '模型名称'),
                  DialogField(
                    controller: apiKey,
                    label: 'API Key',
                    obscure: true,
                  ),
                ],
              ),
            ),
            DialogSection(
              title: '请求参数',
              child: Column(
                children: [
                  SwitchListTile(
                    value: streaming,
                    onChanged: (value) =>
                        setDialogState(() => streaming = value),
                    title: const Text('流式输出'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: reasoningEffort,
                    decoration: dialogInputDecoration('深度思考'),
                    items: [
                      for (final value in [
                        reasoningEffortOffValue,
                        ...reasoningEffortValues,
                      ])
                        DropdownMenuItem(
                          value: value,
                          child: Text(reasoningEffortLabels[value] ?? value),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setDialogState(() => reasoningEffort = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  DialogField(controller: temperature, label: '温度 0-2'),
                  DialogField(controller: maxTokens, label: '最大 Token'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              try {
                final parsedTemperature = double.tryParse(
                  temperature.text.trim(),
                );
                final parsedMaxTokens = int.tryParse(maxTokens.text.trim());
                if (parsedTemperature == null || parsedMaxTokens == null) {
                  throw ArgumentError('温度和最大 Token 必须是数字');
                }
                final next = ModelProfile(
                  id: model?.id ??
                      'model-${DateTime.now().microsecondsSinceEpoch}',
                  name: name.text.trim(),
                  baseUrl: baseUrl.text.trim(),
                  modelName: modelName.text.trim(),
                  apiKey: apiKey.text.trim(),
                  streaming: streaming,
                  temperature: parsedTemperature,
                  maxTokens: parsedMaxTokens,
                  reasoningEffort: reasoningEffort == reasoningEffortOffValue
                      ? null
                      : reasoningEffort,
                );
                if (model == null) {
                  controller.addModel(next);
                } else {
                  controller.updateModel(next);
                }
                Navigator.pop(context);
              } catch (exception) {
                setDialogState(() => validationError = exception.toString());
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
}
