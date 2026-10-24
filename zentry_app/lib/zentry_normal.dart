import 'package:flutter/material.dart';
import 'package:zentry_app/zentry_emergency.dart';

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'zentry_api_service.dart';
import 'zentry_login.dart';
class ZentryNormal extends StatefulWidget {
  const ZentryNormal({super.key});

  @override
  State<ZentryNormal> createState() => _ZentryNormalState();
}

class _ZentryNormalState extends State<ZentryNormal> {

Future<void> _loadLastDrill() async {
  try {
    final result = await ZentryApiService.getLastDrill();

    if (!mounted) return;

    setState(() {
      _lastDrill = result;
      _lastDrillError = null;
      _loadingLastDrill = false;
    });
  } catch (e) {
    if (!mounted) return;

    setState(() {
      _lastDrillError = e.toString();
      _loadingLastDrill = false;
    });
  }
}


String _formatDrillDateTime(dynamic value) {
  if (value == null) return 'Not available';

  final date = DateTime.tryParse(value.toString());
  if (date == null) return 'Not available';

  final local = date.toLocal();

  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  final day = local.day.toString().padLeft(2, '0');
  final month = months[local.month - 1];
  final year = local.year;
  final hour = (local.hour % 12 == 0 ? 12 : local.hour % 12)
      .toString()
      .padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  final second = local.second.toString().padLeft(2, '0');
  final period = local.hour >= 12 ? 'PM' : 'AM';

  return '$day $month $year, $hour:$minute:$second $period';
}


String _formatResponseDuration(dynamic value) {
  if (value == null) return 'Not responded';

  final seconds = int.tryParse(value.toString());
  if (seconds == null || seconds < 0) return 'Not available';

  if (seconds < 60) return '${seconds}s';

  final minutes = seconds ~/ 60;
  final remainingSeconds = seconds % 60;

  if (minutes < 60) {
    return remainingSeconds == 0
        ? '${minutes}m'
        : '${minutes}m ${remainingSeconds}s';
  }

  final hours = minutes ~/ 60;
  final remainingMinutes = minutes % 60;

  return remainingMinutes == 0
      ? '${hours}h'
      : '${hours}h ${remainingMinutes}m';
}


  Timer? _pollTimer;
  // bool _checking = true;
  bool _checkingIncident = false;

  String _statusMessage = 'CONNECTING TO ZENTRY SERVER';
Map<String, dynamic>? _lastDrill;
bool _loadingLastDrill = true;
String? _lastDrillError;

@override
void initState() {
  super.initState();

  _loadLastDrill();
  _checkForIncident();

  _pollTimer = Timer.periodic(
    const Duration(seconds: 2),
    (_) => _checkForIncident(),
  );
}


  Future<void> _checkForIncident() async {
    if (_checkingIncident) return;
    _checkingIncident = true;

    try {
      final response = await http.get(
Uri.parse(
  'https://lives-cheaper-hello-perform.trycloudflare.com/incidents/active',
),
        headers: {'Accept': 'application/json'},
      );

      if (!mounted) return;

      if (response.statusCode != 200) {
        setState(() {
          _statusMessage = 'SERVER CONNECTION UNAVAILABLE';
          // _checking = false;
        });
        return;
      }

      final List<dynamic> incidents = jsonDecode(response.body);

      if (incidents.isNotEmpty) {
        _pollTimer?.cancel();

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const ZentryEmergency(),
          ),
        );

        return;
      }

