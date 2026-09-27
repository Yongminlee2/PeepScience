# 광고 SDK -> WorkManager -> Room. Room은 WorkDatabase_Impl의 기본 생성자를
# 리플렉션으로 부르는데, 릴리스 축소(R8)가 그것을 지워 앱이 켜지자마자 죽는다
# (Unable to get provider androidx.startup.InitializationProvider).
-keep class * extends androidx.room.RoomDatabase { <init>(); }
