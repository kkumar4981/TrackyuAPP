import 'gps_radar_loader.dart';
import 'profile_avatar.dart';

import 'dart:convert';

import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'trackyu_app_bar.dart';

import 'package:image_picker/image_picker.dart';

import 'controller.dart';

import 'error_logger.dart';

import 'residence_mapping_sheet.dart';

import 'office_location_request.dart';

import 'workspace.dart' show jsonRows;

import 'user_feedback.dart';

class ProfilePage extends StatefulWidget {

  final TrackyuController controller;

  const ProfilePage({super.key, required this.controller});

  @override

  State<ProfilePage> createState() => _ProfilePageState();

}

class _ProfilePageState extends State<ProfilePage> {

  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;

  late final TextEditingController _mobileController;

  late final TextEditingController _emailController;

  bool _savingProfile = false;

  bool _loadingProfile = true;

  Uint8List? _selectedPhotoBytes;

  String? _selectedPhotoBase64;

  Map<String, dynamic> _profileDetails = {};

  Map<String, dynamic>? _residenceTag;

  Map<String, dynamic>? _officeTag;

  @override

  void initState() {

    super.initState();

    final c = widget.controller;

    _nameController = TextEditingController(text: c.name);

    _mobileController = TextEditingController(

      text: c.user?['mobile']?.toString() ?? c.user?['MOBILE']?.toString() ?? '',

    );

    _emailController = TextEditingController(

      text: c.user?['email']?.toString() ?? c.user?['EMAIL']?.toString() ?? '',

    );

    _loadProfile();

  }

  @override

  void dispose() {

    _nameController.dispose();

    _mobileController.dispose();

    _emailController.dispose();

    super.dispose();

  }

  Future<void> _loadProfile() async {

    setState(() => _loadingProfile = true);

    try {

      final data = await widget.controller.fetchMyProfile();

      try {

        final geoRes = await widget.controller.api.request('GeoTags?mineOnly=true&tagType=HOME');

        if (geoRes is List && geoRes.isNotEmpty) {

          _residenceTag = Map<String, dynamic>.from(geoRes.first as Map);

        }

      } catch (_) {}

      try {

        final officeRes = await widget.controller.api.request('OfficeLocationRequests');

        final rows = jsonRows(officeRes);

        if (rows.isNotEmpty) {

          _officeTag = Map<String, dynamic>.from(rows.first);

        } else {

          final legacyRes = await widget.controller.api.request('GeoTags?mineOnly=true&tagType=OFFICE');

          if (legacyRes is List && legacyRes.isNotEmpty) {

            _officeTag = Map<String, dynamic>.from(legacyRes.first as Map);

          }

        }

      } catch (_) {}

      if (mounted) {

        setState(() {

          _profileDetails = data;

          if (data['NAME'] != null && data['NAME'].toString().isNotEmpty) {

            _nameController.text = data['NAME'].toString();

          }

          if (data['MOBILE'] != null && data['MOBILE'].toString().isNotEmpty) {

            _mobileController.text = data['MOBILE'].toString();

          }

          if (data['EMAIL'] != null && data['EMAIL'].toString().isNotEmpty) {

            _emailController.text = data['EMAIL'].toString();

          }

          _loadingProfile = false;

        });

      }

    } catch (_) {

      if (mounted) setState(() => _loadingProfile = false);

    }

  }

  String _formatDutyTime(dynamic start, dynamic end) {

    final s = start?.toString().trim() ?? '';

    final e = end?.toString().trim() ?? '';

    if (s.isEmpty && e.isEmpty) return 'Flexible / Standard Shift';

    if (s == '00:00' && (e == '23:59' || e == '24:00' || e == '00:00')) {

      return '24 Hours / Flexible Shift';

    }

    String toAmPm(String t) {

      if (t.isEmpty) return '';

      final parts = t.split(':');

      if (parts.length >= 2) {

        final h = int.tryParse(parts[0]);

        final m = int.tryParse(parts[1]);

        if (h != null && m != null) {

          final period = h >= 12 ? 'PM' : 'AM';

          final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);

          final minStr = m.toString().padLeft(2, '0');

          return '$hour12:$minStr $period';

        }

      }

      return t;

    }

    final startFmt = toAmPm(s);

    final endFmt = toAmPm(e);

    if (startFmt.isNotEmpty && endFmt.isNotEmpty) {

      return '$startFmt – $endFmt ($s - $e)';

    }

