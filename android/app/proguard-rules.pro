# Ignore warnings about Stripe Push Provisioning (Google Wallet)
-dontwarn com.stripe.android.pushProvisioning.**
-dontwarn com.reactnativestripesdk.**

# Keep Stripe classes safe
-keep class com.stripe.android.** { *; }
-keep class com.reactnativestripesdk.** { *; }