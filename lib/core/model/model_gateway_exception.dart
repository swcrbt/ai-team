class ModelGatewayException implements Exception {
  const ModelGatewayException(this.message, {this.isRetryable = false});

  final String message;
  final bool isRetryable;

  @override
  String toString() => message;
}
