// the go backend's address root. AuthService reads the same API_BASE_URL but expects "/api/auth"
// baked in, so that suffix is stripped back off here.
class ApiConfig {
  static const String _authBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080/api/auth',
  );

  static String get serverRoot {
    const authSuffix = '/api/auth';
    return _authBaseUrl.endsWith(authSuffix)
        ? _authBaseUrl.substring(0, _authBaseUrl.length - authSuffix.length)
        : _authBaseUrl;
  }
}
