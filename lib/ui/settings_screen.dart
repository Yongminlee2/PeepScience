import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'strings.dart';
import 'theme.dart';

/// SharedPreferences key for the sound on/off toggle. Value-only for now
/// (Task 18 wires actual playback and will read this same key to decide
/// whether to call Sound.play at all).
const String soundEnabledPrefKey = 'sound_enabled';

/// Sound on/off switch (persists a bool only) + 3-way language choice
/// (system/ko/en, backed by [AppLang]).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _soundOn = true;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadSound();
  }

  Future<void> _loadSound() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getBool(soundEnabledPrefKey) ?? true;
      if (!mounted) return;
      setState(() {
        _soundOn = v;
        _loaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loaded = true);
    }
  }

  Future<void> _setSound(bool v) async {
    setState(() => _soundOn = v);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(soundEnabledPrefKey, v);
    } catch (_) {
      // Best-effort persistence only, same posture as AppLang's own
      // _persistLang - a failed write just reverts to the stored default
      // (or true) on next launch instead of crashing this screen.
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listens to AppLang directly (same reasoning as home_screen.dart's
    // build) so this screen's own radio labels/title re-render immediately
    // on a language change, regardless of any ancestor's const-identity
    // rebuild bailout.
    return ValueListenableBuilder<String>(
      valueListenable: AppLang(),
      builder: (context, lang, _) => Scaffold(
        appBar: AppBar(title: Text(S.t('settings'))),
        body: SafeArea(
          child: ListView(
            padding: scrollPadding(context),
            children: [
              SwitchListTile(
                title: Text(S.t('sound')),
                value: _soundOn,
                onChanged: _loaded ? _setSound : null,
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  S.t('language'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              RadioGroup<String>(
                groupValue: lang,
                onChanged: (v) => AppLang().value = v ?? 'system',
                child: Column(
                  children: [
                    RadioListTile<String>(
                      title: Text(S.t('langSystem')),
                      value: 'system',
                    ),
                    RadioListTile<String>(
                      title: Text(S.t('langKo')),
                      value: 'ko',
                    ),
                    RadioListTile<String>(
                      title: Text(S.t('langEn')),
                      value: 'en',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
