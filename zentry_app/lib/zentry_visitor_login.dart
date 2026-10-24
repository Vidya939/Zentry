
import 'dart:async';

import 'package:flutter/material.dart';

import 'zentry_api_service.dart';
import 'zentry_emergency.dart';

class ZentryVisitorLogin extends StatefulWidget {
  const ZentryVisitorLogin({super.key});

  @override
  State<ZentryVisitorLogin> createState() => _ZentryVisitorLoginState();
}

class _ZentryVisitorLoginState extends State<ZentryVisitorLogin> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();

  bool _otpRequested = false;
  bool _isLoading = false;
  String? _error;
  String? _message;

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _requestOtp() async {
    if (_isLoading || !_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _message = null;
    });

    try {
      final result = await ZentryApiService.requestVisitorLoginOtp(
        email: _emailController.text.trim(),
      );

      if (!mounted) return;

      setState(() {
        _otpRequested = true;
        _message = result['message']?.toString() ??
            'If the visitor account is eligible, a verification code will be sent.';
      });
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _error = 'The server took too long to respond. Please try again.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyOtp() async {
    if (_isLoading || !_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _message = null;
    });

    try {
      await ZentryApiService.verifyVisitorLoginOtp(
        email: _emailController.text.trim(),
        otp: _otpController.text.trim(),
      );

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const ZentryEmergency(),
        ),
        (route) => false,
      );
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _error = 'The server took too long to respond. Please try again.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F4F8),
      appBar: AppBar(
        title: const Text('Visitor Login'),
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
                        Icons.badge_outlined,
                        size: 60,
                        color: Color(0xFF1976D2),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Visitor Sign In',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Sign in using the email address associated with your visitor account.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Email Address',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        enabled: !_otpRequested && !_isLoading,
                        decoration: const InputDecoration(
                          hintText: 'Enter your registered email',
                          prefixIcon: Icon(Icons.email_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final email = value?.trim() ?? '';
                          if (email.isEmpty) {
                            return 'Please enter your email';
                          }
                          if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                              .hasMatch(email)) {
                            return 'Please enter a valid email';
                          }
                          return null;
                        },
                      ),
                      if (_otpRequested) ...[
                        const SizedBox(height: 20),
                        const Text(
                          'Verification Code',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _otpController,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          decoration: const InputDecoration(
                            hintText: 'Enter 6-digit OTP',
                            counterText: '',
                            prefixIcon: Icon(Icons.lock_outline),
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (!_otpRequested) return null;
                            if (!RegExp(r'^\d{6}$')
                                .hasMatch(value?.trim() ?? '')) {
                              return 'Enter the six-digit OTP';
                            }
                            return null;
                          },
                        ),
                      ],
                      const SizedBox(height: 20),
                      if (_message != null) ...[
                        Text(
                          _message!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.green),
                        ),
                        const SizedBox(height: 12),
                      ],
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
                          onPressed: _isLoading
                              ? null
                              : (_otpRequested ? _verifyOtp : _requestOtp),
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
                              : Text(
                                  _otpRequested ? 'Verify and Login' : 'Send OTP',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                      if (_otpRequested) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _isLoading
                              ? null
                              : () {
                                  setState(() {
                                    _otpRequested = false;
                                    _otpController.clear();
                                    _error = null;
                                    _message = null;
                                  });
                                },
                          child: const Text('Use a different email'),
                        ),
                      ],
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
