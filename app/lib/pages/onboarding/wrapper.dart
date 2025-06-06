import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:omi/backend/auth.dart';
import 'package:omi/backend/preferences.dart';
import 'package:omi/backend/schema/bt_device/bt_device.dart';
import 'package:omi/pages/home/page.dart';
import 'package:omi/pages/onboarding/auth.dart';
import 'package:omi/pages/onboarding/find_device/page.dart';
import 'package:omi/pages/onboarding/name/name_widget.dart';
import 'package:omi/pages/onboarding/permissions/permissions_widget.dart';
import 'package:omi/pages/onboarding/primary_language/primary_language_widget.dart';
import 'package:omi/pages/onboarding/speech_profile_widget.dart';
import 'package:omi/pages/onboarding/welcome/page.dart';
import 'package:omi/providers/home_provider.dart';
import 'package:omi/providers/onboarding_provider.dart';
import 'package:omi/services/services.dart';
import 'package:omi/utils/analytics/intercom.dart';
import 'package:omi/utils/analytics/mixpanel.dart';
import 'package:omi/utils/other/temp.dart';
import 'package:omi/widgets/device_widget.dart';
import 'package:provider/provider.dart';

class OnboardingWrapper extends StatefulWidget {
  const OnboardingWrapper({super.key});

  @override
  State<OnboardingWrapper> createState() => _OnboardingWrapperState();
}

class _OnboardingWrapperState extends State<OnboardingWrapper> with TickerProviderStateMixin {
  // Onboarding page indices
  static const int kAuthPage = 0;
  static const int kNamePage = 1;
  static const int kPrimaryLanguagePage = 2;
  static const int kPermissionsPage = 3;
  static const int kWelcomePage = 4;
  static const int kFindDevicesPage = 5;
  static const int kSpeechProfilePage = 6;

  // Special index values used in comparisons
  static const List<int> kHiddenHeaderPages = [-1, 5, 6];

  TabController? _controller;
  bool get hasSpeechProfile => SharedPreferencesUtil().hasSpeakerProfile;

