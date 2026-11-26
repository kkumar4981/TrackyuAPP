import 'dart:convert';

import 'package:flutter/material.dart';

import 'address_cache.dart';

import 'api.dart';

import 'controller.dart';

import 'retailer_geotag_page.dart';

import 'trackyu_app_bar.dart';

import 'selfie.dart';

import 'workspace.dart' show jsonRows;



class OfficeLocationRequestPage extends StatefulWidget {

  final TrackyuController controller;

  final int initialTab;

  const OfficeLocationRequestPage({

    super.key,

    required this.controller,

    this.initialTab = 0,

  });

  @override

  State<OfficeLocationRequestPage> createState() =>

      _OfficeLocationRequestPageState();

}



class _OfficeLocationRequestPageState extends State<OfficeLocationRequestPage> {

  final form = GlobalKey<FormState>(),

      name = TextEditingController(),

      address = TextEditingController();



  String tagType = 'OFFICE'; // 'HOME', 'GODOWN', 'OFFICE'

  Json? point;

  String? photoBase64;

  List<Json> requests = [];

  bool busy = false;

  String? error, success;



  @override

  void initState() {

    super.initState();

    load();

    capture();

  }



  Future<dynamic> request(String path, {Json? body}) async {

    try {

      return await widget.controller.api.request(path, body: body);

    } on ApiFailure catch (e) {

      if (e.status == 401) {

        await widget.controller.signOut();

        if (mounted) Navigator.popUntil(context, (r) => r.isFirst);

      }

      rethrow;

    }

  }



  Future<void> load() async {

    try {

      final res = await request('OfficeLocationRequests/mine');

      final rows = jsonRows(res);

      if (mounted) setState(() => requests = rows);

    } catch (_) {

      try {

        final legacyRows = jsonRows(await request('GeoTags?mineOnly=true&tagType=OFFICE'));

        if (mounted) setState(() => requests = legacyRows);

      } catch (e) {

        if (mounted) setState(() => error = e.toString());

      }

    }

  }



  Future<void> capture() async {

    if (busy) return;

    setState(() {

      busy = true;

      error = null;

    });

    try {

      final value = await widget.controller.locate();

      if (mounted) {

        setState(() {

          point = value;

          if (name.text.isEmpty) {

            name.text = 'Branch / Office Location';

          }

          if (address.text.isEmpty && value['textLocation'] != null && value['textLocation'].toString().trim().isNotEmpty) {

            address.text = value['textLocation'].toString().trim();

          }

        });

      }

      final lat = (value['latitude'] as num?)?.toDouble();

      final lng = (value['longitude'] as num?)?.toDouble();

      if (lat != null && lng != null) {

        final rev = await TrackyuAddressCache.reverseGeocode(lat, lng);

        if (mounted && rev != null && rev.trim().isNotEmpty) {

          setState(() {

            address.text = rev.trim();

          });

        }

      }

    } catch (e) {

      if (mounted) setState(() => error = e.toString());

    } finally {

      if (mounted) setState(() => busy = false);

    }

  }



  Future<void> takeSelfie() async {

    try {

      final photo = await captureVisitPhoto();

      if (photo != null && mounted) {

        setState(() {

          photoBase64 = photo;

          error = null;

        });

      }

    } catch (e) {

      if (mounted) {

        ScaffoldMessenger.of(context).showSnackBar(

          SnackBar(content: Text('Camera error: $e')),

        );

      }

    }

  }



