import 'package:flutter/material.dart';
import './zentry_normal.dart';
import 'dart:async';
import './zentry_api_service.dart';
import './zentry_visitor_register.dart';

class ZentryLogin extends StatefulWidget {
  const ZentryLogin({super.key});

  @override
  State<ZentryLogin> createState() => _ZentryLoginState();
}

class _ZentryLoginState extends State<ZentryLogin> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
bool _isLoading = false;
String? _loginError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

Future<void> _login() async {
  if (_isLoading || !_formKey.currentState!.validate()) {
    return;
  }

  setState(() {
    _isLoading = true;
    _loginError = null;
  });

  try {
    await ZentryApiService.login(
      email: _emailController.text,
      password: _passwordController.text,
    );

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const ZentryNormal(),
      ),
    );
  } on TimeoutException {
    if (mounted) {
      setState(() {
        _loginError = 'The server took too long to respond.';
      });
    }
  } catch (e) {
    if (mounted) {
      setState(() {
        _loginError = e.toString().replaceFirst('Exception: ', '');
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
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              elevation: 4,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Zentry logo
                      Image.asset(
                        'assets/images/zentry_logo.png',
                        height: 90,
                        width: 140,
                        fit: BoxFit.contain,
                      ),

                      const SizedBox(height: 16),

                      // const Text(
                      //   'Zentry Deres',
                      //   textAlign: TextAlign.center,
                      //   style: TextStyle(
                      //     fontSize: 26,
                      //     fontWeight: FontWeight.bold,
                      //     color: Colors.black,
                      //   ),
                      // ),

                      const SizedBox(height: 8),

                      const Text(
                        'Employee Safety Login',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey,
                        ),
                      ),

                      const SizedBox(height: 30),

                      const Text(
                        'Email Address',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      const SizedBox(height: 8),

                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          hintText: 'Enter your email',
                          prefixIcon: Icon(Icons.email_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final email = value?.trim() ?? '';

                          if (email.isEmpty) {
                            return 'Please enter your email';
                          }

                          if (!RegExp(
                            r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                          ).hasMatch(email)) {
                            return 'Please enter a valid email';
                          }

                          return null;
                        },
                      ),

                      const SizedBox(height: 20),

                      const Text(
                        'Password',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      const SizedBox(height: 8),

                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          hintText: 'Enter your password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your password';
                          }

                          return null;
                        },
                      ),

                      const SizedBox(height: 28),
if (_loginError != null) ...[
  Text(
    _loginError!,
    style: const TextStyle(color: Colors.red),
    textAlign: TextAlign.center,
  ),
  const SizedBox(height: 12),
],
                      SizedBox(
                        height: 50,
                        width: double.infinity,
                        child: ElevatedButton(
onPressed: _isLoading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                const Color.fromARGB(255, 160, 214, 239),
                            foregroundColor: Colors.black,
                            elevation: 0,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.zero,
                            ),
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
        'Login',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
                        ),
                      ),
const SizedBox(height: 12),

OutlinedButton.icon(
  onPressed: _isLoading
      ? null
      : () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const ZentryVisitorRegister(),
            ),
          );
        },
  icon: const Icon(Icons.badge_outlined),
  label: const Text('Visitor Registration'),
  style: OutlinedButton.styleFrom(
    foregroundColor: Colors.black,
    padding: const EdgeInsets.symmetric(vertical: 14),
    shape: const RoundedRectangleBorder(),
  ),
),
                      const SizedBox(height: 20),

                      const Text(
                        'Authorized personnel only',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
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
