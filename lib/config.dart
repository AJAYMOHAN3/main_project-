const String kFirebaseAPIKey = "AIzaSyC61uOOK-kmotuQKTsCKIrkjDAYAQ5CYAw";
const String kProjectId = "homes-6b1dd";
const String kStorageBucket = "homes-6b1dd.firebasestorage.app";
String kFirestoreBaseUrl =
    "https://firestore.googleapis.com/v1/projects/$kProjectId/databases/(default)/documents";
const String kStorageBaseUrl =
    "https://firebasestorage.googleapis.com/v0/b/$kStorageBucket/o";
const bool kIsWeb = bool.fromEnvironment('dart.library.js_util');
final String stripePublishableKey =
    "pk_test_51SxE65LnBSmKhaeHxjA9ZLh5LnlKPxpNf4GRVAlFEDZeTkEczdxnGHi7oJ3dWGlI2QjyerHEltGmG2f2Hg2oKhqV00mxy4kcor";
final String stripeSecretKey =
    "sk_test_51SxE65LnBSmKhaeHmf4GQGvjCfhuOPSsvtmQ5JY6GAYLlzKK8KbGMfTBu9VO7BVdv3moqUWPhMFxv8uDgRp0Agcg00eyhqtE1c";
