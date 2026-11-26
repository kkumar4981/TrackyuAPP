import 'dart:convert';

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import 'address_cache.dart';

import 'api.dart';

import 'controller.dart';

import 'selfie.dart';

import 'visits.dart';
import 'workspace.dart' show jsonRows;



class RetailerGeoTagPage extends StatefulWidget {

  final TrackyuController controller;

  final bool isEmbedded;



  final Json? initialRetailer;

  const RetailerGeoTagPage({
    super.key,
    required this.controller,
    this.isEmbedded = false,
    this.initialRetailer,
  });



  @override

  State<RetailerGeoTagPage> createState() => _RetailerGeoTagPageState();

}



class _RetailerGeoTagPageState extends State<RetailerGeoTagPage> {

  final TextEditingController _searchController = TextEditingController();



  List<Json> _retailers = [];

  bool _loading = false;

  bool _locating = false;

  bool _saving = false;

  String? _error;

  String? _success;



  // Current GPS state

  double? _currentLat;

  double? _currentLng;

  double? _accuracy;

  String _currentAddress = 'Acquiring GPS location...';



  // Filter: 'all', 'pending', 'tagged'

  String _filter = 'all';



  // Selected retailer

  Json? _selectedRetailer;



  @override
  void initState() {
    super.initState();
    if (widget.initialRetailer != null) {
      _selectedRetailer = widget.initialRetailer;
      final name = widget.initialRetailer!['name']?.toString() ?? '';
      if (name.isNotEmpty) {
        _searchController.text = name;
      }
    }
    _initData();
  }