  Future<void> submit() async {

    if (busy || !form.currentState!.validate()) return;

    if (point == null) {

      setState(() => error = 'Please capture GPS coordinates first.');

      return;

    }

    if (photoBase64 == null || photoBase64!.trim().isEmpty) {

      setState(() => error = 'Verification photo is mandatory. Please capture a photo before submitting.');

      return;

    }



    setState(() {

      busy = true;

      error = null;

      success = null;

    });



    try {

      final location = await widget.controller.locate();

      final nowStr = DateTime.now().toLocal().toString().split('.')[0];

      final watermark =

          'Location: ${location['latitude']}, ${location['longitude']} | ${address.text.trim()} | $nowStr | Type: OFFICE';



      final nowUtcIso = DateTime.now().toUtc().toIso8601String();
      final capturedAt = (location['capturedAtUtc'] ?? nowUtcIso).toString();
      final officeName = name.text.trim().isNotEmpty ? name.text.trim() : 'Office Location';
      final officeAddress = address.text.trim();
      final lat = (location['latitude'] as num?)?.toDouble() ?? (point?['latitude'] as num?)?.toDouble() ?? 0.0;
      final lng = (location['longitude'] as num?)?.toDouble() ?? (point?['longitude'] as num?)?.toDouble() ?? 0.0;
      final acc = (location['accuracyMeters'] as num?)?.toDouble() ?? (point?['accuracyMeters'] as num?)?.toDouble() ?? 10.0;

      try {
        await request(
          'OfficeLocationRequests/submit',
          body: {
            'name': officeName,
            'address': officeAddress,
            'latitude': lat,
            'longitude': lng,
            'accuracyMeters': acc,
            'capturedAtUtc': capturedAt,
            if (photoBase64 != null) 'selfieBase64': photoBase64,
          },
        );
      } on ApiFailure catch (e) {
        if (e.status == 404) {
          await request(
            'GeoTags/submit',
            body: {
              'tagType': 'OFFICE',
              'name': officeName,
              'address': officeAddress,
              'latitude': lat,
              'longitude': lng,
              'accuracyMeters': acc,
              'capturedAtUtc': capturedAt,
              if (photoBase64 != null)
                'selfieUrl': 'data:image/jpeg;base64,$photoBase64',
              'watermarkText': watermark,
            },
          );
        } else {
          rethrow;
        }
      }



      if (mounted) {

        setState(() {

          point = location;

          photoBase64 = null;

          name.clear();

          address.clear();

          success =

              'Office location proposal submitted successfully! Your administrator will review and assign it.';

        });

      }

      await load();

    } catch (e) {

      if (mounted) setState(() => error = e.toString());

    } finally {

      if (mounted) setState(() => busy = false);

    }

  }



  @override

  void dispose() {

    name.dispose();

    address.dispose();

    super.dispose();

  }



  @override