    return '$s – $e';

  }

  Future<void> _pickPhoto(ImageSource source) async {

    try {

      final picker = ImagePicker();

      final picked = await picker.pickImage(

        source: source,

        maxWidth: 720,

        maxHeight: 720,

        imageQuality: 82,

      );

      if (picked != null) {

        final bytes = await picked.readAsBytes();

        setState(() {

          _selectedPhotoBytes = bytes;

          _selectedPhotoBase64 = base64Encode(bytes);

        });

      }

    } catch (e, stack) {

      await ErrorLogger.record(e, stack, context: 'ProfilePage.pickPhoto');

      if (mounted) {

        ScaffoldMessenger.of(context).showSnackBar(

          const SnackBar(

            content: Text('Could not access image. Check camera/photo permissions.'),

            backgroundColor: Color(0xffb91c1c),

          ),

        );

      }

    }

  }

  void _showImageSourceDialog() {

    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(

      context: context,

      backgroundColor: isDark ? const Color(0xff1e293b) : Colors.white,

      shape: const RoundedRectangleBorder(

        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),

      ),

      builder: (ctx) => SafeArea(

        child: Padding(

          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),

          child: Column(

            mainAxisSize: MainAxisSize.min,

            children: [

              Text(

                'Change Profile Photo',

                style: TextStyle(

                  fontSize: 17,

                  fontWeight: FontWeight.bold,

                  color: isDark ? Colors.white : const Color(0xff0f172a),

                ),

              ),

              const SizedBox(height: 18),

              Row(

                mainAxisAlignment: MainAxisAlignment.spaceEvenly,

                children: [

                  _PhotoOptionButton(

                    icon: Icons.camera_alt_rounded,

                    label: 'Take Photo',

                    color: const Color(0xff0284c7),

                    onTap: () {

                      Navigator.pop(ctx);

                      _pickPhoto(ImageSource.camera);

                    },

                  ),

                  _PhotoOptionButton(

                    icon: Icons.photo_library_rounded,

                    label: 'From Gallery',

                    color: const Color(0xff059669),

                    onTap: () {

                      Navigator.pop(ctx);

                      _pickPhoto(ImageSource.gallery);

                    },

                  ),

                ],

              ),

              const SizedBox(height: 12),

            ],

          ),

        ),

      ),

    );

  }

  Future<void> _saveProfileChanges() async {

    if (!_formKey.currentState!.validate()) return;

    setState(() => _savingProfile = true);

    try {

      if (_selectedPhotoBytes != null) {

        await TrackyuAvatarCache.saveAvatarBytes(

          widget.controller.employeeId,

          _selectedPhotoBytes!,

        );

      }

      try {

        await widget.controller.updateProfile(

          name: _nameController.text.trim(),

          mobile: _mobileController.text.trim(),

          email: _emailController.text.trim(),

          photoBase64: _selectedPhotoBase64,

        );

      } catch (uploadErr) {

        if (_selectedPhotoBase64 != null) {

          await widget.controller.updateProfile(

            name: _nameController.text.trim(),

            mobile: _mobileController.text.trim(),

            email: _emailController.text.trim(),

          );

          if (mounted) {

            setState(() {

              _selectedPhotoBase64 = null;

              _savingProfile = false;

            });

            ScaffoldMessenger.of(context).showSnackBar(

              const SnackBar(

                content: Text('Profile updated! Photo is saved on device (server sync pending tonight\'s update).'),

                backgroundColor: Color(0xff0284c7),

                duration: Duration(seconds: 4),

              ),

            );

            return;

          }

        }

        rethrow;

      }

      if (mounted) {

        setState(() {

          _selectedPhotoBase64 = null; // uploaded

          _savingProfile = false;

        });

        ScaffoldMessenger.of(context).showSnackBar(

          const SnackBar(

            content: Text('Profile updated successfully!'),

            backgroundColor: Color(0xff059669),

            duration: Duration(seconds: 3),

          ),

        );

      }

    } catch (e, stack) {

      await ErrorLogger.record(e, stack, context: 'ProfilePage.saveProfile');

      if (mounted) {

        setState(() => _savingProfile = false);

        ScaffoldMessenger.of(context).showSnackBar(

          SnackBar(

            content: Text(e.toString().replaceAll('Exception: ', '')),

            backgroundColor: const Color(0xffb91c1c),

          ),

        );

      }

    }

  }

  @override

  Widget build(BuildContext context) {

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final c = widget.controller;

    final cardBg = isDark ? const Color(0xff1e293b) : Colors.white;

    final borderColor = isDark ? const Color(0xff334155) : const Color(0xffe2e8f0);

    final textPrimary = isDark ? Colors.white : const Color(0xff0f172a);

    final textSecondary = isDark ? const Color(0xff94a3b8) : const Color(0xff64748b);

    final inputBg = isDark ? const Color(0xff0f172a) : const Color(0xfff8fafc);

    return Scaffold(

      backgroundColor: isDark ? const Color(0xff0b1120) : const Color(0xfff1f5f9),

      appBar: trackyuAppBar(
        context: context,
        controller: widget.controller,
        title: 'My Profile',
      ),
      body: _loadingProfile
          ? Center(
              child: GpsRadarLoader(
                size: 80,
                label: 'Loading Profile Details...',
                sublabel: 'Fetching verified employee master record',
                
              ),
            )
          : Stack(
              children: [
                SingleChildScrollView(

              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),

              child: Center(

                child: ConstrainedBox(

                  constraints: const BoxConstraints(maxWidth: 540),

                  child: Column(

                    children: [

                      // --- Profile Avatar Card ---
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: isDark
                                ? [
                                    const Color(0xff1e293b),
                                    const Color(0xff0f172a),
                                  ]
                                : [
                                    Colors.white,
                                    const Color(0xfff8fafc),
                                  ],
                          ),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xff38bdf8).withValues(alpha: 0.22)
                                : const Color(0xff0284c7).withValues(alpha: 0.16),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: isDark
                                  ? Colors.black.withValues(alpha: 0.35)
                                  : const Color(0xff0284c7).withValues(alpha: 0.08),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Stack(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: const LinearGradient(
                                      colors: [Color(0xff0284c7), Color(0xff38bdf8)],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xff0284c7).withValues(alpha: 0.3),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: TrackyuAvatarWidget(
                                    controller: c,
                                    size: 100,
                                    isDark: isDark,
                                    previewBytes: _selectedPhotoBytes,
                                    onTap: _showImageSourceDialog,
                                  ),
                                ),
                                Positioned(
                                  bottom: 2,
                                  right: 2,
                                  child: InkWell(
                                    onTap: _showImageSourceDialog,
                                    borderRadius: BorderRadius.circular(20),
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [Color(0xff0284c7), Color(0xff0369a1)],
                                        ),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: isDark ? const Color(0xff0f172a) : Colors.white,
                                          width: 2.5,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xff0284c7).withValues(alpha: 0.4),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.camera_alt_rounded,
                                        size: 17,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              c.name,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                                color: textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              alignment: WrapAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xff0284c7).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: const Color(0xff0284c7).withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.badge_rounded, size: 13, color: Color(0xff0284c7)),
                                      const SizedBox(width: 4),
                                      Text(
                                        'ID: ${c.employeeId}',
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xff0284c7),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_profileDetails['DEPARTMENT'] != null &&
                                    _profileDetails['DEPARTMENT'].toString().isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xff059669).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: const Color(0xff059669).withValues(alpha: 0.35),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.work_outline_rounded, size: 13, color: Color(0xff059669)),
                                        const SizedBox(width: 4),
                                        Text(
                                          _profileDetails['DEPARTMENT'].toString().toUpperCase(),
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xff059669),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            if (_selectedPhotoBytes != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xfffef3c7),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xfffde68a)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.info_outline_rounded, size: 15, color: Color(0xff92400e)),
                                    SizedBox(width: 6),
                                    Text(
                                      'New photo selected. Tap "Save Profile Changes" below.',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: Color(0xff92400e),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      // --- Section 1: Basic Details (Editable) ---

                      Container(

                        padding: const EdgeInsets.all(20),

                        decoration: BoxDecoration(

                          color: cardBg,

                          borderRadius: BorderRadius.circular(16),

                          border: Border.all(color: borderColor),

                        ),

                        child: Form(

                          key: _formKey,

                          child: Column(

                            crossAxisAlignment: CrossAxisAlignment.start,

                            children: [

                              Row(

                                children: [

                                  const Icon(

                                    Icons.badge_rounded,

                                    size: 20,

                                    color: Color(0xff0284c7),

                                  ),

                                  const SizedBox(width: 8),

                                  Text(

                                    'Personal Details',

                                    style: TextStyle(

                                      fontSize: 16,

                                      fontWeight: FontWeight.bold,

                                      color: textPrimary,

                                    ),

                                  ),

                                ],

                              ),

                              const SizedBox(height: 16),

                              Text(

                                'Full name',

                                style: TextStyle(

                                  fontSize: 12,

                                  fontWeight: FontWeight.w600,

                                  color: textSecondary,

                                ),

                              ),

                              const SizedBox(height: 6),

                              TextFormField(

                                controller: _nameController,

                                style: TextStyle(color: textPrimary, fontSize: 14),

                                decoration: InputDecoration(

                                  hintText: 'Enter full name',

                                  filled: true,

                                  fillColor: inputBg,

                                  prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),

                                  border: OutlineInputBorder(

                                    borderRadius: BorderRadius.circular(10),

                                    borderSide: BorderSide(color: borderColor),

                                  ),

                                  enabledBorder: OutlineInputBorder(

                                    borderRadius: BorderRadius.circular(10),

                                    borderSide: BorderSide(color: borderColor),

                                  ),

                                ),

                                validator: (val) =>

                                    (val == null || val.trim().isEmpty)

                                        ? 'Name cannot be empty'

                                        : null,

                              ),

                              const SizedBox(height: 14),

                              Text(

                                'Mobile Number',

                                style: TextStyle(

                                  fontSize: 12,

                                  fontWeight: FontWeight.w600,

                                  color: textSecondary,

                                ),

                              ),

                              const SizedBox(height: 6),

                              TextFormField(

                                controller: _mobileController,

                                keyboardType: TextInputType.phone,

                                style: TextStyle(color: textPrimary, fontSize: 14),

                                decoration: InputDecoration(

                                  hintText: 'Enter 10-digit mobile number',

                                  filled: true,

                                  fillColor: inputBg,

                                  prefixIcon: const Icon(Icons.phone_outlined, size: 20),

                                  border: OutlineInputBorder(

                                    borderRadius: BorderRadius.circular(10),

                                    borderSide: BorderSide(color: borderColor),

                                  ),

                                  enabledBorder: OutlineInputBorder(

                                    borderRadius: BorderRadius.circular(10),

                                    borderSide: BorderSide(color: borderColor),

                                  ),

                                ),

                              ),

                              const SizedBox(height: 14),

                              Text(

                                'Email Address',

                                style: TextStyle(

                                  fontSize: 12,

                                  fontWeight: FontWeight.w600,

                                  color: textSecondary,

                                ),

                              ),

                              const SizedBox(height: 6),

                              TextFormField(

                                controller: _emailController,

                                keyboardType: TextInputType.emailAddress,

                                style: TextStyle(color: textPrimary, fontSize: 14),

                                decoration: InputDecoration(

                                  hintText: 'Enter email address',

                                  filled: true,

                                  fillColor: inputBg,

                                  prefixIcon: const Icon(Icons.email_outlined, size: 20),

                                  border: OutlineInputBorder(

                                    borderRadius: BorderRadius.circular(10),

                                    borderSide: BorderSide(color: borderColor),

                                  ),

                                  enabledBorder: OutlineInputBorder(

                                    borderRadius: BorderRadius.circular(10),

                                    borderSide: BorderSide(color: borderColor),

                                  ),

                                ),

                              ),

                              const SizedBox(height: 14),

                              _ReadOnlyInfoTile(

                                label: 'Branch / Company',

                                value: (_profileDetails['BRANCH'] != null && _profileDetails['BRANCH'].toString().trim().isNotEmpty)

                                    ? _profileDetails['BRANCH'].toString().trim()

                                    : (c.user?['company']?.toString() ?? c.user?['COMPANY']?.toString() ?? 'Oyu Infotech'),

                                icon: Icons.business_rounded,

                                

                              ),

                              if (_profileDetails['SUPERVISOR'] != null &&

                                  _profileDetails['SUPERVISOR'].toString().isNotEmpty) ...[

                                const SizedBox(height: 10),

                                _ReadOnlyInfoTile(

                                  label: 'Reporting Supervisor',

                                  value: _profileDetails['SUPERVISOR'].toString(),

                                  icon: Icons.supervisor_account_rounded,

                                  

                                ),

                              ],

                              const SizedBox(height: 20),
                              Container(
                                width: double.infinity,
                                height: 50,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xff0284c7), Color(0xff0369a1)],
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xff0284c7).withValues(alpha: 0.35),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: _savingProfile ? null : _saveProfileChanges,
                                    child: Center(
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.check_circle_rounded, size: 20, color: Colors.white),
                                          const SizedBox(width: 8),
                                          const Text(
                                            'Save Profile Changes',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],

                          ),

                        ),

                      ),

                      const SizedBox(height: 18),

                      const SizedBox(height: 18),

                      // --- Section: Official Duty & Shift Timings (From Master) ---

                      Container(

                        padding: const EdgeInsets.all(20),

                        decoration: BoxDecoration(

                          color: cardBg,

                          borderRadius: BorderRadius.circular(16),

                          border: Border.all(color: borderColor),

                        ),

                        child: Column(

                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [

                            Row(

                              children: [

                                Container(

                                  padding: const EdgeInsets.all(7),

                                  decoration: BoxDecoration(

                                    color: const Color(0xff10b981).withValues(alpha: 0.12),

                                    borderRadius: BorderRadius.circular(8),

                                  ),

                                  child: const Icon(

                                    Icons.access_time_filled_rounded,

                                    size: 19,

                                    color: Color(0xff10b981),

                                  ),

                                ),

                                const SizedBox(width: 9),

                                Text(

                                  'Work & Shift Schedule',

                                  style: TextStyle(

                                    fontSize: 16,

                                    fontWeight: FontWeight.bold,

                                    color: textPrimary,

                                  ),

                                ),

                              ],

                            ),

                            const SizedBox(height: 14),

                            _ReadOnlyInfoTile(

                              label: 'Official Work / Shift Hours',

                              value: _formatDutyTime(

                                _profileDetails['TIME'],

                                _profileDetails['DETIME'],

                              ),

                              icon: Icons.schedule_rounded,

                              

                            ),

                            const SizedBox(height: 10),

                            _ReadOnlyInfoTile(

                              label: 'Weekly Off Day',

                              value: (_profileDetails['WEEK_OFF'] != null &&

                                      _profileDetails['WEEK_OFF'].toString().trim().isNotEmpty)

                                  ? _profileDetails['WEEK_OFF'].toString().trim()

                                  : 'Not specified (Sunday)',

                              icon: Icons.event_busy_rounded,

                              

                            ),

                            if (_profileDetails['DESIGNATION'] != null &&

                                _profileDetails['DESIGNATION'].toString().trim().isNotEmpty) ...[

                              const SizedBox(height: 10),

                              _ReadOnlyInfoTile(

                                label: 'Designation / Role',

                                value: _profileDetails['DESIGNATION'].toString().trim(),

                                icon: Icons.badge_outlined,

                                

                              ),

                            ],

                            if (_profileDetails['P_LOCATION'] != null &&

                                _profileDetails['P_LOCATION'].toString().trim().isNotEmpty) ...[

                              const SizedBox(height: 10),

                              _ReadOnlyInfoTile(

                                label: 'Base Location / Zone',

                                value: _profileDetails['P_LOCATION'].toString().trim(),

                                icon: Icons.location_on_outlined,

                                

                              ),

                            ],

                          ],

                        ),

                      ),

                      const SizedBox(height: 18),

                      // --- Residence / Home Location Mapping Card ---

                      Container(

                        padding: const EdgeInsets.all(16),

                        decoration: BoxDecoration(

                          color: cardBg,

                          borderRadius: BorderRadius.circular(16),

                          border: Border.all(color: borderColor),

                        ),

                        child: Column(

                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [

                            Row(

                              children: [

                                Container(

                                  padding: const EdgeInsets.all(8),

                                  decoration: BoxDecoration(

                                    color: const Color(0xff10b981).withValues(alpha: 0.12),

                                    borderRadius: BorderRadius.circular(8),

                                  ),

                                  child: const Icon(

                                    Icons.home_rounded,

                                    color: Color(0xff10b981),

                                    size: 20,

                                  ),

                                ),

                                const SizedBox(width: 12),

                                Expanded(

                                  child: Column(

                                    crossAxisAlignment: CrossAxisAlignment.start,

                                    children: [

                                      Text(

                                        'Residence Location',

                                        style: TextStyle(

                                          fontSize: 14,

                                          fontWeight: FontWeight.bold,

                                          color: textPrimary,

                                        ),

                                      ),

                                      Text(

                                        'Home base GPS mapping & verification',

                                        style: TextStyle(

                                          fontSize: 11,

                                          color: textSecondary,

                                        ),

                                      ),

                                    ],

                                  ),

                                ),

                                FilledButton.tonal(

                                  style: FilledButton.styleFrom(

                                    backgroundColor: const Color(0xff10b981).withValues(alpha: 0.15),

                                    foregroundColor: const Color(0xff10b981),

                                    shape: RoundedRectangleBorder(

                                      borderRadius: BorderRadius.circular(8),

                                    ),

                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),

                                  ),

                                  onPressed: () async {

                                    final res = await ResidenceMappingSheet.show(context, widget.controller);

                                    if (res != null && mounted) {

                                      setState(() {

                                        _residenceTag = res;

                                      });

                                    }

                                  },

                                  child: Text(

                                    _residenceTag != null ? 'Update' : 'Map Home',

                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),

                                  ),

                                ),

                              ],

                            ),

                            const SizedBox(height: 12),

                            if (_residenceTag != null) ...[

                              Container(

                                padding: const EdgeInsets.all(10),

                                decoration: BoxDecoration(

                                  color: isDark ? const Color(0xff0f172a) : const Color(0xfff0fdf4),

                                  borderRadius: BorderRadius.circular(8),

                                  border: Border.all(

                                    color: isDark ? Colors.white12 : const Color(0xffbbf7d0),

                                  ),

                                ),

                                child: Row(

                                  children: [

                                    const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xff10b981)),

                                    const SizedBox(width: 8),

                                    Expanded(

                                      child: Column(

                                        crossAxisAlignment: CrossAxisAlignment.start,

                                        children: [

                                          Text(

                                            _residenceTag!['address']?.toString() ?? 'Home Location Tagged',

                                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: textPrimary),

                                            maxLines: 2,

                                            overflow: TextOverflow.ellipsis,

                                          ),

                                          if (_residenceTag!['latitude'] != null && _residenceTag!['longitude'] != null)

                                            Text(

                                              'GPS: ${_residenceTag!['latitude']}, ${_residenceTag!['longitude']} • Status: ${_residenceTag!['status'] ?? 'Approved'}',

                                              style: TextStyle(fontSize: 10.5, color: textSecondary),

                                            ),

                                        ],

                                      ),

                                    ),

                                  ],

                                ),

                              ),

                            ] else ...[

                              Container(

                                padding: const EdgeInsets.all(10),

                                decoration: BoxDecoration(

                                  color: isDark ? const Color(0xff0f172a) : const Color(0xfff8fafc),

                                  borderRadius: BorderRadius.circular(8),

                                  border: Border.all(color: borderColor),

                                ),

                                child: Row(

                                  children: [

                                    const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xfff59e0b)),

                                    const SizedBox(width: 8),

                                    Expanded(

                                      child: Text(

                                        'Residence location not yet mapped. Tap "Map Home" to record your official home coordinates.',

                                        style: TextStyle(fontSize: 11.5, color: textSecondary),

                                      ),

                                    ),

                                  ],

                                ),

                              ),

                            ],

                          ],

                        ),

                      ),

                      const SizedBox(height: 18),

                      // --- Office Location Mapping Card ---

                      Container(

                        padding: const EdgeInsets.all(16),

                        decoration: BoxDecoration(

                          color: cardBg,

                          borderRadius: BorderRadius.circular(16),

                          border: Border.all(color: borderColor),

                        ),

                        child: Column(

                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [

                            Row(

                              children: [

                                Container(

                                  padding: const EdgeInsets.all(8),

                                  decoration: BoxDecoration(

                                    color: const Color(0xff0d9488).withValues(alpha: 0.12),

                                    borderRadius: BorderRadius.circular(8),

                                  ),

                                  child: const Icon(

                                    Icons.business_rounded,

                                    color: Color(0xff0d9488),

                                    size: 20,

                                  ),

                                ),

                                const SizedBox(width: 12),

                                Expanded(

                                  child: Column(

                                    crossAxisAlignment: CrossAxisAlignment.start,

                                    children: [

                                      Text(

                                        'Office Location Mapping',

                                        style: TextStyle(

                                          fontSize: 14,

                                          fontWeight: FontWeight.bold,

                                          color: textPrimary,

                                        ),

                                      ),

                                      Text(

                                        'Official workplace GPS mapping & verification',

                                        style: TextStyle(

                                          fontSize: 11,

                                          color: textSecondary,

                                        ),

                                      ),

                                    ],

                                  ),

                                ),

                                FilledButton.tonal(

                                  style: FilledButton.styleFrom(

                                    backgroundColor: const Color(0xff0d9488).withValues(alpha: 0.15),

                                    foregroundColor: const Color(0xff0d9488),

                                    shape: RoundedRectangleBorder(

                                      borderRadius: BorderRadius.circular(8),

                                    ),

                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),

                                  ),

                                  onPressed: () async {

                                    await Navigator.push(

                                      context,

                                      MaterialPageRoute<void>(

                                        builder: (_) => OfficeLocationRequestPage(

                                          controller: widget.controller,

                                          initialTab: 1,

                                        ),

                                      ),

                                    );

                                    if (mounted) _loadProfile();

                                  },

                                  child: Text(

                                    _officeTag != null ? 'Update' : 'Map Office',

                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),

                                  ),

                                ),

                              ],

                            ),

                            const SizedBox(height: 12),

                            if (_officeTag != null) ...[

                              Container(

                                padding: const EdgeInsets.all(10),

                                decoration: BoxDecoration(

                                  color: isDark ? const Color(0xff0f172a) : const Color(0xfff0fdfa),

                                  borderRadius: BorderRadius.circular(8),

                                  border: Border.all(

                                    color: isDark ? Colors.white12 : const Color(0xff99f6e4),

                                  ),

                                ),

                                child: Row(

                                  children: [

                                    const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xff0d9488)),

                                    const SizedBox(width: 8),

                                    Expanded(

                                      child: Column(

                                        crossAxisAlignment: CrossAxisAlignment.start,

                                        children: [

                                          Text(

                                            _officeTag!['officeName']?.toString() ??

                                                _officeTag!['name']?.toString() ??

                                                _officeTag!['label']?.toString() ??

                                                'Office Location Tagged',

                                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: textPrimary),

                                            maxLines: 2,

                                            overflow: TextOverflow.ellipsis,

                                          ),

                                          if (_officeTag!['address'] != null && _officeTag!['address'].toString().trim().isNotEmpty)

                                            Text(

                                              _officeTag!['address'].toString().trim(),

                                              style: TextStyle(fontSize: 11, color: textSecondary),

                                              maxLines: 2,

                                              overflow: TextOverflow.ellipsis,

                                            ),

                                          if (_officeTag!['latitude'] != null && _officeTag!['longitude'] != null)

                                            Text(

                                              'GPS: ${_officeTag!['latitude']}, ${_officeTag!['longitude']} • Status: ${_officeTag!['status'] ?? 'Approved'}',

                                              style: TextStyle(fontSize: 10.5, color: textSecondary),

                                            ),

                                        ],

                                      ),

                                    ),

                                  ],

                                ),

                              ),

                            ] else ...[

                              Container(

                                padding: const EdgeInsets.all(10),

                                decoration: BoxDecoration(

                                  color: isDark ? const Color(0xff0f172a) : const Color(0xfff8fafc),

                                  borderRadius: BorderRadius.circular(8),

                                  border: Border.all(color: borderColor),

                                ),

                                child: Row(

                                  children: [

                                    const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xff0d9488)),

                                    const SizedBox(width: 8),

                                    Expanded(

                                      child: Text(

                                        'Office location not yet mapped. Tap "Map Office" to propose or record your workplace coordinates.',

                                        style: TextStyle(fontSize: 11.5, color: textSecondary),

                                      ),

                                    ),

                                  ],

                                ),

                              ),

                            ],

                          ],

                        ),

                      ),

                      const SizedBox(height: 18),

                      // Shortcut Card to Change Password

                      Container(

                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),

                        decoration: BoxDecoration(

                          color: cardBg,

                          borderRadius: BorderRadius.circular(14),

                          border: Border.all(color: borderColor),

                        ),

                        child: Row(

                          children: [

                            Container(

                              padding: const EdgeInsets.all(8),

                              decoration: BoxDecoration(

                                color: const Color(0xffd97706).withValues(alpha: 0.12),

                                borderRadius: BorderRadius.circular(8),

                              ),

                              child: const Icon(

                                Icons.lock_reset_rounded,

                                color: Color(0xffd97706),

                                size: 20,

                              ),

                            ),

                            const SizedBox(width: 12),

                            Expanded(

                              child: Column(

                                crossAxisAlignment: CrossAxisAlignment.start,

                                children: [

                                  Text(

                                    'Account Security & Password',

                                    style: TextStyle(

                                      fontSize: 13.5,

                                      fontWeight: FontWeight.w600,

                                      color: textPrimary,

                                    ),

                                  ),

                                  const SizedBox(height: 2),

                                  Text(

                                    'Update your login password',

                                    style: TextStyle(

                                      fontSize: 11,

                                      color: textSecondary,

                                    ),

                                  ),

                                ],

                              ),

                            ),

                            FilledButton.tonal(

                              style: FilledButton.styleFrom(

                                backgroundColor: const Color(0xffd97706).withValues(alpha: 0.15),

                                foregroundColor: const Color(0xffd97706),

                                shape: RoundedRectangleBorder(

                                  borderRadius: BorderRadius.circular(8),

                                ),

                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),

                              ),

                              onPressed: () {

                                Navigator.push(

                                  context,

                                  MaterialPageRoute<void>(

                                    builder: (_) => ChangePasswordPage(controller: widget.controller),

                                  ),

                                );

                              },

                              child: const Text('Change', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),

                            ),

                          ],

                        ),

                      ),

                      const SizedBox(height: 20),
                      // Dedicated Account Session & Sign Out Section
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xffdc2626).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.account_circle_outlined, size: 20, color: Color(0xffdc2626)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Account Session',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: textPrimary,
                                        ),
                                      ),
                                      Text(
                                        'Signed in on this device as ${widget.controller.employeeId}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xffdc2626),
                                  side: const BorderSide(color: Color(0xfffca5a5), width: 1.2),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                      title: const Row(
                                        children: [
                                          Icon(Icons.logout_rounded, color: Color(0xffdc2626)),
                                          SizedBox(width: 8),
                                          Expanded(child: Text("Sign Out of Account?")),
                                        ],
                                      ),
                                      content: Text(
                                        widget.controller.onDuty
                                            ? "Your work session is currently ACTIVE. Signing out will automatically record Work Out and complete your shift.\n\nAre you sure you want to sign out?"
                                            : "Are you sure you want to sign out of this account on this device?",
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx, false),
                                          child: const Text("Cancel"),
                                        ),
                                        FilledButton(
                                          style: FilledButton.styleFrom(backgroundColor: const Color(0xffdc2626)),
                                          onPressed: () => Navigator.pop(ctx, true),
                                          child: const Text("Confirm Sign Out"),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    await widget.controller.signOut(autoPunchOut: true);
                                    if (context.mounted) {
                                      Navigator.of(context).popUntil((route) => route.isFirst);
                                    }
                                  }
                                },
                                icon: const Icon(Icons.logout_rounded, size: 17),
                                label: const Text(
                                  'Sign Out of Account',
                                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 30),

                    ],

                  ),

                ),

              ),

            ),
            if (_savingProfile)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.55),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xff1e293b) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isDark ? const Color(0xff334155) : const Color(0xffe2e8f0),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: GpsRadarLoader(
                        size: 72,
                        label: 'Saving Profile Changes...',
                        sublabel: 'Updating employee master record',
                        
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
    );

  }

}

