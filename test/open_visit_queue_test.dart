import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/trackyu/api.dart';
import 'package:fieldforce_hrms/trackyu/controller.dart';
import 'package:fieldforce_hrms/trackyu/visits.dart';
import 'session_race_test.dart' show TestVault, TestAdapter, jsonReply;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TestVault vault;
  TrackyuController make(Future<ResponseBody> Function(RequestOptions) respond) {
    vault = TestVault();
    final dio = Dio()..httpClientAdapter = TestAdapter(respond);
    return TrackyuController(TrackyuApi('https://test.example/api', client: dio), vault: vault,
        locate: () async => {'latitude':19.0,'longitude':72.0,'accuracyMeters':5.0,
          'capturedAtUtc':DateTime.now().toUtc().toIso8601String()})
      ..user = {'userId': 'A'};
  }
  Map<String, dynamic> pending(TrackyuController c, String request, {String? scope}) => {
    'scope': scope ?? '${c.api.baseUrl}|${c.employeeId}', 'finish': true,
    'body': {'id': 268, 'requestId': request, 'departureSelfieBase64': 'saved-photo'},
  };
  for (final status in [400, 401, 403, 404, 409, 500]) {
    test('HTTP $status retains checkout and photo in persisted queue', () async {
      final c = make((_) async => jsonReply(null, status: status, success: false, code: 'VISIT_CHANGED'));
      c.pendingVisits.add(pending(c, 'finish-A'));
      await c.syncPendingVisits();
      expect(c.pendingVisits, hasLength(1));
      expect(jsonDecode(vault.pendingVisits!).single['body']['departureSelfieBase64'], 'saved-photo');
      c.dispose();
    });
  }
  test('dismiss only clears banner, retaining persisted checkout', () async {
    final c = make((_) async => jsonReply({'id':268}));
    c.pendingVisits.add(pending(c, 'finish-A'));
    vault.pendingVisits = jsonEncode(c.pendingVisits);
    c.setClosingVisit(id:'268');
    await c.forceClearStuckVisitClose();
    expect(c.isClosingVisit, isFalse);
    expect(c.hasPendingVisitClose, isFalse);
    expect(c.pendingVisits, hasLength(1));
    expect(jsonDecode(vault.pendingVisits!), hasLength(1));
    c.dispose();
  });
  testWidgets('timeout releases banner without acknowledging queued checkout', (tester) async {
    final c=make((_) async => jsonReply({'id':268}));
    c.pendingVisits.add(pending(c,'A'));
    c.setClosingVisit(id:'268');
    expect(c.hasPendingVisitClose,isTrue);
    await tester.pump(const Duration(seconds:26));
    expect(c.hasPendingVisitClose,isFalse);
    expect(c.pendingVisits.single['body']['departureSelfieBase64'],'saved-photo');
    c.dispose();
  });
  test('receipt cannot remove another workspace checkout with same visit ID', () async {
    final c = make((_) async => jsonReply({'id':268}));
    c.pendingVisits.addAll([pending(c,'A'),pending(c,'B',scope:'another-workspace|B')]);
    await c.syncPendingVisits();
    expect(c.pendingVisits, hasLength(1));
    expect(c.pendingVisits.single['body']['requestId'], 'B');
    c.dispose();
  });
  for (final receipt in [null, <String,dynamic>{}, {'id':0}, {'id':999}]) {
    test('unconfirmed or mismatched receipt $receipt retains checkout', () async {
      final c = make((_) async => jsonReply(receipt));
      c.pendingVisits.add(pending(c,'A'));
      await c.syncPendingVisits();
      expect(c.pendingVisits, hasLength(1));
      c.dispose();
    });
  }
  test('overlapping sync calls submit checkout only once', () async {
    final entered = Completer<void>(), release = Completer<void>();
    int calls=0;
    final c = make((_) async { calls++; if(!entered.isCompleted) entered.complete(); await release.future; return jsonReply({'id':268}); });
    c.pendingVisits.add(pending(c,'A'));
    final first=c.syncPendingVisits(); await entered.future;
    final second=c.syncPendingVisits();
    release.complete(); await Future.wait([first,second]);
    expect(calls,1); expect(c.pendingVisits,isEmpty);
    c.dispose();
  });
  test('account switch during request cannot acknowledge replacement queue', () async {
    final entered = Completer<void>(), release = Completer<void>();
    final c = make((_) async { entered.complete(); await release.future; return jsonReply({'id':268}); });
    c.pendingVisits.add(pending(c,'A'));
    final sync=c.syncPendingVisits(); await entered.future;
    c.user={'userId':'B'};
    c.pendingVisits.clear(); c.pendingVisits.add(pending(c,'B'));
    vault.pendingVisits=jsonEncode(c.pendingVisits);
    release.complete(); await sync;
    expect(c.pendingVisits.single['body']['requestId'],'B');
    expect(jsonDecode(vault.pendingVisits!).single['body']['requestId'],'B');
    c.dispose();
  });
  test('stale visits load cannot replace new account active shop', () async {
    final entered=Completer<void>(), release=Completer<ResponseBody>();
    final c=make((r) async {
      if(r.path=='MobileMenus') return jsonReply([]);
      entered.complete(); return release.future;
    });
    final data=VisitsData(c);
    final loading=data.load(); await entered.future;
    c.user={'userId':'B'}; c.activeVisit={'id':777,'shopName':'B shop'};
    release.complete(jsonReply([{'id':268,'checkOutUtc':null}]));
    await loading;
    expect(c.activeVisit!['id'],777);
    data.dispose(); c.dispose();
  });
  test('closed row does not silently discard newly captured departure photo', () async {
    final c=make((_) async => jsonReply([]));
    final now=DateTime.now().toUtc();
    c.isField=true; c.stateKnown=true; c.enabledMenus={'visits'};
    c.attendance={'id':1,'punchInUtc':now.subtract(const Duration(hours:1)).toIso8601String(),'punchOutUtc':null};
    c.syncServerTime(now.toIso8601String()); c.setOffline(true);
    final data=VisitsData(c,capture:() async=>'new-departure-photo');
    data.rows=[{'id':268,'kind':'Open','requestId':'start-A','checkOutUtc':now.subtract(const Duration(minutes:5)).toIso8601String()}];
    await data.save(finish:true,fields:{'id':268,'kind':'Open'});
    expect(c.pendingVisits.single['body']['departureSelfieBase64'],'new-departure-photo');
    data.dispose(); c.dispose();
  });
}
