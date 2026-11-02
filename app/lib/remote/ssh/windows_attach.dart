import 'dart:convert';

import 'package:dsh_client/dsh_client.dart';

import '../../l10n/l10n.dart';
import '../link_status.dart';
import 'remote_bootstrap.dart';
import 'ssh_transport.dart';

/// Read the launch URL of the user's existing home Windows DSH service.
/// The URL only travels inside SSH and must not be put in error details.
class WindowsDshAttach {
  static String get command {
    const script = r'''
$ErrorActionPreference = 'Stop'
$log = Join-Path $env:USERPROFILE '.dsh\remote-host-restart\dsh.log'
if (-not (Test-Path -LiteralPath $log -PathType Leaf)) { exit 3 }
$line = Get-Content -LiteralPath $log | Select-String -Pattern 'http://127\.0\.0\.1:[0-9]+/\?token=[^\s]+' | Select-Object -Last 1
if ($null -eq $line -or $line.Line -notmatch 'http://127\.0\.0\.1:[0-9]+/\?token=[^\s]+') { exit 4 }
[Console]::Out.WriteLine($Matches[0])
''';
    final bytes = <int>[];
    for (final unit in script.codeUnits) {
      bytes.add(unit & 0xff);
      bytes.add(unit >> 8);
    }
    return 'powershell.exe -NoLogo -NoProfile -NonInteractive -EncodedCommand ${base64Encode(bytes)}';
  }

  static Future<RemoteDshEndpoint> resolve(SshRawCommand transport) async {
    final result = await transport.runRaw(command);
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
