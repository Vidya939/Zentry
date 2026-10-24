import 'package:flutter/material.dart';

import 'zentry_api_service.dart';

class ZentrySafeInside extends StatefulWidget {
  final int incidentId;

  const ZentrySafeInside({super.key, required this.incidentId});

  @override
  State<ZentrySafeInside> createState() => _ZentrySafeInsideState();
}

class _ZentrySafeInsideState extends State<ZentrySafeInside> {
  final _formKey = GlobalKey<FormState>();

  static const List<String> _locations = [
    'Admin Block',
    'North Block',
    'Conf Room',
    'North Block Canteen',
  ];

  String? _location;
  String? _condition;
  String? _evacuationStatus;

  bool _submitting = false;
  bool _submitted = false;

  Future<void> _submitResponse() async {
    if (_submitting || _submitted) return;

    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);

    try {
      await ZentryApiService.submitResponse(
        incidentId: widget.incidentId,
        status: 'SAFE_INSIDE',
        locationDetails: _location!,
        conditionStatus: _condition!,
        evacuationStatus: _evacuationStatus!,
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

  Widget _dropdown({
    required String label,
    required String hint,
    required List<String> options,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      hint: Text(hint),
      items: options
          .map(
            (option) =>
                DropdownMenuItem<String>(value: option, child: Text(option)),
          )
          .toList(),
      onChanged: _submitting ? null : onChanged,
      validator: (value) =>
          value == null || value.isEmpty ? 'Please select $label' : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        elevation: 10,
        shadowColor: Colors.black,
        backgroundColor: Colors.white,
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
              'STILL INSIDE',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.deepOrange,
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: _submitted
            ? Column(
                children: [
                  const SizedBox(height: 30),
                  const Icon(Icons.check_circle, color: Colors.green, size: 90),
                  const SizedBox(height: 16),
                  const Text(
                    'Your response has been submitted',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  _submittedDetail('Location', _location!),
                  _submittedDetail(
                    'Condition',
                    _condition == 'INJURED' ? 'Injured' : 'Not injured',
                  ),
                  _submittedDetail(
                    'Evacuation',
                    _evacuationStatus == 'COMPLETED'
                        ? 'Completed'
                        : 'Not completed',
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
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.deepOrange,
                      size: 80,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'You are still inside',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepOrange,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tell the safety officer where you are and whether '
                      'you are injured or have completed evacuation.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15),
                    ),
                    const SizedBox(height: 28),
                    _dropdown(
                      label: 'Location',
                      hint: 'Select your current location',
                      options: _locations,
                      value: _location,
                      onChanged: (value) => setState(() => _location = value),
                    ),
                    const SizedBox(height: 20),
                    _dropdown(
                      label: 'Condition',
                      hint: 'Select your condition',
                      options: const ['INJURED', 'NOT_INJURED'],
                      value: _condition,
                      onChanged: (value) => setState(() => _condition = value),
                    ),
                    const SizedBox(height: 20),
                    _dropdown(
                      label: 'Evacuation status',
                      hint: 'Select evacuation status',
                      options: const ['COMPLETED', 'NOT_COMPLETED'],
                      value: _evacuationStatus,
                      onChanged: (value) =>
                          setState(() => _evacuationStatus = value),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _submitting ? null : _submitResponse,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrange,
                          foregroundColor: Colors.white,
                        ),
                        child: _submitting
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : const Text(
                                'Submit response',
                                style: TextStyle(fontSize: 17),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
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

  Widget _submittedDetail(String label, String value) {
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
