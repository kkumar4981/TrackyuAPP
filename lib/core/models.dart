import 'dart:math' as math;

typedef Json = Map<String, dynamic>;

class Fix {
  final String id;
  final double lat, lng, accuracy;
  final DateTime capturedAt;
  const Fix(this.id, this.lat, this.lng, this.accuracy, this.capturedAt);
  factory Fix.fromJson(Json j) => Fix(
      j['id']?.toString() ?? '',
      ((j['lat'] ?? j['latitude']) as num?)?.toDouble() ?? 0.0,
      ((j['lng'] ?? j['longitude']) as num?)?.toDouble() ?? 0.0,
      ((j['accuracy'] ?? j['accuracyMeters']) as num?)?.toDouble() ?? 0.0,
      DateTime.tryParse(j['capturedAt']?.toString() ?? '') ?? DateTime.now());
  Json toJson() => {'id':id, 'lat':lat, 'lng':lng, 'accuracy':accuracy,
    'capturedAt':capturedAt.toUtc().toIso8601String()};
}

double distanceMeters(double a, double b, double c, double d) {
  const rad = math.pi / 180;
  final x = math.pow(math.sin((c-a)*rad/2),2) +
    math.cos(a*rad)*math.cos(c*rad)*math.pow(math.sin((d-b)*rad/2),2);
  return 6371000 * 2 * math.asin(math.sqrt(x.toDouble().clamp(0.0, 1.0)));
}