  Widget build(BuildContext context) {

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DefaultTabController(

      length: 2,

      initialIndex: widget.initialTab,

      child: Scaffold(

        appBar: AppBar(

          title: const Text('Geo-Tag Location', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),

          elevation: 0,

          backgroundColor: isDark ? const Color(0xff0f172a) : Colors.white,

          actions: [

            TrackyuAppBarActions(controller: widget.controller),

          ],

          bottom: TabBar(

            indicatorColor: const Color(0xff0284c7),

            indicatorWeight: 3,

            labelColor: isDark ? const Color(0xff38bdf8) : const Color(0xff0284c7),

            unselectedLabelColor: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),

            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),

            tabs: const [

              Tab(

                icon: Icon(Icons.storefront_rounded),

                text: 'Retailer Location',

              ),

              Tab(

                icon: Icon(Icons.business_rounded),

                text: 'Office Mapping',

              ),

            ],

          ),

        ),

        body: TabBarView(

          children: [

            RetailerGeoTagPage(

              controller: widget.controller,

              isEmbedded: true,

            ),

            Center(

              child: ConstrainedBox(

                constraints: const BoxConstraints(maxWidth: 620),

                child: Form(

                  key: form,

                  child: ListView(

                    padding: const EdgeInsets.all(18),

                    children: [

                Container(

                  padding: const EdgeInsets.all(16),

                  decoration: BoxDecoration(

                    color: isDark ? const Color(0xff161e2e) : const Color(0xfff0f9ff),

                    borderRadius: BorderRadius.circular(14),

                    border: Border.all(

                      color: isDark ? const Color(0xff0284c7).withValues(alpha: 0.3) : const Color(0xffbae6fd),

                    ),

                  ),

                  child: Column(

                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [

                      Row(

                        children: const [

                          Icon(Icons.business_rounded,

                              size: 26, color: Color(0xff0284c7)),

                          SizedBox(width: 10),

                          Expanded(

                            child: Text(

                              'Office Location Proposal & Mapping',

                              style: TextStyle(

                                fontSize: 16,

                                fontWeight: FontWeight.bold,

                                color: Color(0xff0369a1),

                              ),

                            ),

                          ),

                        ],

                      ),

                      const SizedBox(height: 8),

                      const Text(

                        'Propose an official office, branch, or workplace location with live GPS coordinates. An administrator will review and officially assign the office to you.',

                        style: TextStyle(fontSize: 12.5, color: Color(0xff0c4a6e), height: 1.4),

                      ),

                    ],

                  ),

                ),

                const SizedBox(height: 16),



                TextFormField(

                  controller: name,

                  decoration: const InputDecoration(

                    labelText: 'Office / Branch Name',

                    hintText: 'e.g. Head Office, Branch, Depot, Warehouse',

                    border: OutlineInputBorder(),

                    prefixIcon: Icon(Icons.business_rounded),

                  ),

                  maxLength: 100,

                  validator: (v) =>

                      (v == null || v.trim().isEmpty) ? 'Please enter a name for this location' : null,

                ),

                const SizedBox(height: 6),



                TextFormField(

                  controller: address,

                  decoration: const InputDecoration(

                    labelText: 'Full Address / Landmark',

                    hintText: 'Street address, landmark, area and city',

                    border: OutlineInputBorder(),

                    prefixIcon: Icon(Icons.map_rounded),

                  ),

                  maxLines: 2,

                  maxLength: 500,

                  validator: (v) => (v == null || v.trim().isEmpty)

                      ? 'Please enter address or landmark'

                      : null,

                ),

                const SizedBox(height: 12),



                Row(

                  children: [

                    Expanded(

                      child: OutlinedButton.icon(

                        onPressed: busy ? null : capture,

                        icon: const Icon(Icons.my_location_rounded, size: 18),

                        label: const Text('Refresh GPS', style: TextStyle(fontSize: 12.5)),

                      ),

                    ),

                    const SizedBox(width: 10),

                    Expanded(

                      child: OutlinedButton.icon(

                        onPressed: busy ? null : takeSelfie,

                        icon: Icon(

                          photoBase64 != null

                              ? Icons.check_circle_rounded

                              : Icons.camera_alt_outlined,

                          size: 18,

                          color: photoBase64 != null ? Colors.green : null,

                        ),

                        label: Text(

                          photoBase64 != null

                              ? 'Photo Added ✓'

                              : 'Take Photo *',

                          style: TextStyle(

                            fontSize: 12.5,

                            fontWeight: FontWeight.w700,

                            color: photoBase64 != null ? Colors.green : const Color(0xff0284c7),

                          ),

                        ),

                      ),

                    ),

                  ],

                ),

                const SizedBox(height: 12),



                if (photoBase64 != null)

                  Container(

                    margin: const EdgeInsets.only(bottom: 12),

                    height: 120,

                    decoration: BoxDecoration(

                      borderRadius: BorderRadius.circular(10),

                      border: Border.all(color: Colors.green),

                    ),

                    clipBehavior: Clip.antiAlias,

                    child: Stack(

                      fit: StackFit.expand,

                      children: [

                        Image.memory(

                          base64Decode(photoBase64!),

                          fit: BoxFit.cover,

                        ),

                        Positioned(

                          right: 8,

                          top: 8,

                          child: InkWell(

                            onTap: () => setState(() => photoBase64 = null),

                            child: Container(

                              padding: const EdgeInsets.all(4),

                              decoration: const BoxDecoration(

                                color: Colors.black54,

                                shape: BoxShape.circle,

                              ),

                              child: const Icon(Icons.close,

                                  color: Colors.white, size: 16),

                            ),

                          ),

                        ),

                      ],

                    ),

                  ),



                if (point != null)

                  Container(

                    padding: const EdgeInsets.all(12),

                    decoration: BoxDecoration(

                      color: isDark ? const Color(0xff1e293b) : const Color(0xfff1f5f9),

                      borderRadius: BorderRadius.circular(10),

                      border: Border.all(color: isDark ? const Color(0xff334155) : const Color(0xffcbd5e1)),

                    ),

                    child: Row(

                      children: [

                        const Icon(Icons.check_circle_rounded,

                            color: Colors.green, size: 20),

                        const SizedBox(width: 8),

                        Expanded(

                          child: Text(

                            'GPS: ${(point!['latitude'] as num?)?.toStringAsFixed(6)}, ${(point!['longitude'] as num?)?.toStringAsFixed(6)} (Accuracy ±${((point!['accuracyMeters'] as num?) ?? 10.0).toStringAsFixed(1)}m)',

                            style: const TextStyle(

                              fontSize: 12,

                              fontWeight: FontWeight.w600,

                            ),

                          ),

                        ),

                      ],

                    ),

                  ),



                if (error != null)

                  Padding(

                    padding: const EdgeInsets.symmetric(vertical: 10),

                    child: Text(

                      error!,

                      style: const TextStyle(

                          color: Colors.red, fontWeight: FontWeight.bold),

                    ),

                  ),

                if (success != null)

                  Padding(

                    padding: const EdgeInsets.symmetric(vertical: 10),

                    child: Text(

                      success!,

                      style: const TextStyle(

                          color: Color(0xff16a34a),

                          fontWeight: FontWeight.bold),

                    ),

                  ),



                const SizedBox(height: 14),

                FilledButton.icon(

                  onPressed: busy ? null : submit,

                  icon: const Icon(Icons.send_rounded),

                  label: Text(busy

                      ? 'Submitting Location...'

                      : 'Submit Location for Approval'),

                  style: FilledButton.styleFrom(

                    backgroundColor: const Color(0xff0284c7),

                    padding: const EdgeInsets.symmetric(vertical: 14),

                  ),

                ),



                const SizedBox(height: 28),

                const Text(

                  'YOUR TAGGED LOCATIONS',

                  style: TextStyle(

                    fontSize: 12,

                    fontWeight: FontWeight.bold,

                    letterSpacing: 0.5,

                    color: Color(0xff64748b),

                  ),

                ),

                const SizedBox(height: 8),



                if (requests.isEmpty)

                  Container(

                    padding: const EdgeInsets.all(20),

                    alignment: Alignment.center,

                    child: const Text(

                      'No geo-tagged locations yet. Submit your office location proposal above.',

                      style: TextStyle(color: Color(0xff94a3b8), fontSize: 13),

                    ),

                  ),



                for (final row in requests)

                  Card(

                    margin: const EdgeInsets.only(bottom: 8),

                    child: ListTile(

                      leading: Icon(

                        row['tagType'] == 'HOME'

                            ? Icons.home_rounded

                            : row['tagType'] == 'GODOWN'

                                ? Icons.warehouse_rounded

                                : Icons.business_rounded,

                        color: row['tagType'] == 'HOME'

                            ? const Color(0xff3b82f6)

                            : row['tagType'] == 'GODOWN'

                                ? const Color(0xfff59e0b)

                                : const Color(0xff8b5cf6),

                      ),

                      title: Text(

                        '${row['name']}',

                        style: const TextStyle(fontWeight: FontWeight.bold),

                      ),

                      subtitle: Text(

                        '${row['address'] ?? ''}\nStatus: ${row['status']}${((row['note'] ?? row['reviewNote']) == null) ? '' : ' | Note: ${row['note'] ?? row['reviewNote']}'}',

                      ),

                      trailing: Chip(

                        label: Text(

                          '${row['status'] ?? 'Pending'}',

                          style: TextStyle(

                            fontSize: 11,

                            fontWeight: FontWeight.bold,

                            color: row['status'] == 'Approved'

                                ? const Color(0xff15803d)

                                : row['status'] == 'Pending'

                                    ? const Color(0xffb45309)

                                    : const Color(0xffb91c1c),

                          ),

                        ),

                        backgroundColor: row['status'] == 'Approved'

                            ? const Color(0xffdcfce7)

                            : row['status'] == 'Pending'

                                ? const Color(0xfffef3c7)

                                : const Color(0xfffee2e2),

                      ),

                    ),

                  ),

              ],

            ),

          ),

        ),

      ),

          ],

        ),

      ),

    );

  }

}

