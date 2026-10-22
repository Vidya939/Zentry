import 'package:flutter/material.dart';
import 'package:zentry_app/zentry_emergency.dart';

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ZentryNormal extends StatefulWidget {
  const ZentryNormal({super.key});

  @override
  State<ZentryNormal> createState() => _ZentryNormalState();
}

class _ZentryNormalState extends State<ZentryNormal> {
  Timer? _pollTimer;
  bool _checking = true;
  bool _checkingIncident = false;

  String _statusMessage = 'CONNECTING TO ZENTRY SERVER';

  @override
  void initState() {
    super.initState();

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
        Uri.parse('http://10.0.2.2:8000/incidents/active'),
        headers: {'Accept': 'application/json'},
      );

      if (!mounted) return;

      if (response.statusCode != 200) {
        setState(() {
          _statusMessage = 'SERVER CONNECTION UNAVAILABLE';
          _checking = false;
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
        _checking = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _statusMessage = 'SERVER CONNECTION UNAVAILABLE';
        _checking = false;
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
            Text(
              'A.Rao',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
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
                        'YOUR SITE',
                        style: TextStyle(fontSize: 15, color: Colors.grey),
                        
                      ),
                      
                                            Text(
                        'Mumbai Office',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                                            Text(
                        'Floor 3',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
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
                        'Last Drill',
                        style: TextStyle(fontSize: 15, color: Colors.grey),
                        
                      ),
                      
                                            Text(
                        '14 August 2026',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                                            Text(
                        'Responded in 42s',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
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