class ChangePasswordPage extends StatefulWidget {

  final TrackyuController controller;

  const ChangePasswordPage({super.key, required this.controller});

  @override

  State<ChangePasswordPage> createState() => _ChangePasswordPageState();

}

class _ChangePasswordPageState extends State<ChangePasswordPage> {

  final _passwordFormKey = GlobalKey<FormState>();

  final _oldPasswordController = TextEditingController();

  final _newPasswordController = TextEditingController();

  final _confirmPasswordController = TextEditingController();

  bool _obscureOld = true;

  bool _obscureNew = true;

  bool _obscureConfirm = true;

  bool _changingPassword = false;

  @override

  void dispose() {

    _oldPasswordController.dispose();

    _newPasswordController.dispose();

    _confirmPasswordController.dispose();

    super.dispose();

  }

  Future<void> _updatePassword() async {

    if (!_passwordFormKey.currentState!.validate()) return;

    final oldPass = _oldPasswordController.text.trim();

    final newPass = _newPasswordController.text.trim();

    final confirmPass = _confirmPasswordController.text.trim();

    if (oldPass.isEmpty) {

      ScaffoldMessenger.of(context).showSnackBar(

        const SnackBar(

          content: Text('Please enter current password.'),

          backgroundColor: Color(0xffb91c1c),

        ),

      );

      return;

    }

    if (newPass.isEmpty) {

      ScaffoldMessenger.of(context).showSnackBar(

        const SnackBar(

          content: Text('Please enter new password.'),

          backgroundColor: Color(0xffb91c1c),

        ),

      );

      return;

    }

    if (newPass.length < 4) {

      ScaffoldMessenger.of(context).showSnackBar(

        const SnackBar(

          content: Text('Password must be at least 4 characters long.'),

          backgroundColor: Color(0xffb91c1c),

        ),

      );

      return;

    }

    if (newPass == oldPass) {

      ScaffoldMessenger.of(context).showSnackBar(

        const SnackBar(

          content: Text('New password must be different from current password.'),

          backgroundColor: Color(0xffb91c1c),

        ),

      );

      return;

    }

    if (newPass != confirmPass) {

      ScaffoldMessenger.of(context).showSnackBar(

        const SnackBar(

          content: Text('New password and confirm password do not match.'),

          backgroundColor: Color(0xffb91c1c),

        ),

      );

      return;

    }

    setState(() => _changingPassword = true);

    try {

      await widget.controller.changePassword(

        oldPassword: oldPass,

        newPassword: newPass,

      );

      if (mounted) {

        setState(() {

          _changingPassword = false;

          _oldPasswordController.clear();

          _newPasswordController.clear();

          _confirmPasswordController.clear();

        });

        ScaffoldMessenger.of(context).showSnackBar(

          const SnackBar(

            content: Text('Password updated successfully!'),

            backgroundColor: Color(0xff059669),

            duration: Duration(seconds: 4),

          ),

        );

        Future.delayed(const Duration(milliseconds: 1000), () {

          if (mounted) Navigator.pop(context);

        });

      }

    } catch (e) {

      if (mounted) {

        setState(() => _changingPassword = false);

        final friendlyMsg = userFriendlyErrorMessage(e);

        ScaffoldMessenger.of(context).showSnackBar(

          SnackBar(

            content: Text(friendlyMsg),

            backgroundColor: const Color(0xffb91c1c),

            duration: const Duration(seconds: 4),

          ),

        );

      }

    }

  }

