import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'address_cache.dart';
import 'api.dart';
import 'controller.dart';
import 'selfie.dart';

class ResidenceMappingSheet extends StatefulWidget {
  final TrackyuController controller;

  const ResidenceMappingSheet({super.key, required this.controller});

  static Future<Json?> show(BuildContext context, TrackyuController controller) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showModalBottomSheet<Json>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xff161e2e) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ResidenceMappingSheet(controller: controller),
    );
  }

  @override
  State<ResidenceMappingSheet> createState() => _ResidenceMappingSheetState();
}

class _ResidenceMappingSheetState extends State<ResidenceMappingSheet> {
  final _addressController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  double? _latitude;
  double? _longitude;
  double? _accuracy;
  String? _photoBase64;
  bool _locating = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _captureLocation();
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _captureLocation() async {
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
          _latitude = lat;
          _longitude = lng;
          _accuracy = acc;
          if (_addressController.text.trim().isEmpty && addr.isNotEmpty) {
            _addressController.text = addr;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Unable to capture GPS location: $e');
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _takePhoto() async {
    try {
      final photo = await captureVisitPhoto();
      if (photo != null && mounted) {
        setState(() {
          _photoBase64 = photo;
          _error = null;
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

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    if (_latitude == null || _longitude == null) {
      setState(() => _error = 'Valid GPS coordinates required. Please wait for GPS fix.');
      return;
    }
    if (_photoBase64 == null || _photoBase64!.trim().isEmpty) {
      setState(() => _error = 'Verification photo is mandatory. Please capture a photo before submitting.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      HapticFeedback.mediumImpact();
      final nowStr = DateTime.now().toLocal().toString().split('.')[0];
      final addr = _addressController.text.trim();
      final watermark =
          'Residence Location: $_latitude, $_longitude | $addr | $nowStr';

      await widget.controller.api.request(
        'GeoTags/submit',
        body: {
          'tagType': 'HOME',
          'name': 'Residence Location',
          'address': addr,
          'latitude': _latitude,
          'longitude': _longitude,
          'accuracyMeters': _accuracy ?? 10.0,
          if (_photoBase64 != null)
            'selfieUrl': 'data:image/jpeg;base64,$_photoBase64',
          'watermarkText': watermark,
        },
      );

      final result = {
        'tagType': 'HOME',
        'name': 'Residence Location',
        'address': addr,
        'latitude': _latitude,
        'longitude': _longitude,
        'status': 'Pending',
      };

      if (mounted) {
        Navigator.pop(context, result);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(child: Text('Residence location submitted for manager review!')),
              ],
            ),
            backgroundColor: Color(0xff10b981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Submission failed: $e');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasFix = _latitude != null && _longitude != null;
    final acc = _accuracy ?? 999;
    final Color accColor = acc <= 20
        ? const Color(0xff10b981)
        : (acc <= 50 ? const Color(0xfff59e0b) : const Color(0xffef4444));

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xff10b981).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.home_rounded, color: Color(0xff10b981), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Residence Location Mapping',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xff0f172a),
                          ),
                        ),
                        Text(
                          'Record your verified home base GPS location',
                          style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(height: 24),

              // GPS Status Card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xff0f172a) : const Color(0xfff8fafc),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? const Color(0xff10b981).withValues(alpha: 0.3) : const Color(0xffe2e8f0),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.my_location_rounded, size: 20, color: Color(0xff10b981)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                hasFix
                                    ? '${_latitude!.toStringAsFixed(6)}, ${_longitude!.toStringAsFixed(6)}'
                                    : 'Acquiring GPS fix...',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              if (hasFix) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: accColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '±${acc.toStringAsFixed(0)}m',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: accColor),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            hasFix ? 'Live device GPS coordinates' : 'Please ensure GPS is enabled',
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
                      tooltip: 'Refresh GPS',
                      onPressed: _locating ? null : _captureLocation,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Address Field
              TextFormField(
                controller: _addressController,
                maxLines: 3,
                maxLength: 300,
                decoration: InputDecoration(
                  labelText: 'Home / Residence Address',
                  hintText: 'Enter complete home address or landmark',
                  prefixIcon: const Icon(Icons.location_on_outlined, size: 20),
                  filled: true,
                  fillColor: isDark ? const Color(0xff0f172a) : const Color(0xfff8fafc),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (val) {
                  if (val == null || val.trim().length < 5) {
                    return 'Please enter a valid home address.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),

              // Photo capture row
              Row(
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _takePhoto,
                    icon: Icon(
                      _photoBase64 != null ? Icons.check_circle_rounded : Icons.camera_alt_outlined,
                      color: _photoBase64 != null ? const Color(0xff10b981) : const Color(0xff0284c7),
                      size: 18,
                    ),
                    label: Text(
                      _photoBase64 != null ? 'Photo Captured ✓' : 'Take Verification Photo *',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _photoBase64 != null ? const Color(0xff10b981) : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_photoBase64 != null)
                    TextButton(
                      onPressed: () => setState(() => _photoBase64 = null),
                      child: const Text('Retake', style: TextStyle(fontSize: 11)),
                    ),
                ],
              ),

              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.red)),
              ],

              const SizedBox(height: 18),

              // Submit button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xff10b981),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded, size: 18),
                  label: Text(
                    _submitting ? 'Submitting…' : 'Submit Residence Location',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
