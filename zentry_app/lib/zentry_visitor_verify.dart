
import 'dart:async';

import 'package:flutter/material.dart';

import 'zentry_api_service.dart';
import 'zentry_emergency.dart';

class ZentryVisitorVerify extends StatefulWidget {
  final String fullName;
  final String email;
  final String vrfId;

  const ZentryVisitorVerify({
    super.key,
    required this.fullName,
    required this.email,
    required this.vrfId,
  });

  @override
  State<ZentryVisitorVerify> createState() =>
      _ZentryVisitorVerifyState();
}

class _ZentryVisitorVerifyState extends State<ZentryVisitorVerify> {
  final _formKey = GlobalKey<FormState>();
  final _otpController = TextEditingController();

  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_isLoading || !_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await ZentryApiService.verifyVisitorEmail(
        vrfId: widget.vrfId,
        email: widget.email,
        otp: _otpController.text.trim(),
      );

      if (!mounted) return;

      // Replace verification screen so Back doesn't return to OTP entry.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const ZentryEmergency(),
        ),
        (route) => false,
      );
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _error = 'The server took too long to respond. Try again.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F4F8),
      appBar: AppBar(
        title: const Text('Verify Visitor Email'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              color: Colors.white,
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.mark_email_read_outlined,
                        size: 64,
                        color: Color(0xFF1976D2),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Verify Your Email',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Hello, ${widget.fullName}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.email,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Your Visitor VRF ID',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF3FF),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFFB7D4F5),
                          ),
                        ),
                        child: SelectableText(
                          widget.vrfId,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                            color: Color(0xFF174A83),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'A six-digit verification code was sent to your email. '
                        'Check your inbox and spam folder.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Verification Code',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _otpController,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          hintText: 'Enter 6-digit OTP',
                          counterText: '',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (!RegExp(r'^\d{6}$')
                              .hasMatch(value?.trim() ?? '')) {
                            return 'Enter the six-digit OTP';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      if (_error != null) ...[
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red),
                        ),
                        const SizedBox(height: 12),
                      ],
                      SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _verify,
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                const Color.fromARGB(255, 160, 214, 239),
                            foregroundColor: Colors.black,
                            elevation: 0,
                            shape: const RoundedRectangleBorder(),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Verify and Continue',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
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
      ),
    );
  }
}
