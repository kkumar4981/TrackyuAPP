import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/core/models.dart';

Policy loadPolicy()=>Policy.parse(jsonDecode(File('assets/default_policy.json').readAsStringSync()));
Fix point(DateTime at,{double lat=23.2599,double lng=77.4126,double accuracy=10})=>Fix('test',lat,lng,accuracy,at);
void main() {
  group('Attendance policy',(){
    test('Office check-in inside boundary and before grace needs no reason',(){
      final p=loadPolicy(),now=DateTime.utc(2026,11,6,4,5); // 09:35 IST
      expect(RuleEngine.evaluate(p,'checkIn',p.facts(now,point(now),null),{}),isEmpty);
    });
    test('Exactly 10 minutes late remains within grace',(){
      final p=loadPolicy(),now=DateTime.utc(2026,11,6,4,10);
      expect(RuleEngine.evaluate(p,'checkIn',p.facts(now,point(now),null),{}),isEmpty);
    });
    test('11 minutes late requires reason',(){
      final p=loadPolicy(),now=DateTime.utc(2026,11,6,4,11);
      expect(RuleEngine.evaluate(p,'checkIn',p.facts(now,point(now),null),{}).single['field'],'reason');
      expect(RuleEngine.evaluate(p,'checkIn',p.facts(now,point(now),null),{'reason':'Traffic'}),isEmpty);
    });
    test('Changing grace configuration changes evaluation without rule rewrite',(){
      final p=loadPolicy();p.json['graceMinutes']=20;
      final now=DateTime.utc(2026,11,6,4,15);
      expect(RuleEngine.evaluate(p,'checkIn',p.facts(now,point(now),null),{}),isEmpty);
    });
    test('Outside office is blocked even when reason supplied',(){
      final p=loadPolicy(),now=DateTime.utc(2026,11,6,4);
      expect(RuleEngine.evaluate(p,'checkIn',p.facts(now,point(now,lat:23.28),null),{'reason':'Traffic'})
        .any((e)=>e['kind']=='block'),isTrue);
    });
    test('Field employee is not office-geofence blocked',(){
      final p=loadPolicy();p.json['employeeType']='field';final now=DateTime.utc(2026,11,6,4);
      expect(RuleEngine.evaluate(p,'checkIn',p.facts(now,point(now,lat:23.28),null),{}),isEmpty);
    });
    test('Early checkout requires reason unless backend approved half day',(){
      final p=loadPolicy(),now=DateTime.utc(2026,11,6,8);
      expect(RuleEngine.evaluate(p,'checkOut',p.facts(now,null,DateTime.utc(2026,11,6,4)),{}),isNotEmpty);
      p.json['halfDayApproved']=true;
      expect(RuleEngine.evaluate(p,'checkOut',p.facts(now,null,DateTime.utc(2026,11,6,4)),{}),isEmpty);
    });
    test('Offline fix cannot be treated as a fresh attendance fix',(){
      final p=loadPolicy(),now=DateTime.utc(2026,11,6,4);
      expect(p.fixProblem(point(now.subtract(const Duration(minutes:2))),now),isNotNull);
      expect(p.fixProblem(point(now,accuracy:500),now),isNotNull);
      expect(p.fixProblem(point(now.add(const Duration(minutes:2))),now),isNotNull);
      expect(p.fixProblem(point(now),now),isNull);
    });
    test('UTC evaluation is independent of phone timezone',(){
      final p=loadPolicy(),now=DateTime.parse('2026-11-06T09:41:00+05:30');
      expect(p.facts(now,point(now),null)['lateMinutes'],11);
    });
    test('Overnight shift checkout uses original shift start date',(){
      final p=loadPolicy();p.json.addAll({'startHour':22,'startMinute':0,'endHour':6,'endMinute':0,'overnight':true});
      final facts=p.facts(DateTime.utc(2026,11,7,0),null,DateTime.utc(2026,11,6,16,30));
      expect(facts['earlyMinutes'],30); // 05:30 local -> 06:00 shift end
    });
    test('Unsupported effect and arbitrary expression rejected',(){
      final p=loadPolicy();
      expect(()=>RuleEngine.validate({'event':'checkIn','when':{'field':'executeSql','op':'eq','value':true},
        'effect':{'kind':'block'}}),throwsFormatException);
      expect(()=>RuleEngine.validate({'event':'checkIn','when':{'field':'lateMinutes','op':'gt','value':1},
        'effect':{'kind':'executeCode'}}),throwsFormatException);
      expect(p.rules,isNotEmpty);
    });
    test('Missing numeric configuration fails closed',(){
      final json=loadPolicy().json;json.remove('officeRadiusMeters');
      expect(()=>Policy(json),throwsFormatException);
    });
  });
  test('Distance handles identical and threshold-separated points',(){
    expect(distanceMeters(23,77,23,77),closeTo(0,0.001));
    expect(distanceMeters(23,77,23.001,77),inInclusiveRange(110,112));
  });
  test('Team location freshness independent of server contact freshness',(){
    final now=DateTime.utc(2026,11,6,10);
    final member=TeamMember('1','Salesperson','onDuty',point(now.subtract(const Duration(minutes:5))),now);
    expect(member.stale(now),isTrue);
  });
}
