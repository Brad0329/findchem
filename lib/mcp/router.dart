/// 원격 서버의 경로 가르기 — `/assist/messages`(F-010 중계)는 [AssistProxy]로, 그 밖은 MCP 층으로.
///
/// 두 길은 서로 기대지 않는다: 중계에 쓸 키가 없어도 `/mcp`는 그대로 돈다.
library;

import 'dart:io';

import 'assist_proxy.dart';
import 'mcp_handler.dart';
import 'mcp_http.dart';

Future<void> routeRequest(
  HttpRequest req, {
  required McpHandler mcp,
  required AssistProxy assist,
  required void Function(String) log,
}) => req.uri.path == assistProxyPath ? assist.handle(req) : handleMcpHttp(req, mcp, log);
