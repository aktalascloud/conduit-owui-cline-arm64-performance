import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:conduit_core/features/cline/models/cline_remote_profile.dart';
import 'package:conduit_core/features/cline/services/cline_native_client.dart';
import 'package:conduit_core/features/cline/services/cline_ssh_tunnel.dart';

/// Read-only probe: connects, lists sessions and hydrates history. Never sends an agent prompt.
Future<void> main(List<String> args) async {
  ClineSshTunnel? tunnel;ClineNativeClient? client;
  try {
    final data=jsonDecode(await File(args.first).readAsString()) as Map<String,dynamic>;
    if(args.length>1){data['host']='127.0.0.1';data['sshPort']=int.parse(args[1]);}
    final profile=ClineRemoteProfile.decode(jsonEncode(data));
    tunnel=await ClineSshTunnel.connect(profile,localPort:0);
    client=await ClineNativeClient.connect(tunnel);
    final context=await client.request('get_process_context');
    final records=await client.request('list_cli_sessions');
    if(context is! Map || records is! List)throw const ClineNativeException('contract');
    var hydrated=0;
    if(client.state.sessions.isNotEmpty){
      final first=client.state.sessions.first.id;
      final complete=client.changes.firstWhere((s)=>s.sessionId==first&&!s.loadingHistory);
      client.openSession(first);final state=await complete.timeout(const Duration(seconds:20));
      hydrated=state.messages.length;
    }
    stdout.writeln(jsonEncode({'status':'passed','native_json_transport':true,'mandatory_ssh_pin':true,
      'session_count':records.length,'hydrated_message_count':hydrated,'agent_messages_sent':0,
      'tool_approvals_sent':0,'webview_used':false}));
  }catch(error){stdout.writeln(jsonEncode({'status':'failed','error_type':error.runtimeType.toString(),
      'code':error is ClineNativeException?error.code:'connection','private_details_withheld':true}));exitCode=1;}
  finally{await client?.close();await tunnel?.close();}
}
