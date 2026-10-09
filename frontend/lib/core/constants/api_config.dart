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

  /// Turns a photo url as the api sends it into one `Image.network` can fetch.
  ///
  /// **The api sends `/images/…` when photos come off its own disk and a full `https://…` when they
  /// come from R2**, because only the server knows which. A relative path handed straight to
  /// `Image.network` fails silently - the frame stays empty and nothing anywhere says why - so
  /// **every photo field from the backend goes through this**, products and storefronts alike.
  static String? absoluteImageUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return '$serverRoot$url';
  }
}
