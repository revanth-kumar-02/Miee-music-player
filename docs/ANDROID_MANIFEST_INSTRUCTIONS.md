# Android Manifest Changes Required for Background Playback

Add the following to android/app/src/main/AndroidManifest.xml

## Permissions (inside <manifest> tag, before <application>):
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />

## Service (inside <application> tag):
    <service android:name="com.ryanheise.audioservice.AudioServiceService"
        android:foregroundServiceType="mediaPlayback"
        android:exported="true">
        <intent-filter>
            <action android:name="android.media.browse.MediaBrowserService" />
        </intent-filter>
    </service>

    <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver"
        android:exported="true">
        <intent-filter>
            <action android:name="android.intent.action.MEDIA_BUTTON" />
        </intent-filter>
    </receiver>
