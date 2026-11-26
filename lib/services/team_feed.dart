import 'package:signalr_netcore/signalr_client.dart';
import '../core/models.dart';

class TeamFeed {
  HubConnection? hub;
  Future<void> connect(String url,Future<String> Function() token,
    void Function(TeamMember) update,void Function() resnapshot,void Function(String) status) async {
    await close();
    final h=HubConnectionBuilder().withUrl('$url/hubs/tracking',options:HttpConnectionOptions(
      accessTokenFactory:token)).withAutomaticReconnect().build();
    hub=h;
    h.on('LocationUpdated',(args) {
      try { if(args!=null && args.isNotEmpty) { update(TeamMember.fromJson(Map<String,dynamic>.from(args.first as Map))); } }
      catch(_) { status('Invalid live payload; refresh snapshot.'); }
    });
    h.onreconnecting(({error})=>status('Live connection interrupted. Showing last known positions.'));
    h.onreconnected(({connectionId}) { status('Live feed connected'); resnapshot(); });
    h.onclose(({error})=>status('Live feed disconnected; retry from Team map.'));
    await h.start(); status('Live feed connected');
    resnapshot();
  }
  Future<void> close() async { await hub?.stop(); hub=null; }
}