  Future<void> _startRegularVisit(Json retailer) async {
    final active = widget.controller.activeVisit;
    if (active != null) {
      Navigator.pop(context);
      return;
    }

    final res = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VisitForm(
          data: VisitsData(widget.controller),
          initialKind: 'Regular',
          initialRetailer: retailer,
        ),
      ),
    );
    if (res == true && mounted) {
      Navigator.pop(context, true);
    }
  }



  @override

  void dispose() {

    _searchController.dispose();

    super.dispose();

  }



  Future<void> _initData() async {

    await Future.wait([

      _captureCurrentLocation(),

      _loadRetailers(),

    ]);

  }



  Future<void> _captureCurrentLocation() async {

    if (_locating) return;

    setState(() {

      _locating = true;

      _error = null;

    });



    try {

      final loc = await widget.controller.locate();

      final lat = (loc['latitude'] as num?)?.toDouble();

      final lng = (loc['longitude'] as num?)?.toDouble();

      final acc = (loc['accuracyMeters'] as num?)?.toDouble();

      String addr = loc['textLocation']?.toString() ?? '';



      if (lat != null && lng != null) {

        if (addr.isEmpty || addr == '-' || addr.contains('not loaded')) {

          final rev = await TrackyuAddressCache.reverseGeocode(lat, lng);

          if (rev != null && rev.trim().isNotEmpty) {

            addr = rev.trim();

          }

        }

      }



      if (mounted) {

        setState(() {

          _currentLat = lat;

          _currentLng = lng;

          _accuracy = acc;

          _currentAddress = addr.isNotEmpty ? addr : 'GPS location captured';

        });

      }

    } catch (e) {

      if (mounted) {

        setState(() {

          _error = 'Unable to capture GPS location: $e';

        });

      }

    } finally {

      if (mounted) setState(() => _locating = false);

    }

  }



  Future<void> _loadRetailers({String query = ''}) async {

    if (_loading) return;

    setState(() {

      _loading = true;

      _error = null;

    });



    try {

      final q = query.trim();

      final encoded = Uri.encodeQueryComponent(q);

      final dynamic raw = await widget.controller.api.request(

        'MobileVisits/retailers?search=$encoded',

      );



      final list = jsonRows(raw);

      if (mounted) {

        setState(() {

          _retailers = list;

          // Retain selected retailer if still in list

          if (_selectedRetailer != null) {

            final selId = _selectedRetailer!['id'] ?? _selectedRetailer!['Id'];

            _selectedRetailer = list.firstWhere(

              (r) => (r['id'] ?? r['Id']) == selId,

              orElse: () => _selectedRetailer!,

            );

          }

        });

      }

    } catch (e) {

      if (mounted) {

        setState(() {

          _error = 'Failed to load retailers: $e';

        });

      }

    } finally {

      if (mounted) setState(() => _loading = false);

    }

  }



  bool _isTagged(Json r) {

    final lat = r['latitude'] ?? r['Latitude'] ?? r['xretailer'];

    final lng = r['longitude'] ?? r['Longitude'] ?? r['yretailer'];

    if (lat == null || lng == null) return false;

    final num? latNum = num.tryParse(lat.toString());

    final num? lngNum = num.tryParse(lng.toString());

    if (latNum == null || lngNum == null) return false;

    return latNum != 0 && lngNum != 0;

  }



  List<Json> get _filteredRetailers {

    final query = _searchController.text.trim().toLowerCase();

    return _retailers.where((r) {

      final id = (r['id'] ?? r['Id'] ?? '').toString().toLowerCase();

      final name = (r['name'] ?? r['Name'] ?? r['Aname'] ?? '').toString().toLowerCase();

      final place = (r['place'] ?? r['Place'] ?? '').toString().toLowerCase();



      final matchesQuery = query.isEmpty ||

          id.contains(query) ||

          name.contains(query) ||

          place.contains(query);



      if (!matchesQuery) return false;



      final tagged = _isTagged(r);

      if (_filter == 'pending') return !tagged;

      if (_filter == 'tagged') return tagged;

      return true;

    }).toList();

  }



    double _calculateDistanceMeters(double lat1, double lon1, double lat2, double lon2) {



    const earthRadius = 6371000.0;



    final dLat = (lat2 - lat1) * math.pi / 180.0;



    final dLon = (lon2 - lon1) * math.pi / 180.0;



    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +



        math.cos(lat1 * math.pi / 180.0) *



            math.cos(lat2 * math.pi / 180.0) *



            math.sin(dLon / 2) *



            math.sin(dLon / 2);



    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));



    return earthRadius * c;



  }







  Map<String, dynamic>? _checkProximityCollision(Json retailer, double lat, double lng) {



    const double thresholdMeters = 25.0;



    final currentId = (retailer['id'] ?? retailer['Id'] ?? retailer['retailer_id'] ?? '').toString();







    for (final other in _retailers) {



      final otherId = (other['id'] ?? other['Id'] ?? other['retailer_id'] ?? '').toString();



      if (otherId == currentId) continue;



      if (!_isTagged(other)) continue;







      final otherLat = num.tryParse((other['latitude'] ?? other['Latitude'] ?? other['xretailer']).toString())?.toDouble();



      final otherLng = num.tryParse((other['longitude'] ?? other['Longitude'] ?? other['yretailer']).toString())?.toDouble();



      if (otherLat == null || otherLng == null || (otherLat == 0 && otherLng == 0)) continue;







      final dist = _calculateDistanceMeters(lat, lng, otherLat, otherLng);



      if (dist <= thresholdMeters) {



        return {



          'id': otherId,



          'name': (other['name'] ?? other['Name'] ?? other['Aname'] ?? 'Shop').toString(),



          'distance': dist,



        };



      }



    }



    return null;



  }







  void _showConfirmation(Json retailer) {



    if (_currentLat == null || _currentLng == null) {



      ScaffoldMessenger.of(context).showSnackBar(



        const SnackBar(



          content: Text('Please wait for GPS location fix before tagging.'),



          backgroundColor: Colors.orange,



        ),



      );



      _captureCurrentLocation();



      return;



    }







    final collision = _checkProximityCollision(retailer, _currentLat!, _currentLng!);







    showDialog<String>(



      context: context,



      builder: (ctx) => RetailerGeoTagConfirmDialog(



        retailer: retailer,



        latitude: _currentLat!,



        longitude: _currentLng!,



        accuracy: _accuracy,



        address: _currentAddress,



        collision: collision,



      ),



    ).then((photo) {



      if (photo != null && photo.isNotEmpty) {



        _saveGeoTag(retailer, photo);



      }



    });



  }







  Future<void> _saveGeoTag(Json retailer, String photoBase64) async {



    if (_saving || _currentLat == null || _currentLng == null) return;







    final retailerId = (retailer['id'] ?? retailer['Id'] ?? retailer['retailer_id'] ?? '').toString();



    final name = (retailer['name'] ?? retailer['Name'] ?? retailer['Aname'] ?? 'Retailer').toString();







    setState(() {



      _saving = true;



      _error = null;



      _success = null;



    });







    try {



      HapticFeedback.mediumImpact();







      // Primary: RetailerMappings/geotag with mandatory selfie photo



      bool ok = false;



      try {



        await widget.controller.api.request(



          'RetailerMappings/geotag',



          body: {



            'retailerId': retailerId,



            'latitude': _currentLat,



            'longitude': _currentLng,



            'address': _currentAddress,



            'photo': photoBase64,



            'selfieUrl': 'data:image/jpeg;base64,$photoBase64',



          },



        );



        ok = true;



      } catch (_) {



        // Fallback: GeoTags/submit with watermark



        final nowStr = DateTime.now().toLocal().toString().split('.')[0];



        await widget.controller.api.request(



          'GeoTags/submit',



          body: {



            'tagType': 'CUSTOMER',



            'name': name,



            'address': _currentAddress,



            'latitude': _currentLat,



            'longitude': _currentLng,



            'accuracyMeters': _accuracy ?? 10.0,



            'selfieUrl': 'data:image/jpeg;base64,$photoBase64',



            'watermarkText': 'Retailer Geo-Tag: $name ($retailerId) | $_currentAddress | $_currentLat, $_currentLng | $nowStr',



          },



        );



        ok = true;



      }







      if (ok && mounted) {



        setState(() {



          retailer['latitude'] = _currentLat;



          retailer['longitude'] = _currentLng;



          retailer['Latitude'] = _currentLat;



          retailer['Longitude'] = _currentLng;



          retailer['xretailer'] = _currentLat;



          retailer['yretailer'] = _currentLng;



          retailer['address'] = _currentAddress;



          retailer['Address'] = _currentAddress;



          retailer['add_by_map'] = _currentAddress;







          _success = 'Geo-tag saved successfully for $name with verified photo!';



          _selectedRetailer = retailer;



        });







        showDialog<void>(








          context: context,








          builder: (ctx) => AlertDialog(








            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),








            title: Row(








              children: const [








                Icon(Icons.check_circle_rounded, color: Color(0xff10b981), size: 24),








                SizedBox(width: 8),








                Text('Geo-Tag Saved!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),








              ],








            ),








            content: Text(








              'Location for "$name" has been tagged successfully.\n\nWould you like to start a Regular Visit now?',








              style: const TextStyle(fontSize: 14, height: 1.4),








            ),








            actions: [








              TextButton(








                onPressed: () => Navigator.pop(ctx),








                child: const Text('Maybe Later'),








              ),








              ElevatedButton.icon(








                style: ElevatedButton.styleFrom(








                  backgroundColor: const Color(0xff16a34a),








                  foregroundColor: Colors.white,








                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),








                ),








                icon: const Icon(Icons.store_rounded, size: 16),








                label: const Text('Start Regular Visit'),








                onPressed: () {








                  Navigator.pop(ctx);








                  _startRegularVisit(retailer);








                },








              ),








            ],








          ),








        );








        ScaffoldMessenger.of(context).showSnackBar(








          SnackBar(



            content: Row(



              children: [



                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),



                const SizedBox(width: 8),



                Expanded(child: Text('Geo-tag & photo saved for $name!')),



              ],



            ),



            backgroundColor: const Color(0xff10b981),



            behavior: SnackBarBehavior.floating,



          ),



        );



      }



    } catch (e) {



      if (mounted) {



        setState(() {



          _error = 'Failed to save geo-tag: $e';



        });



        ScaffoldMessenger.of(context).showSnackBar(



          SnackBar(



            content: Text('Error: $e'),



            backgroundColor: Colors.redAccent,



          ),



        );



      }



    } finally {



      if (mounted) setState(() => _saving = false);



    }



  }







  @override

  Widget build(BuildContext context) {

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final content = _buildContent(isDark);



    if (widget.isEmbedded) {

      return content;

    }



    return Scaffold(

      appBar: AppBar(

        title: const Text('Retailer Geo-Tagging'),

        elevation: 0,

        actions: [

          IconButton(

            icon: _loading

                ? const SizedBox(

                    width: 18,

                    height: 18,

                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),

                  )

                : const Icon(Icons.refresh_rounded),

            tooltip: 'Reload Retailers',

            onPressed: _loading ? null : () => _loadRetailers(query: _searchController.text),

          ),

        ],

      ),

      body: content,

    );

  }



  Widget _buildContent(bool isDark) {

    final filtered = _filteredRetailers;



    final totalCount = _retailers.length;

    final taggedCount = _retailers.where(_isTagged).length;

    final pendingCount = totalCount - taggedCount;



    return Column(

      children: [

        // Current GPS banner card

        _buildGpsCard(isDark),



        if (_error != null)

          Container(

            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),

            padding: const EdgeInsets.all(10),

            decoration: BoxDecoration(

              color: Colors.red.withValues(alpha: 0.1),

              borderRadius: BorderRadius.circular(8),

              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),

            ),

            child: Row(

              children: [

                const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18),

                const SizedBox(width: 8),

                Expanded(child: Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.red))),

                IconButton(

                  icon: const Icon(Icons.close_rounded, size: 16),

                  onPressed: () => setState(() => _error = null),

                ),

              ],

            ),

          ),



        if (_success != null)

          Container(

            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),

            padding: const EdgeInsets.all(10),

            decoration: BoxDecoration(

              color: const Color(0xff10b981).withValues(alpha: 0.1),

              borderRadius: BorderRadius.circular(8),

              border: Border.all(color: const Color(0xff10b981).withValues(alpha: 0.3)),

            ),

            child: Row(

              children: [

                const Icon(Icons.check_circle_outline_rounded, color: Color(0xff10b981), size: 18),

                const SizedBox(width: 8),

                Expanded(child: Text(_success!, style: const TextStyle(fontSize: 12, color: Color(0xff10b981)))),

                IconButton(

                  icon: const Icon(Icons.close_rounded, size: 16),

                  onPressed: () => setState(() => _success = null),

                ),

              ],

            ),

          ),



        // Search & Filter header

        _buildSearchAndFilter(isDark, totalCount, pendingCount, taggedCount),



        // Retailers List

        Expanded(

          child: _loading && _retailers.isEmpty

              ? const Center(child: CircularProgressIndicator())

              : filtered.isEmpty

                  ? Center(

                      child: Padding(

                        padding: const EdgeInsets.all(24),

                        child: Column(

                          mainAxisSize: MainAxisSize.min,

                          children: [

                            Icon(Icons.store_mall_directory_outlined, size: 48, color: Colors.grey[400]),

                            const SizedBox(height: 12),

                            Text(

                              _searchController.text.isNotEmpty

                                  ? 'No retailers match "${_searchController.text}"'

                                  : 'No retailers found',

                              style: TextStyle(fontSize: 14, color: Colors.grey[600]),

                            ),

                          ],

                        ),

                      ),

                    )

                  : RefreshIndicator(

                      onRefresh: () => _loadRetailers(query: _searchController.text),

                      child: ListView.separated(

                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),

                        itemCount: filtered.length,

                        separatorBuilder: (_, __) => const SizedBox(height: 8),

                        itemBuilder: (ctx, i) {

                          final r = filtered[i];

                          final isSel = _selectedRetailer != null &&

                              ((r['id'] ?? r['Id']) == (_selectedRetailer!['id'] ?? _selectedRetailer!['Id']));

                          return _buildRetailerTile(r, isSel, isDark);

                        },

                      ),

                    ),

        ),



        // Bottom Action bar if selected

        if (_selectedRetailer != null) _buildSelectedActionBar(isDark),

      ],

    );

  }



  Widget _buildGpsCard(bool isDark) {

    final hasFix = _currentLat != null && _currentLng != null;

    final acc = _accuracy ?? 999;

    final Color accColor = acc <= 20

        ? const Color(0xff10b981)

        : (acc <= 50 ? const Color(0xfff59e0b) : const Color(0xffef4444));



    return Container(

      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),

      padding: const EdgeInsets.all(14),

      decoration: BoxDecoration(

        color: isDark ? const Color(0xff161e2e) : const Color(0xfff8fafc),

        borderRadius: BorderRadius.circular(14),

        border: Border.all(

          color: isDark ? const Color(0xff0284c7).withValues(alpha: 0.3) : const Color(0xffe2e8f0),

        ),

      ),

      child: Column(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          Row(

            children: [

              Container(

                width: 32,

                height: 32,

                decoration: BoxDecoration(

                  color: const Color(0xff0284c7).withValues(alpha: 0.12),

                  borderRadius: BorderRadius.circular(8),

                ),

                alignment: Alignment.center,

                child: const Icon(Icons.my_location_rounded, size: 18, color: Color(0xff0284c7)),

              ),

              const SizedBox(width: 10),

              Expanded(

                child: Column(

                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [

                    Row(

                      children: [

                        const Text(

                          'Current Location',

                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),

                        ),

                        const SizedBox(width: 8),

                        if (hasFix)

                          Container(

                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),

                            decoration: BoxDecoration(

                              color: accColor.withValues(alpha: 0.15),

                              borderRadius: BorderRadius.circular(6),

                            ),

                            child: Text(

                              '±${acc.toStringAsFixed(0)}m',

                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: accColor),

                            ),

                          ),

                      ],

                    ),

                    if (hasFix)

                      Text(

                        '${_currentLat!.toStringAsFixed(6)}, ${_currentLng!.toStringAsFixed(6)}',

                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),

                      ),

                  ],

                ),

              ),

              IconButton(

                icon: _locating

                    ? const SizedBox(

                        width: 16,

                        height: 16,

                        child: CircularProgressIndicator(strokeWidth: 2),

                      )

                    : const Icon(Icons.refresh_rounded, size: 20),

                tooltip: 'Refresh Location',

                onPressed: _locating ? null : _captureCurrentLocation,

              ),

            ],

          ),

          const SizedBox(height: 6),

          Text(

            _currentAddress,

            style: TextStyle(

              fontSize: 11.5,

              color: isDark ? Colors.grey[300] : const Color(0xff334155),

              height: 1.3,

            ),

            maxLines: 2,

            overflow: TextOverflow.ellipsis,

          ),

        ],

      ),

    );

  }



  Widget _buildSearchAndFilter(bool isDark, int total, int pending, int tagged) {

    return Padding(

      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),

      child: Column(

        children: [

          // Search box

          TextField(

            controller: _searchController,

            decoration: InputDecoration(

              hintText: 'Search retailer by name or code...',

              prefixIcon: const Icon(Icons.search_rounded, size: 20),

              suffixIcon: _searchController.text.isNotEmpty

                  ? IconButton(

                      icon: const Icon(Icons.clear_rounded, size: 18),

                      onPressed: () {

                        _searchController.clear();

                        _loadRetailers(query: '');

                      },

                    )

                  : null,

              filled: true,

              fillColor: isDark ? const Color(0xff161e2e) : const Color(0xfff1f5f9),

              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),

              border: OutlineInputBorder(

                borderRadius: BorderRadius.circular(12),

                borderSide: BorderSide.none,

              ),

            ),

            onChanged: (val) {

              setState(() {});

            },

            onSubmitted: (val) => _loadRetailers(query: val),

          ),

          const SizedBox(height: 8),



          // Filter chips

          SingleChildScrollView(

            scrollDirection: Axis.horizontal,

            child: Row(

              children: [

                _buildFilterChip('all', 'All ($total)'),

                const SizedBox(width: 8),

                _buildFilterChip('pending', 'Pending ($pending)', color: const Color(0xfff59e0b)),

                const SizedBox(width: 8),

                _buildFilterChip('tagged', 'Tagged ($tagged)', color: const Color(0xff10b981)),

              ],

            ),

          ),

        ],

      ),

    );

  }



  Widget _buildFilterChip(String value, String label, {Color? color}) {

    final isSel = _filter == value;

    final primary = color ?? const Color(0xff0284c7);



    return FilterChip(

      label: Text(

        label,

        style: TextStyle(

          fontSize: 11.5,

          fontWeight: isSel ? FontWeight.bold : FontWeight.w500,

          color: isSel ? Colors.white : (color ?? const Color(0xff475569)),

        ),

      ),

      selected: isSel,

      selectedColor: primary,

      backgroundColor: primary.withValues(alpha: 0.1),

      showCheckmark: false,

      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),

      shape: RoundedRectangleBorder(

        borderRadius: BorderRadius.circular(8),

        side: BorderSide(

          color: isSel ? primary : primary.withValues(alpha: 0.25),

        ),

      ),

      onSelected: (_) => setState(() => _filter = value),

    );

  }



  Widget _buildRetailerTile(Json r, bool isSel, bool isDark) {

    final name = r['name'] ?? r['Name'] ?? r['Aname'] ?? 'Unnamed Retailer';

    final id = r['id'] ?? r['Id'] ?? r['retailer_id'] ?? '';

    final place = r['place'] ?? r['Place'] ?? '';

    final address = r['address'] ?? r['Address'] ?? '';

    final tagged = _isTagged(r);



    final num? lat = num.tryParse((r['latitude'] ?? r['Latitude'] ?? r['xretailer'] ?? '').toString());

    final num? lng = num.tryParse((r['longitude'] ?? r['Longitude'] ?? r['yretailer'] ?? '').toString());



    return InkWell(

      borderRadius: BorderRadius.circular(12),

      onTap: () {

        setState(() {

          _selectedRetailer = isSel ? null : r;

        });

      },

      child: Container(

        padding: const EdgeInsets.all(12),

        decoration: BoxDecoration(

          color: isSel

              ? const Color(0xff0284c7).withValues(alpha: 0.08)

              : (isDark ? const Color(0xff161e2e) : Colors.white),

          borderRadius: BorderRadius.circular(12),

          border: Border.all(

            color: isSel

                ? const Color(0xff0284c7)

                : (isDark ? Colors.white12 : const Color(0xffe2e8f0)),

            width: isSel ? 1.5 : 1,

          ),

          boxShadow: [

            BoxShadow(

              color: Colors.black.withValues(alpha: 0.02),

              blurRadius: 4,

              offset: const Offset(0, 2),

            ),

          ],

        ),

        child: Row(

          crossAxisAlignment: CrossAxisAlignment.start,

          children: [

            // Store Avatar

            Container(

              width: 38,

              height: 38,

              decoration: BoxDecoration(

                color: (tagged ? const Color(0xff10b981) : const Color(0xfff59e0b)).withValues(alpha: 0.12),

                borderRadius: BorderRadius.circular(10),

              ),

              alignment: Alignment.center,

              child: Icon(

                tagged ? Icons.store_rounded : Icons.storefront_outlined,

                size: 20,

                color: tagged ? const Color(0xff10b981) : const Color(0xfff59e0b),

              ),

            ),

            const SizedBox(width: 12),



            // Info

            Expanded(

              child: Column(

                crossAxisAlignment: CrossAxisAlignment.start,

                children: [

                  Row(

                    children: [

                      Expanded(

                        child: Text(

                          name.toString(),

                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),

                          maxLines: 1,

                          overflow: TextOverflow.ellipsis,

                        ),

                      ),

                      if (id.toString().isNotEmpty)

                        Container(

                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),

                          decoration: BoxDecoration(

                            color: Colors.grey.withValues(alpha: 0.12),

                            borderRadius: BorderRadius.circular(4),

                          ),

                          child: Text(

                            '#$id',

                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xff64748b)),

                          ),

                        ),

                    ],

                  ),

                  const SizedBox(height: 2),



                  if (place.toString().isNotEmpty || address.toString().isNotEmpty)

                    Text(

                      place.toString().isNotEmpty ? place.toString() : address.toString(),

                      style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),

                      maxLines: 1,

                      overflow: TextOverflow.ellipsis,

                    ),



                  const SizedBox(height: 6),



                  // Tagged status badge

                  if (tagged && lat != null && lng != null)

                    Row(

                      children: [

                        const Icon(Icons.check_circle_rounded, size: 12, color: Color(0xff10b981)),

                        const SizedBox(width: 4),

                        Text(

                          'Tagged: ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',

                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xff10b981)),

                        ),

                      ],

                    )

                  else

                    Row(

                      children: const [

                        Icon(Icons.warning_amber_rounded, size: 12, color: Color(0xfff59e0b)),

                        SizedBox(width: 4),

                        Text(

                          'Location not tagged',

                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xfff59e0b)),

                        ),

                      ],

                    ),

                ],

              ),

            ),



            const SizedBox(width: 8),



            if (tagged)




              IconButton(




                icon: const Icon(Icons.store_rounded, color: Color(0xff6366f1), size: 22),




                tooltip: 'Start Regular Visit',




                onPressed: () => _startRegularVisit(r),




              ),




            // Tag button




            IconButton(




              icon: Icon(




                tagged ? Icons.edit_location_alt_rounded : Icons.add_location_alt_rounded,

                color: const Color(0xff0284c7),

                size: 22,

              ),

              tooltip: tagged ? 'Update Geo-Tag' : 'Tag Location',

              onPressed: () => _showConfirmation(r),

            ),

          ],

        ),

      ),

    );

  }



  Widget _buildSelectedActionBar(bool isDark) {

    final r = _selectedRetailer!;

    final name = r['name'] ?? r['Name'] ?? r['Aname'] ?? 'Retailer';

    final tagged = _isTagged(r);



    return Container(

      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),

      decoration: BoxDecoration(

        color: isDark ? const Color(0xff161e2e) : Colors.white,

        border: Border(top: BorderSide(color: isDark ? Colors.white12 : const Color(0xffe2e8f0))),

        boxShadow: [

          BoxShadow(

            color: Colors.black.withValues(alpha: 0.05),

            blurRadius: 8,

            offset: const Offset(0, -2),

          ),

        ],

      ),

      child: SafeArea(

        top: false,

        child: Row(

          children: [

            Expanded(

              child: Column(

                mainAxisSize: MainAxisSize.min,

                crossAxisAlignment: CrossAxisAlignment.start,

                children: [

                  Text(

                    name.toString(),

                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),

                    maxLines: 1,

                    overflow: TextOverflow.ellipsis,

                  ),

                  Text(

                    tagged ? 'Ready to update GPS coordinates' : 'Ready to tag store location',

                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),

                  ),

                ],

              ),

            ),

            const SizedBox(width: 12),

            if (tagged) ...[


              OutlinedButton.icon(


                style: OutlinedButton.styleFrom(


                  foregroundColor: const Color(0xff4338ca),


                  side: const BorderSide(color: Color(0xff6366f1)),


                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),


                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),


                ),


                icon: const Icon(Icons.store_rounded, size: 16),


                label: const Text('Regular Visit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),


                onPressed: () => _startRegularVisit(r),


              ),


              const SizedBox(width: 8),


            ],


            ElevatedButton.icon(


              style: ElevatedButton.styleFrom(

                backgroundColor: const Color(0xff0284c7),

                foregroundColor: Colors.white,

                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),

                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),

              ),

              icon: _saving

                  ? const SizedBox(

                      width: 16,

                      height: 16,

                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),

                    )

                  : Icon(tagged ? Icons.edit_location_alt_rounded : Icons.pin_drop_rounded, size: 18),

              label: Text(_saving ? 'Saving…' : (tagged ? 'Update Tag' : 'Save Geo-Tag')),

              onPressed: _saving ? null : () => _showConfirmation(r),

            ),

          ],

        ),

      ),

    );

  }

}









