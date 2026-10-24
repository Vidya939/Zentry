import 'package:flutter/material.dart';

import 'zentry_api_service.dart';

class ZentryHelp extends StatefulWidget {
  final int incidentId;

  const ZentryHelp({super.key, required this.incidentId});

  @override
  State<ZentryHelp> createState() => _ZentryHelpState();
}

class _ZentryHelpState extends State<ZentryHelp> {
final _otherHelpController = TextEditingController();

String? _helpDetails;

static const List<String> _helpOptions = [
  'Need help evacuating',
  'Unable to use stairs',
  'Injured and need assistance',
  'Need other assistance',
];

  static const List<String> _locations = [
    'Admin Block',
    'North Block',
    'Conf Room',
    'North Block Canteen',
  ];

  String? _location;
  bool _submitting = false;
  bool _submitted = false;

  Future<void> _submitHelpRequest() async {
    if (_submitting || _submitted) return;

    // if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);

    try {
      await ZentryApiService.submitResponse(
        incidentId: widget.incidentId,
        status: 'NEED_HELP',
        locationDetails: _location!,
message: _helpDetails == 'Need other assistance'
    ? 'Need other assistance: ${_otherHelpController.text.trim()}'
    : _helpDetails!,
          );

      if (!mounted) return;
      setState(() => _submitted = true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

@override
void dispose() {
  _otherHelpController.dispose();
  super.dispose();
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        elevation: 10,
        shadowColor: Colors.black,
        title: const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Zentry Deres',
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
        padding: const EdgeInsets.all(20),
        child: _submitted
            ? Column(
                children: [
                  const SizedBox(height: 30),
                  const Icon(Icons.check_circle, color: Colors.green, size: 90),
                  const SizedBox(height: 16),
                  const Text(
                    'Help request submitted',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'The safety officer has been notified of your '
                    'reported location and help request.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 20),
                  _detailRow('Location', _location!),
                  _detailRow(
  'Help required',
  _helpDetails == 'Need other assistance'
      ? 'Need other assistance: ${_otherHelpController.text.trim()}'
      : _helpDetails ?? '',
),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Back to emergency'),
                    ),
                  ),
                ],
              )
            : Form(
                // key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      shape: const RoundedRectangleBorder(),
                      color: const Color.fromARGB(255, 227, 38, 25),
                      child: const Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'EMERGENCY HELP REQUEST',
                              style: TextStyle(
                                fontSize: 17,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'I NEED HELP',
                              style: TextStyle(
                                fontSize: 32,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Where are you?',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _location,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Location',
                        hintText: 'Select your current location',
                        border: OutlineInputBorder(),
                      ),
                      items: _locations
                          .map(
                            (location) => DropdownMenuItem<String>(
                              value: location,
                              child: Text(location),
                            ),
                          )
                          .toList(),
                      onChanged: _submitting
                          ? null
                          : (value) => setState(() => _location = value),
                      validator: (value) => value == null || value.isEmpty
                          ? 'Please select your location'
                          : null,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'What help do you need?',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
DropdownButtonFormField<String>(
  initialValue: _helpDetails,
  isExpanded: true,
  decoration: const InputDecoration(
    labelText: 'Help required',
    hintText: 'Select an option',
    border: OutlineInputBorder(),
  ),
  items: _helpOptions.map((option) {
    return DropdownMenuItem<String>(
      value: option,
      child: Text(
        option,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }).toList(),
  onChanged: _submitting
      ? null
      : (value) {
          setState(() {
            _helpDetails = value;
            if (value != 'Need other assistance') {
              _otherHelpController.clear();
            }
          });
        },
  validator: (value) {
    if (value == null) {
      return 'Please select an option';
    }
    return null;
  },
),

if (_helpDetails == 'Need other assistance') ...[
  const SizedBox(height: 16),
  TextFormField(
    controller: _otherHelpController,
    enabled: !_submitting,
    maxLines: 3,
    decoration: const InputDecoration(
      labelText: 'Describe the help you need',
      hintText: 'Enter your specific assistance requirement',
      border: OutlineInputBorder(),
      alignLabelWithHint: true,
    ),
    validator: (value) {
      if (_helpDetails == 'Need other assistance' &&
          (value == null || value.trim().isEmpty)) {
        return 'Please describe the help you need';
      }
      return null;
    },
  ),
],
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _submitting ? null : _submitHelpRequest,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        child: _submitting
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : const Text(
                                'Send help request',
                                style: TextStyle(fontSize: 17),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.pop(context),
                      child: const Text('Back'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}
