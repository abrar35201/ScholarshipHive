package com.scholarshiphive.scholarshiphive

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (not the plain FlutterActivity) is required by the
// local_auth plugin — biometric prompts are shown via the AndroidX Fragment
// APIs, which only a FragmentActivity host can provide.
class MainActivity : FlutterFragmentActivity()