  @override
  void initState() {
    //TODO: Change from tab controller to default controller and use provider (part of instabug cleanup) @mdmohsin7
    _controller = TabController(length: hasSpeechProfile ? 6 : 7, vsync: this);
    _controller!.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (isSignedIn()) {
        // && !SharedPreferencesUtil().onboardingCompleted
        if (mounted) {
          context.read<HomeProvider>().setupHasSpeakerProfile();
          _goNext();
        }
      }
    });
    super.initState();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  _goNext() {
    if (_controller!.index < _controller!.length - 1) {
      _controller!.animateTo(_controller!.index + 1);
    } else {
      routeToPage(context, const HomePageWrapper(), replace: true);
    }
  }

  // TODO: use connection directly
  Future<BleAudioCodec> _getAudioCodec(String deviceId) async {
    var connection = await ServiceManager.instance().device.ensureConnection(deviceId);
    if (connection == null) {
      return BleAudioCodec.pcm8;
    }
    return connection.getAudioCodec();
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> pages = [
      // TODO: if connected already, stop animation and display battery
      AuthComponent(
        onSignIn: () {
          SharedPreferencesUtil().hasOmiDevice = true;
          SharedPreferencesUtil().verifiedPersonaId = null;
          MixpanelManager().onboardingStepCompleted('Auth');
          context.read<HomeProvider>().setupHasSpeakerProfile();
          IntercomManager.instance.intercom.loginIdentifiedUser(
            userId: SharedPreferencesUtil().uid,
          );
          if (SharedPreferencesUtil().onboardingCompleted) {
            routeToPage(context, const HomePageWrapper(), replace: true);
          } else {
            _goNext();
          }
        },
      ),
      NameWidget(goNext: () {
        _goNext();
        IntercomManager.instance.updateUser(
          FirebaseAuth.instance.currentUser!.email,
          FirebaseAuth.instance.currentUser!.displayName,
          FirebaseAuth.instance.currentUser!.uid,
        );
        MixpanelManager().onboardingStepCompleted('Name');
      }),
      PrimaryLanguageWidget(goNext: () {
        _goNext();
        MixpanelManager().onboardingStepCompleted('Primary Language');
      }),
      PermissionsWidget(
        goNext: () {
          _goNext();
          MixpanelManager().onboardingStepCompleted('Permissions');
        },
      ),
      WelcomePage(
        goNext: () {
          _goNext();
          MixpanelManager().onboardingStepCompleted('Welcome');
        },
      ),
      FindDevicesPage(
        isFromOnboarding: true,
        onSkip: () {
          routeToPage(context, const HomePageWrapper(), replace: true);
        },
        goNext: () async {
          var provider = context.read<OnboardingProvider>();
          if (context.read<HomeProvider>().hasSpeakerProfile) {
            // previous users
            routeToPage(context, const HomePageWrapper(), replace: true);
          } else {
            if (provider.deviceId.isEmpty) {
              _goNext();
            } else {
              var codec = await _getAudioCodec(provider.deviceId);
              if (codec == BleAudioCodec.opus) {
                _goNext();
              } else {
                routeToPage(context, const HomePageWrapper(), replace: true);
              }
            }
          }

          MixpanelManager().onboardingStepCompleted('Find Devices');
        },
      ),
    ];

    if (!hasSpeechProfile) {
      pages.addAll([
        SpeechProfileWidget(
          goNext: () {
            routeToPage(context, const HomePageWrapper(), replace: true);
            MixpanelManager().onboardingStepCompleted('Speech Profile');
          },
          onSkip: () {
            routeToPage(context, const HomePageWrapper(), replace: true);
          },
        ),
      ]);
    }

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.primary,
        body: SingleChildScrollView(
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    DeviceAnimationWidget(animatedBackground: _controller!.index != -1),
                    const SizedBox(height: 24),
                    kHiddenHeaderPages.contains(_controller?.index)
                        ? const SizedBox(
                            height: 0,
                          )
                        : Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              _controller!.index == _controller!.length - 1
                                  ? 'Your personal growth journey with AI that listens to your every word.'
                                  : 'Your personal growth journey with AI that listens to your every word.',
                              style: TextStyle(color: Colors.grey.shade300, fontSize: 24),
                              textAlign: TextAlign.center,
                            ),
                          ),
                    SizedBox(
                      height: (_controller!.index == kFindDevicesPage || _controller!.index == kSpeechProfilePage)
                          ? max(MediaQuery.of(context).size.height - 500 - 10,
                              maxHeightWithTextScale(context, _controller!.index))
                          : max(MediaQuery.of(context).size.height - 500 - 30,
                              maxHeightWithTextScale(context, _controller!.index)),
                      child: Padding(
                        padding: EdgeInsets.only(bottom: MediaQuery.sizeOf(context).height <= 700 ? 10 : 64),
                        child: TabBarView(
                          controller: _controller,
                          physics: const NeverScrollableScrollPhysics(),
                          children: pages,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_controller!.index == kWelcomePage)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 40, 16, 0),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: TextButton(
                      onPressed: () {
                        if (_controller!.index == kPermissionsPage) {
                          _controller!.animateTo(_controller!.index + 1);
                        } else {
                          routeToPage(context, const HomePageWrapper(), replace: true);
                        }
                      },
                      child: Text(
                        'Skip',
                        style: TextStyle(color: Colors.grey.shade200),
                      ),
                    ),
                  ),
                ),
              if (_controller!.index > kNamePage)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 40, 0, 0),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: TextButton(
                      onPressed: () {
                        _controller!.animateTo(_controller!.index - 1);
                      },
                      child: Text(
                        'Back',
                        style: TextStyle(color: Colors.grey.shade200),
                      ),
                    ),
                  ),
                ),
              if (_controller!.index != kAuthPage)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 56, 16, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _controller!.length - 1, // Exclude the Auth page from the count
                      (index) {
                        // Calculate the adjusted index
                        int adjustedIndex = index + 1;
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4.0),
                          width: adjustedIndex == _controller!.index ? 12.0 : 8.0,
                          height: adjustedIndex == _controller!.index ? 12.0 : 8.0,
                          decoration: BoxDecoration(
                            color: adjustedIndex <= _controller!.index
                                ? Theme.of(context).colorScheme.secondary
                                : Colors.grey.shade400,
                            shape: BoxShape.circle,
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

double maxHeightWithTextScale(BuildContext context, int index) {
  double textScaleFactor = MediaQuery.of(context).textScaleFactor;
  if (textScaleFactor > 1.0) {
    if (index == _OnboardingWrapperState.kAuthPage) {
      return 200;
    } else {
      return 405;
    }
  } else {
    return 305;
  }
}
