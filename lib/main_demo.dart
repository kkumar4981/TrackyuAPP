import 'package:flutter/material.dart';
import 'core/app_controller.dart';
import 'ui/shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FieldForce());
}

class FieldForce extends StatefulWidget {
  const FieldForce({super.key});
  @override State<FieldForce> createState()=>_FieldForceState();
}
class _FieldForceState extends State<FieldForce> with WidgetsBindingObserver {
  final controller=AppController();
  late final Future<void> boot;
  @override void initState() {
    super.initState(); WidgetsBinding.instance.addObserver(this);
    boot=controller.initialize();
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if(state==AppLifecycleState.resumed && controller.initialized) {
      controller.resume().catchError((Object e)=>controller.report('RESUME_ERROR',e.toString()));
    }
  }
  @override void dispose() {
    WidgetsBinding.instance.removeObserver(this);controller.dispose();super.dispose();
  }
  @override Widget build(BuildContext context)=>MaterialApp(
    title:'FieldForce HRMS',debugShowCheckedModeBanner:false,
    theme:ThemeData(useMaterial3:true,scaffoldBackgroundColor:const Color(0xfff4f7fa),
      colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xff087f79)),
      appBarTheme:const AppBarTheme(backgroundColor:Color(0xfff4f7fa),centerTitle:false),
      inputDecorationTheme:const InputDecorationTheme(border:OutlineInputBorder(),filled:true,fillColor:Colors.white)),
    home:FutureBuilder<void>(future:boot,builder:(context,snapshot) {
      if(snapshot.hasError) { return Scaffold(body:SafeArea(child:Padding(padding:const EdgeInsets.all(24),
        child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
          const Icon(Icons.error_outline,size:48),const Text('Startup needs attention'),
          SelectableText('${snapshot.error}'),const SizedBox(height:16),
          const Text('Check native setup, storage availability and API_BASE_URL. No attendance has been confirmed.')])))); }
      if(snapshot.connectionState!=ConnectionState.done) { return const Scaffold(body:Center(child:CircularProgressIndicator())); }
      return AnimatedBuilder(animation:controller,builder:(_,__)=>controller.loggedIn?
        AppShell(controller):LoginScreen(controller));
    }));
}