    @override

  Widget build(BuildContext context) {

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final cardBg = isDark ? const Color(0xff1e293b) : Colors.white;

    final borderColor = isDark ? const Color(0xff334155) : const Color(0xffe2e8f0);

    final textPrimary = isDark ? Colors.white : const Color(0xff0f172a);

    final textSecondary = isDark ? const Color(0xff94a3b8) : const Color(0xff64748b);

    final inputBg = isDark ? const Color(0xff0f172a) : Colors.white;

    return Scaffold(

      backgroundColor: isDark ? const Color(0xff0b1120) : const Color(0xfff8fafc),

      appBar: AppBar(

        title: const Text('Change Password', style: TextStyle(fontWeight: FontWeight.bold)),

        elevation: 0,

        backgroundColor: isDark ? const Color(0xff0f172a) : Colors.white,

      ),

      body: SingleChildScrollView(

        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),

        child: Center(

          child: ConstrainedBox(

            constraints: const BoxConstraints(maxWidth: 540),

            child: Column(

              crossAxisAlignment: CrossAxisAlignment.start,

              children: [

                // Info Banner (Peach Header Card)

                Container(

                  padding: const EdgeInsets.all(16),

                  decoration: BoxDecoration(

                    color: isDark ? const Color(0xff451a03).withValues(alpha: 0.3) : const Color(0xfffff7ed),

                    borderRadius: BorderRadius.circular(16),

                    border: Border.all(color: isDark ? const Color(0xff78350f) : const Color(0xfffed7aa)),

                  ),

                  child: Row(

                    children: [

                      Container(

                        padding: const EdgeInsets.all(10),

                        decoration: BoxDecoration(

                          color: isDark ? const Color(0xff78350f).withValues(alpha: 0.5) : const Color(0xffffedd5),

                          borderRadius: BorderRadius.circular(12),

                          border: Border.all(

                            color: isDark ? const Color(0xff9a3412) : const Color(0xfffed7aa),

                          ),

                        ),

                        child: const Icon(

                          Icons.shield_outlined,

                          color: Color(0xffc2410c),

                          size: 24,

                        ),

                      ),

                      const SizedBox(width: 14),

                      Expanded(

                        child: Column(

                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [

                            Text(

                              'Account security',

                              style: TextStyle(

                                fontSize: 15,

                                fontWeight: FontWeight.bold,

                                color: isDark ? Colors.white : const Color(0xff0f172a),

                              ),

                            ),

                            const SizedBox(height: 3),

                            Text(

                              'Use at least 4 characters for your new password.',

                              style: TextStyle(

                                fontSize: 12.5,

                                color: isDark ? const Color(0xffcbd5e1) : const Color(0xff64748b),

                                height: 1.3,

                              ),

                            ),

                          ],

                        ),

                      ),

                    ],

                  ),

                ),

                const SizedBox(height: 18),

                // Form Container

                Container(

                  padding: const EdgeInsets.all(20),

                  decoration: BoxDecoration(

                    color: cardBg,

                    borderRadius: BorderRadius.circular(18),

                    border: Border.all(color: borderColor),

                    boxShadow: [

                      BoxShadow(

                        color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),

                        blurRadius: 10,

                        offset: const Offset(0, 4),

                      ),

                    ],

                  ),

                  child: Form(

                    key: _passwordFormKey,

                    child: Column(

                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [

                        Text(

                          'Current password',

                          style: TextStyle(

                            fontSize: 13,

                            fontWeight: FontWeight.w600,

                            color: textPrimary,

                          ),

                        ),

                        const SizedBox(height: 6),

                        TextFormField(

                          controller: _oldPasswordController,

                          obscureText: _obscureOld,

                          style: TextStyle(color: textPrimary, fontSize: 14.5),

                          decoration: InputDecoration(

                            hintText: 'Enter current password',

                            hintStyle: TextStyle(color: textSecondary, fontSize: 14),

                            filled: true,

                            fillColor: inputBg,

                            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),

                            suffixIcon: IconButton(

                              icon: Icon(

                                _obscureOld

                                    ? Icons.visibility_off_outlined

                                    : Icons.visibility_outlined,

                                size: 20,

                              ),

                              onPressed: () =>

                                  setState(() => _obscureOld = !_obscureOld),

                            ),

                            border: OutlineInputBorder(

                              borderRadius: BorderRadius.circular(10),

                              borderSide: BorderSide(color: borderColor),

                            ),

                            enabledBorder: OutlineInputBorder(

                              borderRadius: BorderRadius.circular(10),

                              borderSide: BorderSide(color: borderColor),

                            ),

                          ),

                          validator: (val) =>

                              (val == null || val.isEmpty)

                                  ? 'Enter current password'

                                  : null,

                        ),

                        const SizedBox(height: 16),

                        Text(

                          'New password',

                          style: TextStyle(

                            fontSize: 13,

                            fontWeight: FontWeight.w600,

                            color: textPrimary,

                          ),

                        ),

                        const SizedBox(height: 6),

                        TextFormField(

                          controller: _newPasswordController,

                          obscureText: _obscureNew,

                          style: TextStyle(color: textPrimary, fontSize: 14.5),

                          decoration: InputDecoration(

                            hintText: 'Enter new password',

                            hintStyle: TextStyle(color: textSecondary, fontSize: 14),

                            filled: true,

                            fillColor: inputBg,

                            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),

                            suffixIcon: IconButton(

                              icon: Icon(

                                _obscureNew

                                    ? Icons.visibility_off_outlined

                                    : Icons.visibility_outlined,

                                size: 20,

                              ),

                              onPressed: () =>

                                  setState(() => _obscureNew = !_obscureNew),

                            ),

                            border: OutlineInputBorder(

                              borderRadius: BorderRadius.circular(10),

                              borderSide: BorderSide(color: borderColor),

                            ),

                            enabledBorder: OutlineInputBorder(

                              borderRadius: BorderRadius.circular(10),

                              borderSide: BorderSide(color: borderColor),

                            ),

                          ),

                          validator: (val) {

                            if (val == null || val.isEmpty) {

                              return 'Enter new password';

                            }

                            if (val.length < 4) {

                              return 'Password must be at least 4 characters';

                            }

                            return null;

                          },

                        ),

                        const SizedBox(height: 16),

                        Text(

                          'Confirm new password',

                          style: TextStyle(

                            fontSize: 13,

                            fontWeight: FontWeight.w600,

                            color: textPrimary,

                          ),

                        ),

                        const SizedBox(height: 6),

                        TextFormField(

                          controller: _confirmPasswordController,

                          obscureText: _obscureConfirm,

                          style: TextStyle(color: textPrimary, fontSize: 14.5),

                          decoration: InputDecoration(

                            hintText: 'Confirm new password',

                            hintStyle: TextStyle(color: textSecondary, fontSize: 14),

                            filled: true,

                            fillColor: inputBg,

                            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),

                            suffixIcon: IconButton(

                              icon: Icon(

                                _obscureConfirm

                                    ? Icons.visibility_off_outlined

                                    : Icons.visibility_outlined,

                                size: 20,

                              ),

                              onPressed: () =>

                                  setState(() => _obscureConfirm = !_obscureConfirm),

                            ),

                            border: OutlineInputBorder(

                              borderRadius: BorderRadius.circular(10),

                              borderSide: BorderSide(color: borderColor),

                            ),

                            enabledBorder: OutlineInputBorder(

                              borderRadius: BorderRadius.circular(10),

                              borderSide: BorderSide(color: borderColor),

                            ),

                          ),

                          validator: (val) {

                            if (val == null || val.isEmpty) {

                              return 'Confirm new password';

                            }

                            if (val != _newPasswordController.text) {

                              return 'Passwords do not match';

                            }

                            return null;

                          },

                        ),

                        const SizedBox(height: 24),

                        SizedBox(

                          width: double.infinity,

                          height: 48,

                          child: ElevatedButton.icon(

                            icon: _changingPassword

                                ? const SizedBox(

                                    width: 18,

                                    height: 18,

                                    child: CircularProgressIndicator(

                                      strokeWidth: 2,

                                      color: Colors.white,

                                    ),

                                  )

                                : const Icon(Icons.shield_outlined, size: 20, color: Colors.white),

                            label: Text(

                              _changingPassword ? 'Updating Password...' : 'Update Password',

                              style: const TextStyle(

                                fontWeight: FontWeight.bold,

                                fontSize: 15,

                                color: Colors.white,

                              ),

                            ),

                            style: ElevatedButton.styleFrom(

                              backgroundColor: const Color(0xff2563eb),

                              shape: RoundedRectangleBorder(

                                borderRadius: BorderRadius.circular(12),

                              ),

                              elevation: 0,

                            ),

                            onPressed: _changingPassword ? null : _updatePassword,

                          ),

                        ),

                      ],

                    ),

                  ),

                ),

              ],

            ),

          ),

        ),

      ),

    );

  }

}

