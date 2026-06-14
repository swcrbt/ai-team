import 'package:flutter/material.dart';

import 'app.dart';
import 'core/local_store.dart';
import 'core/model_gateway.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = JsonLocalStore.defaultStore();
  final state = await store.load();
  runApp(AiTeamApp(
    initialState: state,
    modelGateway: OpenAiCompatibleGateway(),
    onStateChanged: store.save,
  ));
}
