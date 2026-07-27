// the go backend's address root, e.g. "http://localhost:8080" or an ngrok url during local testing.
// AuthService reads the same API_BASE_URL env value but expects the "/api/auth" suffix baked in already,
// so here we strip that suffix back off to get a plain server root other features (shops, images) can build on
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
