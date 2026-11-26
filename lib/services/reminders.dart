import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../core/models.dart';
import 'store.dart';

class Reminders {
  final LocalStore store;
  final plugin=FlutterLocalNotificationsPlugin();
  Reminders(this.store);
  Future<void> initialize() async {
    tzdata.initializeTimeZones();
    await plugin.initialize(const InitializationSettings(
      android:AndroidInitializationSettings('ic_stat_notification'),
      iOS:DarwinInitializationSettings(requestAlertPermission:false,
        requestBadgePermission:false,requestSoundPermission:false)));
  }
  Future<bool> permission() async {
    if(Platform.isAndroid) {
      return await plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission()??false;
    }
    return await plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
      ?.requestPermissions(alert:true,badge:true,sound:true)??false;
  }
  Future<List<Json>> list() async=>((await store.get('reminders')) as List? ?? [])
    .map((e)=>Map<String,dynamic>.from(e as Map)).toList();
  Future<void> save(String title,int hour,int minute) async {
    if(title.trim().isEmpty) { throw Exception('Enter a reminder title.'); }
    if(!await permission()) { throw Exception('Allow notifications in Settings to schedule a reminder.'); }
    final rows=await list();
    if(rows.length>=30) { throw Exception('Maximum 30 daily reminders.'); }
    final id=DateTime.now().millisecondsSinceEpoch%2000000000;
    final row={'id':id,'title':title.trim(),'hour':hour,'minute':minute,'zone':'Asia/Kolkata'};
    await _schedule(row);
    rows.add(row); await store.set('reminders',rows);
  }
  Future<void> _schedule(Json row) async {
    final zone=tz.getLocation(row['zone'] as String);
    final now=tz.TZDateTime.now(zone);
    var next=tz.TZDateTime(zone,now.year,now.month,now.day,row['hour'] as int,row['minute'] as int);
    if(!next.isAfter(now)) { next=tz.TZDateTime(zone,now.year,now.month,now.day+1,row['hour'] as int,row['minute'] as int); }
    await plugin.zonedSchedule(row['id'] as int,row['title'] as String,
      'Your HRMS reminder',next,const NotificationDetails(
        android:AndroidNotificationDetails('hrms_reminders','HRMS reminders',
          channelDescription:'Employee attendance and work reminders',importance:Importance.high,priority:Priority.high),
        iOS:DarwinNotificationDetails()),
      androidScheduleMode:AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents:DateTimeComponents.time);
  }
  Future<void> reconcile() async {
    for(final row in await list()) { await _schedule(row); }
  }
  Future<void> remove(int id) async {
    await plugin.cancel(id);
    await store.set('reminders',(await list()).where((e)=>e['id']!=id).toList());
  }
}