      setState(() {
        _statusMessage = 'NO ACTIVE INCIDENT';
        // _checking = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _statusMessage = 'SERVER CONNECTION UNAVAILABLE';
        // _checking = false;
      });
    } finally {
      _checkingIncident = false;
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }


  String _accountValue(List<String> keys, {String fallback = 'Not available'}) {
    final account = ZentryApiService.account;

    for (final key in keys) {
      final value = account?[key]?.toString().trim();
      if (value != null && value.isNotEmpty && value != 'null') {
        return value;
      }
    }

    return fallback;
  }

  Future<void> _showProfile() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final employeeCode = _accountValue(
          ['employee_code', 'employee_id', 'code'],
        );
        final name = _accountValue(
          ['full_name', 'name', 'employee_name'],
        );
        final email = _accountValue(['email']);

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(
                  child: CircleAvatar(
                    radius: 32,
                    child: Icon(Icons.person, size: 36),
                  ),
                ),
                const SizedBox(height: 16),
                const Center(
                  child: Text(
                    'My Profile',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('Employee Code'),
                  subtitle: Text(employeeCode),
                ),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Name'),
                  subtitle: Text(name),
                ),
                ListTile(
                  leading: const Icon(Icons.email_outlined),
                  title: const Text('Email'),
                  subtitle: Text(email),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.logout, color: Colors.red),
                    label: const Text(
                      'Logout',
                      style: TextStyle(color: Colors.red),
                    ),
                    onPressed: () async {
                      Navigator.pop(sheetContext);
                      await _confirmLogout();
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Are you sure?'),
        content: const Text('Do you want to log out of Zentry?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (shouldLogout != true || !mounted) return;

    await ZentryApiService.logout();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ZentryLogin()),
      (route) => false,
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: true,
        elevation: 10,
        shadowColor: Colors.white,
        backgroundColor: Colors.white,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Zentry Deres",
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
IconButton(
  tooltip: 'My Profile',
  icon: const Icon(
    Icons.account_circle_outlined,
    size: 32,
    color: Colors.black,
  ),
  onPressed: _showProfile,
),
          ],
        ),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [const SizedBox(height: 20),
          Card(
            margin: EdgeInsetsDirectional.only(bottom: 40),
            shape: const RoundedRectangleBorder(),
            color: const Color.fromARGB(255, 231, 243, 229),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _statusMessage,
                        style: TextStyle(fontSize: 18,fontWeight: FontWeight.bold, color: const Color.fromARGB(255, 24, 131, 28)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          
          
                    Card(
                      margin: EdgeInsetsDirectional.only(bottom: 20),
            shape: const RoundedRectangleBorder(),
            color: const Color.fromARGB(255, 228, 230, 227),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Location',
                        style: TextStyle(fontSize: 15, color: Colors.grey),
                        
                      ),
                      
                                            Text(
                        'Hyderabad',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                      )
                    ],
                  ),
                ),
              ),
            ),
          ),
                    
                    
                    
                    Card(
                      margin: EdgeInsetsDirectional.only(bottom: 20),
            shape: const RoundedRectangleBorder(),
            color: const Color.fromARGB(255, 228, 230, 227),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Assembly Point',
                        style: TextStyle(fontSize: 15, color: Colors.grey),
                        
                      ),
                      
                                            Text(
                        'North car Park',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
     

Card(
  margin: const EdgeInsetsDirectional.only(bottom: 20),
  shape: const RoundedRectangleBorder(),
  color: const Color.fromARGB(255, 228, 230, 227),
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Last Safety Drill',
            style: TextStyle(fontSize: 15, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          if (_loadingLastDrill)
            const Text('Loading last drill...')
else if (_lastDrillError != null)
  Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Unable to load drill details'),
      const SizedBox(height: 6),
      Text(
        _lastDrillError!,
        style: const TextStyle(
          fontSize: 12,
          color: Colors.red,
        ),
      ),
      TextButton(
        onPressed: () {
          setState(() {
            _loadingLastDrill = true;
            _lastDrillError = null;
          });
          _loadLastDrill();
        },
        child: const Text('Retry'),
      ),
    ],
  )
          else if (_lastDrill == null)
            const Text(
              'No completed drill yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            )
          else ...[
            Text(
              _lastDrill!['title']?.toString() ?? 'Safety Drill',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 6),

Text(
  'Start: ${_formatDrillDateTime(_lastDrill!['created_at'])}',
  style: const TextStyle(fontSize: 14, color: Colors.grey),
),
Text(
  'End: ${_formatDrillDateTime(_lastDrill!['cleared_at'])}',
  style: const TextStyle(fontSize: 14, color: Colors.grey),
),
const SizedBox(height: 6),
Text(
  'You Responded in: ${_formatResponseDuration(_lastDrill!['response_duration_seconds'])}',
  style: const TextStyle(fontSize: 14, color: Colors.grey),
),

          ],
        ],
      ),
    ),
  ),
),

                    Card(
                      margin: EdgeInsetsDirectional.only(bottom: 20),
            shape: const RoundedRectangleBorder(),
            color: const Color.fromARGB(255, 228, 230, 227),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'App Status',
                        style: TextStyle(fontSize: 15, color: Colors.grey),
                        
                      ),
                      
                                            Text(
                        'Enrolled and Ready',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                                            Text(
                        'Nothing in background',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
     
                 const SizedBox(height: 30),

            Text(
              'Deres does not track your location',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            Text(
              'Requested only during an incident or Drill',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
