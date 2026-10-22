import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import './zentry_help.dart';
import './zentry_safe.dart';
import './zentry_safe_outside.dart';
import './zentry_safe_inside.dart';
import './zentry_normal.dart';
import './zentry_api_service.dart';

class ZentryEmergency extends StatefulWidget {
  const ZentryEmergency({super.key});

  @override
  State<ZentryEmergency> createState() => _ZentryEmergencyState();
}

class _ZentryEmergencyState extends State<ZentryEmergency> {
  Map<String, dynamic>? _incident;

  bool _loading = true;
  bool _isFetching = false;
  bool _isNavigatingToNormal = false;

  String? _error;
  Timer? _pollTimer;

  Future<void> _submitSafetyStatus({
    required String status,
    required Widget destination,
  }) async {
    if (_incident == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active incident found.')),
      );
      return;
    }

    final incidentId = int.tryParse(_incident!['id'].toString());

    if (incidentId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Invalid incident ID.')));
      return;
    }

    try {
      // debugPrint('ZENTRY BUTTON SELECTED: status=$status');
      await ZentryApiService.submitResponse(
        incidentId: incidentId,
        status: status,
      );

      if (!mounted) return;

      Navigator.push(context, MaterialPageRoute(builder: (_) => destination));
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  void initState() {
    super.initState();

    _fetchActiveIncident();

    // Check for incident updates every 5 seconds.
    _pollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _fetchActiveIncident(),
    );
  }

  Future<void> _fetchActiveIncident() async {
    // Prevent overlapping requests and repeated navigation.
    if (_isFetching || _isNavigatingToNormal || !mounted) {
      return;
    }

    _isFetching = true;

    try {
      final response = await http
          .get(
            Uri.parse('http://10.0.2.2:8000/incidents/active'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! List) {
        throw const FormatException('Invalid active incidents response');
      }

      if (!mounted) return;

      // No active incidents means the officer has cleared all issues.
      if (decoded.isEmpty) {
        _isNavigatingToNormal = true;
        _pollTimer?.cancel();

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ZentryNormal()),
          (route) => false,
        );

        return;
      }

      final activeIncident = Map<String, dynamic>.from(decoded.first);

      setState(() {
        _incident = activeIncident;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      // A connection error must not clear the emergency screen.
      setState(() {
        _error = 'Unable to connect to the Zentry server.';
        _loading = false;
      });
    } finally {
      _isFetching = false;
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        elevation: 10,
        shadowColor: Colors.black,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Zentry Deres',
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const Text(
              'EMERGENCY',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              Card(
                shape: const RoundedRectangleBorder(),
                color: const Color.fromARGB(255, 227, 38, 25),
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
                            _loading
                                ? 'CHECKING FOR EMERGENCY...'
                                : _error != null
                                ? 'CONNECTION ERROR'
                                : _incident == null
                                ? 'NO ACTIVE EMERGENCY'
                                : 'EMERGENCY ACTIVE',
                            style: const TextStyle(
                              fontSize: 18,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            (_incident?['title'] ?? 'No active incident')
                                .toString()
                                .toUpperCase(),
                            style: const TextStyle(
                              fontSize: 37,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _error ??
                                (_incident == null
                                    ? 'Waiting for an active incident'
                                    : '${_incident!['message']}\n'
                                          'Location: '
                                          '${_incident!['location']}'),
                            style: const TextStyle(
                              fontSize: 15,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'TAP ONE',
                    style: TextStyle(fontSize: 20, color: Colors.black),
                  ),
                ),
              ),

              // SAFE - AT ASSEMBLY POINT
              InkWell(
                onTap: () {
                  _submitSafetyStatus(
                    status: 'SAFE_AT_ASSEMBLY',
                    destination: const ZentrySafe(),
                  );
                },
                child: Card(
                  margin: const EdgeInsetsDirectional.only(bottom: 10),
                  shape: const RoundedRectangleBorder(),
                  color: const Color.fromARGB(255, 22, 148, 26),
                  child: const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text(
                                'SAFE - AT ASSEMBLY POINT',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text(
                                'I have reached the North Car Park',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // SAFE - OUTSIDE, ELSEWHERE
              InkWell(
                onTap: () {
                  _submitSafetyStatus(
                    status: 'SAFE_OUTSIDE',
                    destination: const ZentrySafeOutside(),
                  );
                },
                child: Card(
                  margin: const EdgeInsetsDirectional.only(bottom: 10),
                  shape: const RoundedRectangleBorder(),
                  color: const Color.fromARGB(255, 121, 101, 72),
                  child: const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text(
                                'SAFE - OUTSIDE, ELSEWHERE',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text(
                                'Out of the building, not at assembly',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // SAFE - STILL INSIDE
              InkWell(
                onTap: () {
                  _submitSafetyStatus(
                    status: 'SAFE_INSIDE',
                    destination: const ZentrySafeInside(),
                  );
                },
                child: Card(
                  margin: const EdgeInsetsDirectional.only(bottom: 10),
                  shape: const RoundedRectangleBorder(),
                  color: const Color.fromARGB(255, 185, 22, 174),
                  child: const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text(
                                'SAFE - STILL INSIDE',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text(
                                'Unhurt but not evacuated yet',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // I NEED HELP
              InkWell(
                onTap: () {
                  _submitSafetyStatus(
                    status: 'NEED_HELP',
                    destination: const ZentryHelp(),
                  );
                },
                child: Card(
                  margin: const EdgeInsetsDirectional.only(bottom: 10),
                  shape: const RoundedRectangleBorder(),
                  color: const Color.fromARGB(255, 227, 38, 25),
                  child: const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text(
                                'I NEED HELP',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text(
                                'I cannot evacuate - send someone',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
