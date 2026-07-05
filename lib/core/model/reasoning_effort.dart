const reasoningEffortOffValue = '';
const reasoningEffortValues = [
  'none',
  'minimal',
  'low',
  'medium',
  'high',
  'xhigh',
];
const reasoningEffortLabels = <String, String>{
  reasoningEffortOffValue: '关闭',
  'none': 'none',
  'minimal': 'minimal',
  'low': 'low',
  'medium': 'medium',
  'high': 'high',
  'xhigh': 'xhigh',
};

String reasoningEffortLabel(String? value) {
  if (value == null || value.trim().isEmpty) {
    return reasoningEffortLabels[reasoningEffortOffValue]!;
  }
  return reasoningEffortLabels[value] ?? value;
}
