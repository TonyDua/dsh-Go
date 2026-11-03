import 'dart:io';

import 'package:dsh_app/remote/ssh/remote_shell.dart';
import 'package:dsh_app/remote/ssh/ssh_host_config.dart';
import 'package:dsh_app/remote/ssh/ssh_transport.dart';
import 'package:dsh_app/remote/ssh/windows_attach.dart';
import 'package:flutter_test/flutter_test.dart';

class RawCommand implements SshRawCommand {
  RawCommand(this.result);
  final RemoteExecResult result;
  String? command;
  @override
  Future<RemoteExecResult> runRaw(String command, {Duration timeout = const Duration(seconds: 30)}) async {
    this.command = command;
    return result;
  }
}

void main() {
  test('attaches to an existing loopback endpoint through raw PowerShell', () async {
    final shell = RawCommand(const RemoteExecResult(0, 'http://127.0.0.1:3080/?token=test-token\n', ''));
    final endpoint = await WindowsDshAttach.resolve(shell);
    expect(endpoint.port, 3080);
    expect(endpoint.token, 'test-token');
    expect(endpoint.reused, isTrue);
    expect(shell.command, startsWith('powershell.exe -NoLogo -NoProfile -NonInteractive -EncodedCommand '));
  });

  test('rejects non-loopback and missing launch URLs without leaking output', () async {
    for (final output in ['http://example.com:3080/?token=secret', 'http://127.0.0.1:3080/path?token=secret', 'secret']) {
      await expectLater(WindowsDshAttach.resolve(RawCommand(RemoteExecResult(0, output, ''))),
          throwsA(predicate((e) => !e.toString().contains('secret'))));
    }
    await expectLater(WindowsDshAttach.resolve(RawCommand(const RemoteExecResult(1, 'secret', 'secret'))),
        throwsA(predicate((e) => !e.toString().contains('secret'))));
  });

  test('Windows setting persists and changes the connection identity', () {
    const config = SshHostConfig(id: 'a', name: 'a', host: 'h', user: 'u');
    final windows = config.copyWith(windowsAttachExisting: true);
    expect(SshHostConfig.fromJson(windows.toJson()), windows);
    expect(windows.connectionKey, isNot(config.connectionKey));
    expect(SshHostConfig.fromJson(config.toJson())!.windowsAttachExisting, isFalse);
    final posix = windows.copyWith(existingDshPlatform: 'posix', existingDshLogPath: () => '~/logs/dsh.log');
    expect(SshHostConfig.fromJson(posix.toJson()), posix);
    expect(posix.connectionKey, isNot(windows.connectionKey));
    expect(SshHostConfig.fromJson(windows.toJson())!.existingDshPlatform, 'windows');
  });

  test('POSIX attaches from a quoted log path without interpreting shell text', () async {
    final temp = await Directory.systemTemp.createTemp('dsh-log-test-');
    addTearDown(() => temp.delete(recursive: true));
    final log = File("${temp.path}/dsh'\$(touch injected).log");
    await log.writeAsString('http://127.0.0.1:3080/?token=test-token\n');
    final endpoint = await PosixDshAttach.resolve(LocalProcessShell(workingDirectory: temp.path), log.path);
    expect(endpoint.port, 3080);
    expect(endpoint.token, 'test-token');
    expect(await File('${temp.path}/injected').exists(), isFalse);
  });

  test('POSIX missing logs and non-loopback launch fail without leaking content', () async {
    await expectLater(PosixDshAttach.resolve(LocalProcessShell(), '/no-such-dsh-test-log'), throwsA(isA<Exception>()));
    expect(() => PosixDshAttach.script(''), throwsA(isA<Exception>()));
    final raw = WindowsDshAttach.commandFor("log'\$(do-not-run)");
    expect(raw, isNot(contains('do-not-run')));
  });
}
