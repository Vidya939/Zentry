import 'package:flutter/material.dart';

class ZentryHelp extends StatelessWidget {
  const ZentryHelp({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: true,
        elevation: 10,
        shadowColor: Colors.black,
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
              'HELP',
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
                            'HELP REQUESTED - 0:38',
                            style: TextStyle(fontSize: 18, color: Colors.white),
                          ),
                          Text(
                            'HELP IS COMING',
                            style: TextStyle(
                              fontSize: 37,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
        
              const SizedBox(height: 20),
        
              // Green tick and confirmation
              const Icon(Icons.error, color: Colors.red, size: 120),
        
              const SizedBox(height: 16),
        
              const Text(
                'Officer Notified',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
        
              const SizedBox(height: 8),
        
              const Text(
                'Warden Dispacthed',
                style: TextStyle(fontSize: 15, color: Colors.grey),
              ),
        
              const SizedBox(height: 4),
              const SizedBox(height: 30),
        
              const Divider(),
        
              // Status
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Acknowledged',
                      style: TextStyle(fontSize: 18, color: Colors.black),
                    ),
                    Text(
                      '00:11',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
        
              const Divider(),
        
              // Location
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Location',
                      style: TextStyle(fontSize: 18, color: Colors.black),
                    ),
                    Flexible(
                      child: Text(
                        'Conf, Room2',
                        textAlign: TextAlign.end,
                        style: TextStyle(fontSize: 16, color: Colors.black),
                      ),
                    ),
                  ],
                ),
              ),
        
              const Divider(),
        
              // Response time
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Source',
                      style: TextStyle(fontSize: 18, color: Colors.black),
                    ),
                    Text(
                      'Mobile',
                      style: TextStyle(fontSize: 16, color: Colors.black),
                    ),
                  ],
                ),
              ),
        
              const Divider(),
        
              const SizedBox(height: 30),
        
        
              Text('Stay where you are if it safe',style: TextStyle(fontSize: 18, color: Colors.grey),),
              Text('Keep the phone with you',style: TextStyle(fontSize: 18, color: Colors.grey),),
            ],
          ),
        ),
      ),
    );
  }
}