class RetailerGeoTagConfirmDialog extends StatefulWidget {



  final Json retailer;



  final double latitude;



  final double longitude;



  final double? accuracy;



  final String address;



  final Map<String, dynamic>? collision;







  const RetailerGeoTagConfirmDialog({



    super.key,



    required this.retailer,



    required this.latitude,



    required this.longitude,



    required this.accuracy,



    required this.address,



    this.collision,



  });







  @override



  State<RetailerGeoTagConfirmDialog> createState() => _RetailerGeoTagConfirmDialogState();



}







class _RetailerGeoTagConfirmDialogState extends State<RetailerGeoTagConfirmDialog> {



  String? _photoBase64;



  bool _takingPhoto = false;







  Future<void> _capturePhoto() async {



    if (_takingPhoto) return;



    setState(() => _takingPhoto = true);



    try {



      final photo = await captureVisitPhoto();



      if (photo != null && mounted) {



        setState(() {



          _photoBase64 = photo;



        });



      }



    } catch (e) {



      if (mounted) {



        ScaffoldMessenger.of(context).showSnackBar(



          SnackBar(content: Text('Camera error: $e')),



        );



      }



    } finally {



      if (mounted) setState(() => _takingPhoto = false);



    }



  }







  @override



  Widget build(BuildContext context) {



    final name = (widget.retailer['name'] ?? widget.retailer['Name'] ?? widget.retailer['Aname'] ?? 'Retailer').toString();



    final id = (widget.retailer['id'] ?? widget.retailer['Id'] ?? widget.retailer['retailer_id'] ?? '').toString();



    final isDark = Theme.of(context).brightness == Brightness.dark;







    return AlertDialog(



      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),



      title: Row(



        children: const [



          Icon(Icons.pin_drop_rounded, color: Color(0xff0284c7)),



          SizedBox(width: 8),



          Expanded(



            child: Text(



              'Verify & Confirm Geo-Tag',



              style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold),



            ),



          ),



        ],



      ),