class Policy {
  final Json json;
  Policy(this.json) { validate(); }
  factory Policy.parse(dynamic value) => Policy(Map<String,dynamic>.from(value as Map));
  num n(String key) => (json[key] as num?) ?? 0;
  double get lat => n('officeLat').toDouble();
  double get lng => n('officeLng').toDouble();
  double get radius => n('officeRadiusMeters').toDouble();
  double get movement => n('movementMeters').toDouble();
  bool get office => json['employeeType'] == 'office';
  bool get offlineAllowed => json['allowOfflineAttendance'] == true;
  bool get backgroundRequired => json['backgroundRequired'] == true;
  String get label => '${json['id']} · v${json['version']}';
  List<Json> get rules => (json['rules'] as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
  void validate() {
    for (final key in ['officeLat','officeLng','officeRadiusMeters','movementMeters',
      'maxAccuracyMeters','maxLocationAgeSeconds','startHour','startMinute',
      'endHour','endMinute','graceMinutes','utcOffsetMinutes','version']) {
      if (json[key] is! num) { throw FormatException('Policy missing numeric $key'); }
    }
    if (radius <= 0 || movement <= 0 || n('maxAccuracyMeters') <= 0 ||
      n('maxLocationAgeSeconds') <= 0 || lat.abs()>90 || lng.abs()>180 ||
      n('startHour')<0 || n('startHour')>23 || n('endHour')<0 || n('endHour')>23 ||
      n('startMinute')<0 || n('startMinute')>59 || n('endMinute')<0 || n('endMinute')>59) {
      throw const FormatException('Invalid policy values');
    }
    for(final rule in rules) { RuleEngine.validate(rule); }
  }
  String? fixProblem(Fix fix, DateTime now) {
    final age = now.toUtc().difference(fix.capturedAt.toUtc()).inSeconds;
    if (age < -10 || age > n('maxLocationAgeSeconds')) { return 'Location is stale. Refresh GPS.'; }
    if (fix.accuracy <= 0 || fix.accuracy > n('maxAccuracyMeters')) {
      return 'GPS accuracy ${fix.accuracy.round()} m is insufficient. Move to an open area.';
    }
    return null;
  }
  Json facts(DateTime now, Fix? fix, DateTime? checkedInAt) {
    // Fixed office offset supplied by policy; the server remains authoritative.
    final local = now.toUtc().add(Duration(minutes:n('utcOffsetMinutes').toInt()));
    final anchor = (checkedInAt ?? now).toUtc().add(Duration(minutes:n('utcOffsetMinutes').toInt()));
    var start = DateTime.utc(anchor.year,anchor.month,anchor.day,
      n('startHour').toInt(),n('startMinute').toInt());
    var end = DateTime.utc(anchor.year,anchor.month,anchor.day,
      n('endHour').toInt(),n('endMinute').toInt());
    if(json['overnight']==true) {
      if(checkedInAt==null && local.isBefore(end)) { start=start.subtract(const Duration(days:1)); }
      if(!end.isAfter(start)) { end=end.add(const Duration(days:1)); }
    }
    return {'isOffice':office,
      'outsideOffice': fix==null || distanceMeters(lat,lng,fix.lat,fix.lng)>radius,
      'lateMinutes':math.max(0,local.difference(start).inMinutes),'graceMinutes':n('graceMinutes'),
      'earlyMinutes':math.max(0,end.difference(local).inMinutes),
      // Approval facts must come from the backend, never user checkboxes.
      'lateExemptionApproved':json['lateExemptionApproved']==true,
      'halfDayApproved':json['halfDayApproved']==true};
  }
}

class RuleEngine {
  static const fields = {'isOffice','outsideOffice','lateMinutes','earlyMinutes',
    'lateExemptionApproved','halfDayApproved','graceMinutes'};
  static void validate(Json rule) {
    if(!['checkIn','checkOut'].contains(rule['event'])) { throw const FormatException('Unknown event'); }
    _validateCondition(Map<String,dynamic>.from(rule['when'] as Map),0);
    final e=Map<String,dynamic>.from(rule['effect'] as Map);
    if(!['block','requireField'].contains(e['kind']) ||
      (e['kind']=='requireField' && e['field']!='reason')) {
      throw const FormatException('Unsupported rule effect');
    }
  }
  static void _validateCondition(Json c,int depth) {
    if(depth>8) { throw const FormatException('Rule nesting limit'); }
    if(c.containsKey('all') || c.containsKey('any')) {
      final list=(c[c.containsKey('all')?'all':'any'] as List);
      if(list.isEmpty || list.length>20) { throw const FormatException('Invalid condition group'); }
      for(final child in list) { _validateCondition(Map<String,dynamic>.from(child as Map),depth+1); }
    } else if(!fields.contains(c['field']) || !['eq','gt','gte','lt','lte'].contains(c['op']) ||
      (c.containsKey('valueFrom') && !fields.contains(c['valueFrom'])) ||
      (!c.containsKey('value') && !c.containsKey('valueFrom'))) {
      throw const FormatException('Unsupported field/operator');
    }
  }
  static bool matches(Json c, Json facts) {
    if(c.containsKey('all')) { return (c['all'] as List).every((e)=>matches(Map<String,dynamic>.from(e as Map),facts)); }
    if(c.containsKey('any')) { return (c['any'] as List).any((e)=>matches(Map<String,dynamic>.from(e as Map),facts)); }
    final a=facts[c['field']], b=c.containsKey('valueFrom')?facts[c['valueFrom']]:c['value'];
    if(c['op']=='eq') { return a==b; }
    if(a is! num || b is! num) { throw const FormatException('Numeric comparison expected'); }
    return switch(c['op']) {'gt'=>a>b,'gte'=>a>=b,'lt'=>a<b,'lte'=>a<=b,_=>false};
  }
  static List<Json> evaluate(Policy policy,String event,Json facts,Json input) {
    final issues=<Json>[];
    for(final rule in policy.rules.where((r)=>r['event']==event)) {
      if(!matches(Map<String,dynamic>.from(rule['when'] as Map),facts)) { continue; }
      final e=Map<String,dynamic>.from(rule['effect'] as Map);
      if(e['kind']=='block' || (input[e['field']]?.toString().trim() ?? '').isEmpty) {
        issues.add({...e,'ruleId':rule['id']});
      }
    }
    return issues;
  }
}

class TeamMember {
  final String id,name,status;
  final Fix? fix;
  final DateTime? lastContact;
  TeamMember(this.id,this.name,this.status,this.fix,this.lastContact);
  factory TeamMember.fromJson(Json j)=>TeamMember(j['id'] as String,j['name'] as String,
    j['status'] as String,j['location']==null?null:Fix.fromJson(Map<String,dynamic>.from(j['location'] as Map)),
    j['lastContact']==null?null:DateTime.parse(j['lastContact'] as String));
  bool stale(DateTime now)=>fix==null || now.toUtc().difference(fix!.capturedAt.toUtc()).inMinutes>=3;
}