class _PhotoOptionButton extends StatelessWidget {

  final IconData icon;

  final String label;

  final Color color;

  final VoidCallback onTap;

  const _PhotoOptionButton({

    required this.icon,

    required this.label,

    required this.color,

    required this.onTap,

  });

  @override

  Widget build(BuildContext context) {

    return InkWell(

      onTap: onTap,

      borderRadius: BorderRadius.circular(14),

      child: Container(

        width: 130,

        padding: const EdgeInsets.symmetric(vertical: 16),

        decoration: BoxDecoration(

          color: color.withValues(alpha: 0.08),

          borderRadius: BorderRadius.circular(14),

          border: Border.all(color: color.withValues(alpha: 0.3)),

        ),

        child: Column(

          children: [

            Icon(icon, size: 30, color: color),

            const SizedBox(height: 8),

            Text(

              label,

              style: TextStyle(

                fontSize: 13,

                fontWeight: FontWeight.w600,

                color: color,

              ),

            ),

          ],

        ),

      ),

    );

  }

}

class _ReadOnlyInfoTile extends StatelessWidget {

  final String label;

  final String value;

  final IconData icon;

  final bool? isDark;

  const _ReadOnlyInfoTile({

    required this.label,

    required this.value,

    required this.icon,

    this.isDark,

  });

