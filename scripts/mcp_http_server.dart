// A-001 원격 MCP 서버 진입점 — Cloud Run에서 `dart compile exe`로 돈다(배포: scripts/deploy_mcp.sh).
//
//   dart run scripts/mcp_http_server.dart          → PORT(기본 8080)에서 POST /mcp
//   FINDCHEM_DATA=<번들 JSON 경로>                  → 데이터 위치(기본 assets/data/findchem_data.json)
//
// 여기에는 규칙도 문장도 없다 — 프로토콜은 lib/mcp/, 도구는 lib/assist/(앱ㆍ웹과 같은 코드).
// 로그는 stderr 한 줄씩(Cloud Run이 Cloud Logging으로 모은다).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:findchem/mcp/mcp_handler.dart';
import 'package:findchem/mcp/mcp_http.dart';
import 'package:findchem/parser/models.dart';

/// 배포 판 구분용. 서버 동작을 바꾸면 올린다.
const serverVersion = '0.1.0-a001';

void log(String message) => stderr.writeln(message);

Future<void> main() async {
  final dataPath = Platform.environment['FINDCHEM_DATA'] ?? 'assets/data/findchem_data.json';
  final Dataset ds;
  try {
    ds = Dataset.fromJson((jsonDecode(File(dataPath).readAsStringSync()) as Map).cast<String, Object?>());
  } catch (e) {
    // 데이터 없이 뜨면 모든 검색이 0건으로 "없음"을 답한다 — 기동을 거부한다(fail-closed).
    log('A-001 MCP: 번들 JSON을 읽지 못해 기동 중단($dataPath) — $e');
    exit(2);
  }
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final handler = McpHandler(ds, version: serverVersion, log: log);
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  log('A-001 MCP: $serverVersion 기동 — 포트 $port, 데이터 $dataPath');
  await for (final req in server) {
    // 요청을 기다리지 않고 받는다(동시 요청). 예외는 handleMcpHttp 안에서 로그로 남는다.
    unawaited(handleMcpHttp(req, handler, log));
  }
}
