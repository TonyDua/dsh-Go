import 'dart:convert';

import 'package:dsh_client/dsh_client.dart';

import '../../l10n/l10n.dart';
import '../link_status.dart';
import 'remote_bootstrap.dart';
import 'remote_shell.dart';
import 'ssh_transport.dart';

/// Read the launch URL of the user's existing home Windows DSH service.
/// The URL only travels inside SSH and must not be put in error details.
class WindowsDshAttach {
  static String get command {
    return commandFor(null);
  }

  static String commandFor(String? logPath) {
    final path = base64Encode(utf8.encode(logPath?.trim().isNotEmpty == true ? logPath!.trim() : r'.dsh\remote-host-restart\dsh.log'));
    final script = r'''
$ErrorActionPreference = 'Stop'
$path = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('PATHBASE64'))
if ($path.StartsWith('~\') -or $path.StartsWith('~/')) { $path = $path.Substring(2) }
if ([IO.Path]::IsPathRooted($path)) { $log = $path } else { $log = Join-Path $env:USERPROFILE $path }
if (-not (Test-Path -LiteralPath $log -PathType Leaf)) { exit 3 }
$line = Get-Content -LiteralPath $log | Select-String -Pattern 'http://127\.0\.0\.1:[0-9]+/\?token=[^\s]+' | Select-Object -Last 1
if ($null -eq $line -or $line.Line -notmatch 'http://127\.0\.0\.1:[0-9]+/\?token=[^\s]+') { exit 4 }
[Console]::Out.WriteLine($Matches[0])
'''.replaceFirst('PATHBASE64', path);
    final bytes = <int>[];
    for (final unit in script.codeUnits) {
      bytes.add(unit & 0xff);
      bytes.add(unit >> 8);
    }
    return 'powershell.exe -NoLogo -NoProfile -NonInteractive -EncodedCommand ${base64Encode(bytes)}';
  }

  static Future<RemoteDshEndpoint> resolve(SshRawCommand transport, {String? logPath}) async {
    final result = await transport.runRaw(commandFor(logPath));
    return parseResult(result);
  }

  /// Only a loopback launch URL may cross into an SSH tunnel. Never include
  /// raw stdout or stderr in failures: a log can contain credentials.
  static RemoteDshEndpoint parseResult(RemoteExecResult result) {
    if (!result.ok) {
      throw HostLinkError(HostLinkErrorKind.other, appL10n.remoteWindowsAttachError, retryable: true);
    }
    final parsed = DshLaunchUrl.tryParse(result.stdout);
    if (parsed == null || parsed.baseUri.scheme != 'http' || parsed.baseUri.host != '127.0.0.1' ||
        parsed.baseUri.port < 1 || parsed.baseUri.port > 65535 || parsed.baseUri.path.isNotEmpty) {
      throw HostLinkError(HostLinkErrorKind.other, appL10n.remoteWindowsAttachError, retryable: true);
    }
    return RemoteDshEndpoint(port: parsed.baseUri.port, token: parsed.token, reused: true);
  }
}

/// Attach to an explicitly configured POSIX log without starting a server.
class PosixDshAttach {
  static String script(String path) {
    final value = path.trim();
    if (value.isEmpty || value.contains('\u0000') || value.contains('\n') || value.contains('\r')) {
      throw HostLinkError(HostLinkErrorKind.other, appL10n.remoteWindowsAttachError);
    }
    final expression = value.startsWith('~/')
        ? '"\$HOME"/${shQuote(value.substring(2))}'
        : value.startsWith('/') ? shQuote(value) : '"\$HOME"/${shQuote(value)}';
    return '''log=$expression
test -f "\$log" || exit 3
url=\$(grep -Eo 'http://127\\.0\\.0\\.1:[0-9]+/\\?token=[^[:space:]]+' "\$log" | tail -n 1)
test -n "\$url" || exit 4
printf '%s\\n' "\$url"
''';
  }

  static Future<RemoteDshEndpoint> resolve(RemoteShell shell, String path) async =>
      WindowsDshAttach.parseResult(await shell.run(script(path)));
}
