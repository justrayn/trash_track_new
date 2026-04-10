/// Secure configuration management for trash_track
///
/// This file demonstrates secure handling of sensitive configuration
/// such as API keys, database credentials, and other secrets.
///
/// SECURITY BEST PRACTICES:
/// - Never hardcode secrets in source code
/// - Use environment variables for development
/// - Use secure key management in production
/// - Implement proper access controls

import 'package:flutter/foundation.dart';

/// Secure configuration class
/// Loads sensitive values from environment variables or secure storage
class SecureConfig {
  // Supabase Configuration
  static String get supabaseUrl {
    return const String.fromEnvironment(
      'SUPABASE_URL',
      defaultValue: 'https://your-project.supabase.co',
    );
  }

  static String get supabaseAnonKey {
    // NEVER hardcode this value!
    // Load from environment variable or secure storage
    const key = String.fromEnvironment('SUPABASE_ANON_KEY');

    if (key.isEmpty) {
      throw StateError(
        'SUPABASE_ANON_KEY environment variable is required. '
        'Set it in your .env file or build environment.',
      );
    }

    return key;
  }

  // Database Configuration (if needed)
  static String get databaseUrl {
    return const String.fromEnvironment(
      'DATABASE_URL',
      defaultValue: '',
    );
  }

  // API Configuration
  static String get apiBaseUrl {
    return const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://api.trash-track.com',
    );
  }

  // Security Headers
  static Map<String, String> get defaultHeaders {
    return {
      'Content-Type': 'application/json',
      'X-App-Version': '1.0.0',
      'X-Platform': defaultTargetPlatform.name,
    };
  }

  // Development vs Production
  static bool get isProduction {
    return const String.fromEnvironment('ENVIRONMENT') == 'production';
  }

  static bool get isDevelopment {
    return !isProduction;
  }

  // Logging Configuration
  static bool get enableSecurityLogging {
    return const bool.fromEnvironment('ENABLE_SECURITY_LOGGING',
        defaultValue: true);
  }
}

/// Environment variable validation
/// Call this during app initialization to ensure all required secrets are set
void validateEnvironmentConfiguration() {
  final requiredVars = [
    'SUPABASE_URL',
    'SUPABASE_ANON_KEY',
  ];

  final missing = <String>[];

    final value = String.fromEnvironment(varName);
      if (value.isEmpty) {
        missing.add(varName);
      }
  }

  if (missing.isNotEmpty) {
    throw StateError(
      'Missing required environment variables: ${missing.join(', ')}\n'
      'Please set these in your .env file or build configuration.',
    );
  }

  // Log security configuration (without exposing secrets)
  if (SecureConfig.enableSecurityLogging) {
    debugPrint('🔐 Security config validated');
    debugPrint('🌐 Supabase URL configured: ${SecureConfig.supabaseUrl}');
    debugPrint('🔑 API key configured: ${SecureConfig.supabaseAnonKey.isNotEmpty ? 'YES' : 'NO'}');
    debugPrint('🏭 Environment: ${SecureConfig.isProduction ? 'Production' : 'Development'}');
  }
}

/// Example .env file content (DO NOT commit this!)
/*
/// .env file (add to .gitignore!)
SUPABASE_URL=https://your-project-id.supabase.co
SUPABASE_ANON_KEY=your-actual-supabase-anon-key-here
API_BASE_URL=https://api.trash-track.com
ENVIRONMENT=development
ENABLE_SECURITY_LOGGING=true
DATABASE_URL=postgresql://user:password@localhost:5432/trash_track
*/