      content: SingleChildScrollView(



        child: Column(



          mainAxisSize: MainAxisSize.min,



          crossAxisAlignment: CrossAxisAlignment.start,



          children: [



            // Proximity Collision Alert if any



            if (widget.collision != null) ...[



              Container(



                margin: const EdgeInsets.only(bottom: 12),



                padding: const EdgeInsets.all(12),



                decoration: BoxDecoration(



                  color: const Color(0xfffef2f2),



                  borderRadius: BorderRadius.circular(10),



                  border: Border.all(color: const Color(0xfffca5a5), width: 1.2),



                ),



                child: Row(



                  crossAxisAlignment: CrossAxisAlignment.start,



                  children: [



                    const Icon(Icons.warning_amber_rounded, color: Color(0xffdc2626), size: 22),



                    const SizedBox(width: 8),



                    Expanded(



                      child: Column(



                        crossAxisAlignment: CrossAxisAlignment.start,



                        children: [



                          const Text(



                            'Nearby Tagged Shop Alert',



                            style: TextStyle(



                              fontWeight: FontWeight.bold,



                              fontSize: 13,



                              color: Color(0xffb91c1c),



                            ),



                          ),



                          const SizedBox(height: 3),



                          Text(



                            'Another shop "${widget.collision!['name']}" (${widget.collision!['id']}) is already tagged within ${widget.collision!['distance'].toStringAsFixed(0)}m of this spot. Multiple shops at the exact same location spot are restricted.',



                            style: const TextStyle(fontSize: 11.5, color: Color(0xff7f1d1d), height: 1.3),



                          ),



                        ],



                      ),



                    ),



                  ],



                ),



              ),



            ],







            // Retailer Details Card



            Container(



              padding: const EdgeInsets.all(12),



              decoration: BoxDecoration(



                color: isDark ? const Color(0xff1e293b) : const Color(0xfff0f9ff),



                borderRadius: BorderRadius.circular(12),



                border: Border.all(color: isDark ? const Color(0xff334155) : const Color(0xffbae6fd)),



              ),



              child: Column(



                crossAxisAlignment: CrossAxisAlignment.start,



                children: [



                  Text(



                    name,



                    style: TextStyle(



                      fontWeight: FontWeight.bold,



                      fontSize: 14.5,



                      color: isDark ? Colors.white : const Color(0xff0369a1),



                    ),



                  ),



                  if (id.isNotEmpty) ...[



                    const SizedBox(height: 2),



                    Text('Party Code: $id', style: TextStyle(fontSize: 11.5, color: isDark ? const Color(0xff38bdf8) : const Color(0xff0284c7))),



                  ],



                  const Divider(height: 14),



                  Text(



                    'GPS: ${widget.latitude.toStringAsFixed(6)}, ${widget.longitude.toStringAsFixed(6)} (±${widget.accuracy?.toStringAsFixed(0) ?? '?'}m)',



                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? const Color(0xff94a3b8) : const Color(0xff0f172a)),



                  ),



                  const SizedBox(height: 4),



                  Text(



                    widget.address,



                    style: TextStyle(fontSize: 11, color: isDark ? const Color(0xff64748b) : Colors.grey[700]),



                    maxLines: 2,



                    overflow: TextOverflow.ellipsis,



                  ),



                ],



              ),



            ),



            const SizedBox(height: 14),







            // Mandatory Shop Selfie / Verification Photo



            Text(



              'Shop Verification Photo (Mandatory)*',



              style: TextStyle(



                fontSize: 12.5,



                fontWeight: FontWeight.bold,



                color: _photoBase64 == null ? const Color(0xffdc2626) : const Color(0xff059669),



              ),



            ),



            const SizedBox(height: 6),



            if (_photoBase64 == null) ...[



              InkWell(



                onTap: _takingPhoto ? null : _capturePhoto,



                borderRadius: BorderRadius.circular(12),



                child: Container(



                  width: double.infinity,



                  padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),



                  decoration: BoxDecoration(



                    color: const Color(0xfffef2f2),



                    borderRadius: BorderRadius.circular(12),



                    border: Border.all(color: const Color(0xfff87171), style: BorderStyle.solid, width: 1.2),



                  ),



                  child: Column(



                    children: [



                      const Icon(Icons.add_a_photo_rounded, size: 36, color: Color(0xffdc2626)),



                      const SizedBox(height: 6),



                      Text(



                        _takingPhoto ? 'Opening camera...' : 'Tap to Capture Shop Front Photo',



                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xffb91c1c)),



                      ),



                      const SizedBox(height: 2),



                      const Text(



                        'Selfie or front photo of shop is required',



                        style: TextStyle(fontSize: 11, color: Color(0xff991b1b)),



                      ),



                    ],



                  ),



                ),



              ),



            ] else ...[



              Container(



                padding: const EdgeInsets.all(10),



                decoration: BoxDecoration(



                  color: const Color(0xfff0fdf4),



                  borderRadius: BorderRadius.circular(12),



                  border: Border.all(color: const Color(0xff86efac)),



                ),



                child: Row(



                  children: [



                    ClipRRect(



                      borderRadius: BorderRadius.circular(8),



                      child: Image.memory(



                        base64Decode(_photoBase64!),



                        width: 55,



                        height: 55,



                        fit: BoxFit.cover,



                      ),



                    ),



                    const SizedBox(width: 12),



                    Expanded(



                      child: Column(



                        crossAxisAlignment: CrossAxisAlignment.start,



                        children: const [



                          Row(



                            children: [



                              Icon(Icons.check_circle_rounded, size: 16, color: Color(0xff16a34a)),



                              SizedBox(width: 4),



                              Text('Photo Verified', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xff15803d))),



                            ],



                          ),



                          SizedBox(height: 2),



                          Text('Ready to submit geo-tag', style: TextStyle(fontSize: 11, color: Color(0xff166534))),



                        ],



                      ),



                    ),



                    TextButton.icon(



                      onPressed: _takingPhoto ? null : _capturePhoto,



                      icon: const Icon(Icons.refresh_rounded, size: 14),



                      label: const Text('Retake', style: TextStyle(fontSize: 11)),



                    ),



                  ],



                ),



              ),



            ],



          ],



        ),



      ),



      actions: [



        TextButton(



          onPressed: () => Navigator.pop(context),



          child: const Text('Cancel'),



        ),



        FilledButton(



          style: FilledButton.styleFrom(



            backgroundColor: _photoBase64 != null ? const Color(0xff0284c7) : Colors.grey,



            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),



          ),



          onPressed: _photoBase64 == null



              ? () {



                  ScaffoldMessenger.of(context).showSnackBar(



                    const SnackBar(



                      content: Text('Shop verification photo is mandatory. Tap "Capture Shop Front Photo" to take a photo.'),



                      backgroundColor: Colors.redAccent,



                    ),



                  );



                }



              : () => Navigator.pop(context, _photoBase64),



          child: const Text('Confirm & Save Geo-Tag'),



        ),



      ],



    );



  }



}



