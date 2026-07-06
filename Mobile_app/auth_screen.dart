import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:energymon/shared_widgets.dart';
import 'package:energymon/main.dart';

// ---------------------------------------------------------------------------
// LOGIN SCREEN
// ---------------------------------------------------------------------------

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showError('Completează toate câmpurile.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (!mounted) return;
      // AuthGate in main.dart will handle navigation automatically
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      _showError(e.message);
    } catch (e) {
      if (!mounted) return;
      _showError('Eroare neașteptată. Încearcă din nou.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const SizedBox(height: 60),
              // App Logo
              const Center(
                child: NeumorphicContainer(
                  width: 80,
                  height: 80,
                  borderRadius: 40,
                  child: Center(
                    child: Icon(
                      Icons.grid_view_rounded,
                      color: Color(0xFF3A86FF),
                      size: 40,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'SmartHome',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF003566),
                ),
              ),
              const Text(
                'Welcome back to your space.',
                style: TextStyle(color: Color(0xFF8E949A)),
              ),
              const SizedBox(height: 48),

              // Email field
              NeumorphicTextField(
                label: 'Email Address',
                hint: 'hello@example.com',
                icon: Icons.email_outlined,
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 24),

              // Password field
              NeumorphicTextField(
                label: 'Password',
                hint: '••••••••',
                icon: Icons.lock_outline,
                isPassword: _obscurePassword,
                controller: _passwordController,
                trailing: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: const Color(0xFF8E949A),
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                ),
              ),
              const SizedBox(height: 48),

              // Login button
              GestureDetector(
                onTap: _isLoading ? null : _handleLogin,
                child: NeumorphicContainer(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  borderRadius: 16,
                  child: Center(
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF3A86FF),
                            ),
                          )
                        : const Text(
                            'Login',
                            style: TextStyle(
                              color: Color(0xFF3A86FF),
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Navigate to Create Account
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CreateAccountScreen(),
                    ),
                  );
                },
                child: const Text(
                  'Create Account',
                  style: TextStyle(color: Color(0xFF8E949A)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// CREATE ACCOUNT SCREEN
// ---------------------------------------------------------------------------

class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignUp() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (name.isEmpty ||
        email.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty) {
      _showError('Completează toate câmpurile.');
      return;
    }

    if (password.length < 6) {
      _showError('Parola trebuie să aibă minim 6 caractere.');
      return;
    }

    if (password != confirmPassword) {
      _showError('Parolele nu se potrivesc.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': name},
      );

      if (!mounted) return;

      _showSuccess('Cont creat cu succes! Verifică email-ul dacă e necesar.');

      // Navigate back to login after short delay
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) Navigator.pop(context);
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      _showError(e.message);
    } catch (e) {
      if (!mounted) return;
      _showError('Eroare neașteptată. Încearcă din nou.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF2ECC71),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const SizedBox(height: 40),
              // App Logo
              const Center(
                child: NeumorphicContainer(
                  width: 60,
                  height: 60,
                  borderRadius: 30,
                  child: Center(
                    child: Icon(
                      Icons.grid_view_rounded,
                      color: Color(0xFF3A86FF),
                      size: 30,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'SmartHome',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF003566),
                ),
              ),
              const Text(
                'Create your account to begin',
                style: TextStyle(color: Color(0xFF8E949A)),
              ),
              const SizedBox(height: 40),

              // Full Name
              NeumorphicTextField(
                label: 'Full Name',
                hint: 'John Doe',
                icon: Icons.person_outline,
                controller: _nameController,
                keyboardType: TextInputType.name,
              ),
              const SizedBox(height: 20),

              // Email
              NeumorphicTextField(
                label: 'Email Address',
                hint: 'john@example.com',
                icon: Icons.email_outlined,
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 20),

              // Password
              NeumorphicTextField(
                label: 'Password',
                hint: '••••••••',
                icon: Icons.lock_outline,
                isPassword: _obscurePassword,
                controller: _passwordController,
                trailing: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: const Color(0xFF8E949A),
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                ),
              ),
              const SizedBox(height: 20),

              // Confirm Password
              NeumorphicTextField(
                label: 'Confirm Password',
                hint: '••••••••',
                icon: Icons.lock_outline,
                isPassword: _obscureConfirm,
                controller: _confirmPasswordController,
                trailing: IconButton(
                  icon: Icon(
                    _obscureConfirm
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: const Color(0xFF8E949A),
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() => _obscureConfirm = !_obscureConfirm);
                  },
                ),
              ),
              const SizedBox(height: 40),

              // Sign Up button
              GestureDetector(
                onTap: _isLoading ? null : _handleSignUp,
                child: NeumorphicContainer(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  borderRadius: 16,
                  child: Center(
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF3A86FF),
                            ),
                          )
                        : const Text(
                            'Sign Up',
                            style: TextStyle(
                              color: Color(0xFF3A86FF),
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Back to Login
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back, size: 16, color: Color(0xFF8E949A)),
                    SizedBox(width: 8),
                    Text(
                      'Back to Login',
                      style: TextStyle(color: Color(0xFF8E949A)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
