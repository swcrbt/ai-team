import 'dart:convert';
import 'dart:collection';
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter/services.dart';

import 'core/commands/command_service.dart';
import 'core/domain.dart';
import 'core/file_dialogs.dart';
import 'core/local_store.dart';
import 'core/model_gateway.dart';
import 'core/orchestrator.dart';
import 'core/patching.dart';
import 'core/workspace/workspace_service.dart';

part 'ui/app_shell.dart';
part 'application/app_controller.dart';
part 'application/state_persistence_queue.dart';
part 'ui/sidebar.dart';
part 'ui/conversation_sidebar.dart';
part 'ui/chat/chat_pane.dart';
part 'ui/management/management_pages.dart';
part 'ui/dialogs/config_dialogs.dart';
part 'ui/app_helpers.dart';
