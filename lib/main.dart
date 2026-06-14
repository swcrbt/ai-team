import 'dart:io';

import 'package:flutter/material.dart';

import 'app.dart';
import 'core/local_store.dart';
import 'core/model_gateway.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = JsonLocalStore(File('.ai_team_data/state.json'));
  final state = await store.load();
  runApp(AiTeamApp(
    initialState: state,
    modelGateway: OpenAiCompatibleGateway(),
    onStateChanged: store.save,
  ));
}