  @override

  Widget build(BuildContext context) {

    final dark = isDark ?? (Theme.of(context).brightness == Brightness.dark);

    final bg = dark ? const Color(0xff0f172a) : const Color(0xfff8fafc);

    final borderColor = dark ? const Color(0xff334155) : const Color(0xffe2e8f0);

    final textPrimary = dark ? Colors.white : const Color(0xff0f172a);

    final textSecondary = dark ? const Color(0xff94a3b8) : const Color(0xff64748b);

    return Column(

      crossAxisAlignment: CrossAxisAlignment.start,

      children: [

        Text(

          label,

          style: TextStyle(

            fontSize: 12,

            fontWeight: FontWeight.w600,

            color: textSecondary,

          ),

        ),

        const SizedBox(height: 6),

        Container(

          width: double.infinity,

          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),

          decoration: BoxDecoration(

            color: bg,

            borderRadius: BorderRadius.circular(10),

            border: Border.all(color: borderColor),

          ),

          child: Row(

            children: [

              Icon(icon, size: 20, color: textSecondary),

              const SizedBox(width: 12),

              Expanded(

                child: Text(

                  value,

                  style: TextStyle(

                    fontSize: 14,

                    fontWeight: FontWeight.w600,

                    color: textPrimary,

                  ),

                ),

              ),

            ],

          ),

        ),

      ],

    );

  }

}