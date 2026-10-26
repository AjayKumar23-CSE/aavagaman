import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Aavagaman Driver'**
  String get appTitle;

  /// No description provided for @appTagline.
  ///
  /// In en, this message translates to:
  /// **'Safar • Aapke Saath'**
  String get appTagline;

  /// No description provided for @splashQuote.
  ///
  /// In en, this message translates to:
  /// **'Har safar ka apna ek maqsad hota hai.'**
  String get splashQuote;

  /// No description provided for @homeStatusOffline.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline'**
  String get homeStatusOffline;

  /// No description provided for @homeStatusGoingOnline.
  ///
  /// In en, this message translates to:
  /// **'Going online…'**
  String get homeStatusGoingOnline;

  /// No description provided for @homeStatusOnline.
  ///
  /// In en, this message translates to:
  /// **'You\'re online'**
  String get homeStatusOnline;

  /// No description provided for @homeStatusReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting…'**
  String get homeStatusReconnecting;

  /// No description provided for @homeStatusGoingOffline.
  ///
  /// In en, this message translates to:
  /// **'Going offline…'**
  String get homeStatusGoingOffline;

  /// No description provided for @homeOfflineHint.
  ///
  /// In en, this message translates to:
  /// **'Switch on to start receiving ride requests.'**
  String get homeOfflineHint;

  /// No description provided for @homeOnlineHint.
  ///
  /// In en, this message translates to:
  /// **'Stay on this screen or lock your phone — requests will ring.'**
  String get homeOnlineHint;

  /// No description provided for @homeReconnectingHint.
  ///
  /// In en, this message translates to:
  /// **'Connection lost. We\'ll put you back online automatically.'**
  String get homeReconnectingHint;

  /// No description provided for @homeOnTripHint.
  ///
  /// In en, this message translates to:
  /// **'You\'re on a trip. Finish it before going offline.'**
  String get homeOnTripHint;

  /// No description provided for @homeSwitchLabel.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get homeSwitchLabel;

  /// No description provided for @homeViewTrip.
  ///
  /// In en, this message translates to:
  /// **'View current trip'**
  String get homeViewTrip;

  /// No description provided for @homeTodayEarnings.
  ///
  /// In en, this message translates to:
  /// **'Today\'s earnings'**
  String get homeTodayEarnings;

  /// No description provided for @homeEarningsNote.
  ///
  /// In en, this message translates to:
  /// **'After commission and GST'**
  String get homeEarningsNote;

  /// No description provided for @homeLocationDenied.
  ///
  /// In en, this message translates to:
  /// **'Allow location access to go online.'**
  String get homeLocationDenied;

  /// No description provided for @homeBackgroundLocationDenied.
  ///
  /// In en, this message translates to:
  /// **'Allow location access \"All the time\" so ride requests reach you while the screen is off.'**
  String get homeBackgroundLocationDenied;

  /// No description provided for @homeNotificationsDenied.
  ///
  /// In en, this message translates to:
  /// **'Allow notifications so you hear ride requests.'**
  String get homeNotificationsDenied;

  /// No description provided for @homeLocationServiceOff.
  ///
  /// In en, this message translates to:
  /// **'Turn on location services to go online.'**
  String get homeLocationServiceOff;

  /// No description provided for @homeNoFix.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t get your location. Move to an open area and try again.'**
  String get homeNoFix;

  /// No description provided for @homeOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get homeOpenSettings;

  /// No description provided for @homeBatteryMenu.
  ///
  /// In en, this message translates to:
  /// **'Battery settings'**
  String get homeBatteryMenu;

  /// No description provided for @homeLocate.
  ///
  /// In en, this message translates to:
  /// **'My location'**
  String get homeLocate;

  /// No description provided for @onlineNotificationTitle.
  ///
  /// In en, this message translates to:
  /// **'You are online'**
  String get onlineNotificationTitle;

  /// No description provided for @onlineNotificationBody.
  ///
  /// In en, this message translates to:
  /// **'Receiving ride requests nearby'**
  String get onlineNotificationBody;

  /// No description provided for @channelRidesName.
  ///
  /// In en, this message translates to:
  /// **'Ride requests'**
  String get channelRidesName;

  /// No description provided for @channelRidesDescription.
  ///
  /// In en, this message translates to:
  /// **'New ride requests (rings loudly)'**
  String get channelRidesDescription;

  /// No description provided for @channelPresenceName.
  ///
  /// In en, this message translates to:
  /// **'Online status'**
  String get channelPresenceName;

  /// No description provided for @channelPresenceDescription.
  ///
  /// In en, this message translates to:
  /// **'Shown while you are online'**
  String get channelPresenceDescription;

  /// No description provided for @offerTitle.
  ///
  /// In en, this message translates to:
  /// **'New ride request'**
  String get offerTitle;

  /// No description provided for @offersTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{New ride request} other{{count} ride requests}}'**
  String offersTitle(int count);

  /// No description provided for @offerPickup.
  ///
  /// In en, this message translates to:
  /// **'Pickup'**
  String get offerPickup;

  /// No description provided for @offerDrop.
  ///
  /// In en, this message translates to:
  /// **'Drop'**
  String get offerDrop;

  /// No description provided for @offerDistance.
  ///
  /// In en, this message translates to:
  /// **'{distance} to pickup'**
  String offerDistance(String distance);

  /// No description provided for @offerFare.
  ///
  /// In en, this message translates to:
  /// **'Fare {range}'**
  String offerFare(String range);

  /// No description provided for @offerAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get offerAccept;

  /// No description provided for @offerReject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get offerReject;

  /// No description provided for @offerExpired.
  ///
  /// In en, this message translates to:
  /// **'This request has expired'**
  String get offerExpired;

  /// No description provided for @offerAccepting.
  ///
  /// In en, this message translates to:
  /// **'Accepting…'**
  String get offerAccepting;

  /// No description provided for @offerNotificationBody.
  ///
  /// In en, this message translates to:
  /// **'{pickup} · tap to view'**
  String offerNotificationBody(String pickup);

  /// No description provided for @tripTitle.
  ///
  /// In en, this message translates to:
  /// **'Navigate to pickup'**
  String get tripTitle;

  /// No description provided for @tripRider.
  ///
  /// In en, this message translates to:
  /// **'Rider'**
  String get tripRider;

  /// No description provided for @tripPickup.
  ///
  /// In en, this message translates to:
  /// **'Pickup'**
  String get tripPickup;

  /// No description provided for @tripDrop.
  ///
  /// In en, this message translates to:
  /// **'Drop'**
  String get tripDrop;

  /// No description provided for @tripNavigate.
  ///
  /// In en, this message translates to:
  /// **'Navigate'**
  String get tripNavigate;

  /// No description provided for @tripCall.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get tripCall;

  /// No description provided for @tripCallHint.
  ///
  /// In en, this message translates to:
  /// **'Calling unlocks when you arrive'**
  String get tripCallHint;

  /// No description provided for @tripCallVia.
  ///
  /// In en, this message translates to:
  /// **'Call via Aavagaman'**
  String get tripCallVia;

  /// No description provided for @tripNumberPrivate.
  ///
  /// In en, this message translates to:
  /// **'Number private · calls go via Aavagaman'**
  String get tripNumberPrivate;

  /// No description provided for @callConnecting.
  ///
  /// In en, this message translates to:
  /// **'Calling you from {number}. Pick up to talk to the rider.'**
  String callConnecting(String number);

  /// No description provided for @callFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t connect the call. Please try again.'**
  String get callFailed;

  /// No description provided for @tripArrived.
  ///
  /// In en, this message translates to:
  /// **'Arrived'**
  String get tripArrived;

  /// No description provided for @tripStart.
  ///
  /// In en, this message translates to:
  /// **'Start trip'**
  String get tripStart;

  /// No description provided for @tripEnd.
  ///
  /// In en, this message translates to:
  /// **'End trip'**
  String get tripEnd;

  /// No description provided for @tripStatusAccepted.
  ///
  /// In en, this message translates to:
  /// **'Head to the pickup'**
  String get tripStatusAccepted;

  /// No description provided for @tripStatusArrived.
  ///
  /// In en, this message translates to:
  /// **'You\'re at the pickup — waiting for the rider'**
  String get tripStatusArrived;

  /// No description provided for @tripStatusStarted.
  ///
  /// In en, this message translates to:
  /// **'Trip in progress'**
  String get tripStatusStarted;

  /// No description provided for @tripStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Trip completed — collect the fare'**
  String get tripStatusCompleted;

  /// No description provided for @tripFare.
  ///
  /// In en, this message translates to:
  /// **'Fare {range}'**
  String tripFare(String range);

  /// No description provided for @tripReassigned.
  ///
  /// In en, this message translates to:
  /// **'This ride was reassigned to another driver.'**
  String get tripReassigned;

  /// No description provided for @tripCancelledByRider.
  ///
  /// In en, this message translates to:
  /// **'The rider cancelled this ride.'**
  String get tripCancelledByRider;

  /// No description provided for @tripEnded.
  ///
  /// In en, this message translates to:
  /// **'This ride has ended.'**
  String get tripEnded;

  /// No description provided for @backToHome.
  ///
  /// In en, this message translates to:
  /// **'Back to home'**
  String get backToHome;

  /// No description provided for @tripNavigateFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open a navigation app.'**
  String get tripNavigateFailed;

  /// No description provided for @tripTitleOnTrip.
  ///
  /// In en, this message translates to:
  /// **'On trip'**
  String get tripTitleOnTrip;

  /// No description provided for @tripTitlePayment.
  ///
  /// In en, this message translates to:
  /// **'Collect payment'**
  String get tripTitlePayment;

  /// No description provided for @tripTitleRate.
  ///
  /// In en, this message translates to:
  /// **'Rate the rider'**
  String get tripTitleRate;

  /// No description provided for @tripStepPickup.
  ///
  /// In en, this message translates to:
  /// **'Pickup'**
  String get tripStepPickup;

  /// No description provided for @tripStepTrip.
  ///
  /// In en, this message translates to:
  /// **'Trip'**
  String get tripStepTrip;

  /// No description provided for @tripStepPayment.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get tripStepPayment;

  /// No description provided for @tripNavigateToDrop.
  ///
  /// In en, this message translates to:
  /// **'Navigate to drop'**
  String get tripNavigateToDrop;

  /// No description provided for @tripOtpLabel.
  ///
  /// In en, this message translates to:
  /// **'Rider\'s 4-digit OTP'**
  String get tripOtpLabel;

  /// No description provided for @tripOtpHint.
  ///
  /// In en, this message translates to:
  /// **'Ask the rider for the code shown in their app.'**
  String get tripOtpHint;

  /// No description provided for @tripEndConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'End the trip?'**
  String get tripEndConfirmTitle;

  /// No description provided for @tripEndConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'End the trip only when the rider has reached the drop.'**
  String get tripEndConfirmBody;

  /// No description provided for @tripCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel ride'**
  String get tripCancel;

  /// No description provided for @tripLocationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t get your location. Check that GPS is on and try again.'**
  String get tripLocationUnavailable;

  /// No description provided for @tripYouCancelled.
  ///
  /// In en, this message translates to:
  /// **'You cancelled this ride. It has gone back to other drivers.'**
  String get tripYouCancelled;

  /// No description provided for @tripNoShowCancelled.
  ///
  /// In en, this message translates to:
  /// **'Ride cancelled as a rider no-show. The rider will be charged the cancellation fee.'**
  String get tripNoShowCancelled;

  /// No description provided for @cancelTitle.
  ///
  /// In en, this message translates to:
  /// **'Why are you cancelling?'**
  String get cancelTitle;

  /// No description provided for @cancelWarning.
  ///
  /// In en, this message translates to:
  /// **'Cancellations count against you: three in a day pauses your account.'**
  String get cancelWarning;

  /// No description provided for @cancelReasonVehicleBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Vehicle breakdown'**
  String get cancelReasonVehicleBreakdown;

  /// No description provided for @cancelReasonRiderNotReachable.
  ///
  /// In en, this message translates to:
  /// **'Rider not reachable'**
  String get cancelReasonRiderNotReachable;

  /// No description provided for @cancelReasonRiderNoShow.
  ///
  /// In en, this message translates to:
  /// **'Rider didn\'t show up'**
  String get cancelReasonRiderNoShow;

  /// No description provided for @cancelReasonWrongPickup.
  ///
  /// In en, this message translates to:
  /// **'Wrong pickup location'**
  String get cancelReasonWrongPickup;

  /// No description provided for @cancelReasonOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get cancelReasonOther;

  /// No description provided for @cancelNoShowWait.
  ///
  /// In en, this message translates to:
  /// **'Available after waiting {minutes} min at the pickup'**
  String cancelNoShowWait(int minutes);

  /// No description provided for @cancelOtherHint.
  ///
  /// In en, this message translates to:
  /// **'Tell us what happened'**
  String get cancelOtherHint;

  /// No description provided for @cancelConfirm.
  ///
  /// In en, this message translates to:
  /// **'Cancel ride'**
  String get cancelConfirm;

  /// No description provided for @cancelKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep ride'**
  String get cancelKeep;

  /// No description provided for @paymentAmountDue.
  ///
  /// In en, this message translates to:
  /// **'Amount to collect'**
  String get paymentAmountDue;

  /// No description provided for @paymentFare.
  ///
  /// In en, this message translates to:
  /// **'Trip fare'**
  String get paymentFare;

  /// No description provided for @paymentPreviousFee.
  ///
  /// In en, this message translates to:
  /// **'Earlier cancellation fee'**
  String get paymentPreviousFee;

  /// No description provided for @paymentTrip.
  ///
  /// In en, this message translates to:
  /// **'{distance} · {duration}'**
  String paymentTrip(String distance, String duration);

  /// No description provided for @paymentMethodCash.
  ///
  /// In en, this message translates to:
  /// **'Rider pays cash'**
  String get paymentMethodCash;

  /// No description provided for @paymentMethodOnline.
  ///
  /// In en, this message translates to:
  /// **'Rider pays online'**
  String get paymentMethodOnline;

  /// No description provided for @paymentCashCollected.
  ///
  /// In en, this message translates to:
  /// **'Cash collected'**
  String get paymentCashCollected;

  /// No description provided for @paymentCashConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Cash collected?'**
  String get paymentCashConfirmTitle;

  /// No description provided for @paymentCashConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Confirm you received {amount} in cash from the rider.'**
  String paymentCashConfirmBody(String amount);

  /// No description provided for @paymentWaitingOnline.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the rider\'s online payment…'**
  String get paymentWaitingOnline;

  /// No description provided for @paymentOnlineFallback.
  ///
  /// In en, this message translates to:
  /// **'If the rider pays you in cash instead, tap Cash collected once you have it.'**
  String get paymentOnlineFallback;

  /// No description provided for @paymentReceived.
  ///
  /// In en, this message translates to:
  /// **'Payment received'**
  String get paymentReceived;

  /// No description provided for @rateTitle.
  ///
  /// In en, this message translates to:
  /// **'How was the rider?'**
  String get rateTitle;

  /// No description provided for @rateSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get rateSubmit;

  /// No description provided for @rateSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get rateSkip;

  /// No description provided for @rateFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send your rating.'**
  String get rateFailed;

  /// No description provided for @sosTooltip.
  ///
  /// In en, this message translates to:
  /// **'SOS'**
  String get sosTooltip;

  /// No description provided for @sosTitle.
  ///
  /// In en, this message translates to:
  /// **'Emergency?'**
  String get sosTitle;

  /// No description provided for @sosBody.
  ///
  /// In en, this message translates to:
  /// **'This calls 112 and alerts our support team with your location.'**
  String get sosBody;

  /// No description provided for @sosConfirm.
  ///
  /// In en, this message translates to:
  /// **'Call 112'**
  String get sosConfirm;

  /// No description provided for @sosAlerted.
  ///
  /// In en, this message translates to:
  /// **'Our support team has been alerted.'**
  String get sosAlerted;

  /// No description provided for @sosFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t alert the support team. Call 112 if you haven\'t already.'**
  String get sosFailed;

  /// No description provided for @menuEarnings.
  ///
  /// In en, this message translates to:
  /// **'Earnings'**
  String get menuEarnings;

  /// No description provided for @menuHistory.
  ///
  /// In en, this message translates to:
  /// **'Trip history'**
  String get menuHistory;

  /// No description provided for @earningsTitle.
  ///
  /// In en, this message translates to:
  /// **'Earnings'**
  String get earningsTitle;

  /// No description provided for @earningsToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get earningsToday;

  /// No description provided for @earningsWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get earningsWeek;

  /// No description provided for @earningsTrips.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 trip} other{{count} trips}}'**
  String earningsTrips(int count);

  /// No description provided for @earningsNet.
  ///
  /// In en, this message translates to:
  /// **'You earn'**
  String get earningsNet;

  /// No description provided for @earningsGross.
  ///
  /// In en, this message translates to:
  /// **'Fares'**
  String get earningsGross;

  /// No description provided for @earningsCommission.
  ///
  /// In en, this message translates to:
  /// **'Commission'**
  String get earningsCommission;

  /// No description provided for @earningsGst.
  ///
  /// In en, this message translates to:
  /// **'GST'**
  String get earningsGst;

  /// No description provided for @earningsCash.
  ///
  /// In en, this message translates to:
  /// **'Cash collected'**
  String get earningsCash;

  /// No description provided for @earningsOnline.
  ///
  /// In en, this message translates to:
  /// **'Paid online'**
  String get earningsOnline;

  /// No description provided for @earningsRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent trips'**
  String get earningsRecent;

  /// No description provided for @earningsSettlementNote.
  ///
  /// In en, this message translates to:
  /// **'Settlements are prepared every Monday for the previous week (Monday–Sunday).'**
  String get earningsSettlementNote;

  /// No description provided for @earningsTripLine.
  ///
  /// In en, this message translates to:
  /// **'Fare {fare} · Commission {commission} · GST {gst}'**
  String earningsTripLine(String fare, String commission, String gst);

  /// No description provided for @loadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this. Check your connection.'**
  String get loadFailed;

  /// No description provided for @historyTitle.
  ///
  /// In en, this message translates to:
  /// **'Trip history'**
  String get historyTitle;

  /// No description provided for @historyEmpty.
  ///
  /// In en, this message translates to:
  /// **'No trips yet.'**
  String get historyEmpty;

  /// No description provided for @historyLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get historyLoadMore;

  /// No description provided for @historyStatusPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get historyStatusPaid;

  /// No description provided for @historyStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Awaiting payment'**
  String get historyStatusCompleted;

  /// No description provided for @historyStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get historyStatusCancelled;

  /// No description provided for @historyStatusActive.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get historyStatusActive;

  /// No description provided for @historyCancelledByYou.
  ///
  /// In en, this message translates to:
  /// **'Cancelled by you'**
  String get historyCancelledByYou;

  /// No description provided for @historyCancelledByRider.
  ///
  /// In en, this message translates to:
  /// **'Cancelled by the rider'**
  String get historyCancelledByRider;

  /// No description provided for @historyCancelledByAdmin.
  ///
  /// In en, this message translates to:
  /// **'Cancelled by support'**
  String get historyCancelledByAdmin;

  /// No description provided for @batteryTitle.
  ///
  /// In en, this message translates to:
  /// **'Keep ride requests coming'**
  String get batteryTitle;

  /// No description provided for @batteryIntro.
  ///
  /// In en, this message translates to:
  /// **'Android may put this app to sleep while your screen is off, so ride requests stop arriving. Turn off battery optimisation for Ride Driver once.'**
  String get batteryIntro;

  /// No description provided for @batteryGenericSteps.
  ///
  /// In en, this message translates to:
  /// **'Open the battery settings for Ride Driver and choose \"Don\'t optimise\" or \"Unrestricted\".'**
  String get batteryGenericSteps;

  /// No description provided for @batteryBrandNote.
  ///
  /// In en, this message translates to:
  /// **'On your {brand} phone:'**
  String batteryBrandNote(String brand);

  /// No description provided for @batteryXiaomi.
  ///
  /// In en, this message translates to:
  /// **'Settings → Apps → Manage apps → Ride Driver → Battery saver: No restrictions. Also enable Autostart, and lock the app in Recents (pull down on its card).'**
  String get batteryXiaomi;

  /// No description provided for @batteryVivo.
  ///
  /// In en, this message translates to:
  /// **'Settings → Battery → Background power consumption management → Ride Driver: Allow. Also enable Autostart under i Manager → App manager.'**
  String get batteryVivo;

  /// No description provided for @batteryOppo.
  ///
  /// In en, this message translates to:
  /// **'Settings → Battery → More settings → Optimise battery use → Ride Driver: Don\'t optimise. Enable \"Allow auto startup\" under App management.'**
  String get batteryOppo;

  /// No description provided for @batteryRealme.
  ///
  /// In en, this message translates to:
  /// **'Settings → Battery → App battery management → Ride Driver: Allow background activity. Enable auto startup under App management.'**
  String get batteryRealme;

  /// No description provided for @batterySamsung.
  ///
  /// In en, this message translates to:
  /// **'Settings → Apps → Ride Driver → Battery: Unrestricted. In Settings → Battery → Background usage limits, make sure Ride Driver is not in \"Sleeping apps\".'**
  String get batterySamsung;

  /// No description provided for @batteryOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open battery settings'**
  String get batteryOpenSettings;

  /// No description provided for @batteryOpenAppSettings.
  ///
  /// In en, this message translates to:
  /// **'Open app settings'**
  String get batteryOpenAppSettings;

  /// No description provided for @batteryDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get batteryDone;

  /// No description provided for @batteryLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get batteryLater;

  /// No description provided for @phoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your mobile number'**
  String get phoneTitle;

  /// No description provided for @phoneSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We\'ll send you a 6-digit code to log in or sign up as a driver.'**
  String get phoneSubtitle;

  /// No description provided for @phoneConsent.
  ///
  /// In en, this message translates to:
  /// **'We\'ll text you a one-time code. Standard SMS charges may apply.'**
  String get phoneConsent;

  /// No description provided for @phoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Mobile number'**
  String get phoneLabel;

  /// No description provided for @invalidPhone.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid 10-digit Indian mobile number'**
  String get invalidPhone;

  /// No description provided for @continueLabel.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// No description provided for @otpTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the code'**
  String get otpTitle;

  /// No description provided for @otpSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sent by SMS to {phone}'**
  String otpSubtitle(String phone);

  /// No description provided for @resendIn.
  ///
  /// In en, this message translates to:
  /// **'Resend code in {time}'**
  String resendIn(String time);

  /// No description provided for @resend.
  ///
  /// In en, this message translates to:
  /// **'Resend code'**
  String get resend;

  /// No description provided for @codeResent.
  ///
  /// In en, this message translates to:
  /// **'A new code is on its way'**
  String get codeResent;

  /// No description provided for @changeNumber.
  ///
  /// In en, this message translates to:
  /// **'Change number'**
  String get changeNumber;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @networkError.
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach the server. Check your connection and try again.'**
  String get networkError;

  /// No description provided for @genericError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get genericError;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @homeGreeting.
  ///
  /// In en, this message translates to:
  /// **'Hi {name}'**
  String homeGreeting(String name);

  /// No description provided for @homeDocsAttention.
  ///
  /// In en, this message translates to:
  /// **'Some documents need attention before you can go online.'**
  String get homeDocsAttention;

  /// No description provided for @homeDocsAction.
  ///
  /// In en, this message translates to:
  /// **'View documents'**
  String get homeDocsAction;

  /// No description provided for @registerTitle.
  ///
  /// In en, this message translates to:
  /// **'Your details'**
  String get registerTitle;

  /// No description provided for @registerIntro.
  ///
  /// In en, this message translates to:
  /// **'Tell us about you and your car. You\'ll upload documents next.'**
  String get registerIntro;

  /// No description provided for @registerRejected.
  ///
  /// In en, this message translates to:
  /// **'Your application was not approved. Please correct your details and submit again.'**
  String get registerRejected;

  /// No description provided for @reviewerNoteLabel.
  ///
  /// In en, this message translates to:
  /// **'Note from our team: {note}'**
  String reviewerNoteLabel(String note);

  /// No description provided for @sectionDriver.
  ///
  /// In en, this message translates to:
  /// **'Driver'**
  String get sectionDriver;

  /// No description provided for @sectionVehicle.
  ///
  /// In en, this message translates to:
  /// **'Vehicle'**
  String get sectionVehicle;

  /// No description provided for @vehicleTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Vehicle type'**
  String get vehicleTypeLabel;

  /// No description provided for @vehicleBike.
  ///
  /// In en, this message translates to:
  /// **'Bike'**
  String get vehicleBike;

  /// No description provided for @vehicleAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get vehicleAuto;

  /// No description provided for @vehicleMini.
  ///
  /// In en, this message translates to:
  /// **'Mini'**
  String get vehicleMini;

  /// No description provided for @vehicleSedan.
  ///
  /// In en, this message translates to:
  /// **'Sedan'**
  String get vehicleSedan;

  /// No description provided for @nameLabel.
  ///
  /// In en, this message translates to:
  /// **'Full name (as on licence)'**
  String get nameLabel;

  /// No description provided for @licenceNoLabel.
  ///
  /// In en, this message translates to:
  /// **'Driving licence number'**
  String get licenceNoLabel;

  /// No description provided for @licenceExpiryLabel.
  ///
  /// In en, this message translates to:
  /// **'Licence valid until'**
  String get licenceExpiryLabel;

  /// No description provided for @dateOfBirthLabel.
  ///
  /// In en, this message translates to:
  /// **'Date of birth (as on your licence)'**
  String get dateOfBirthLabel;

  /// No description provided for @dateOfBirthTooYoung.
  ///
  /// In en, this message translates to:
  /// **'You must be at least 18 years old to drive'**
  String get dateOfBirthTooYoung;

  /// No description provided for @regNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Registration number'**
  String get regNumberLabel;

  /// No description provided for @regNumberHint.
  ///
  /// In en, this message translates to:
  /// **'DL01AB1234'**
  String get regNumberHint;

  /// No description provided for @makeLabel.
  ///
  /// In en, this message translates to:
  /// **'Make'**
  String get makeLabel;

  /// No description provided for @makeHint.
  ///
  /// In en, this message translates to:
  /// **'Maruti Suzuki'**
  String get makeHint;

  /// No description provided for @modelLabel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get modelLabel;

  /// No description provided for @modelHint.
  ///
  /// In en, this message translates to:
  /// **'Dzire'**
  String get modelHint;

  /// No description provided for @colourLabel.
  ///
  /// In en, this message translates to:
  /// **'Colour'**
  String get colourLabel;

  /// No description provided for @fuelLabel.
  ///
  /// In en, this message translates to:
  /// **'Fuel type'**
  String get fuelLabel;

  /// No description provided for @fuelPetrol.
  ///
  /// In en, this message translates to:
  /// **'Petrol'**
  String get fuelPetrol;

  /// No description provided for @fuelDiesel.
  ///
  /// In en, this message translates to:
  /// **'Diesel'**
  String get fuelDiesel;

  /// No description provided for @fuelCng.
  ///
  /// In en, this message translates to:
  /// **'CNG'**
  String get fuelCng;

  /// No description provided for @fuelEv.
  ///
  /// In en, this message translates to:
  /// **'Electric'**
  String get fuelEv;

  /// No description provided for @fieldRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get fieldRequired;

  /// No description provided for @invalidLicenceNo.
  ///
  /// In en, this message translates to:
  /// **'8–20 letters and digits'**
  String get invalidLicenceNo;

  /// No description provided for @invalidRegNumber.
  ///
  /// In en, this message translates to:
  /// **'Looks like DL01AB1234'**
  String get invalidRegNumber;

  /// No description provided for @dateExpired.
  ///
  /// In en, this message translates to:
  /// **'This date has already passed'**
  String get dateExpired;

  /// No description provided for @selectDate.
  ///
  /// In en, this message translates to:
  /// **'Select date'**
  String get selectDate;

  /// No description provided for @submit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submit;

  /// No description provided for @documentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get documentsTitle;

  /// No description provided for @documentsIntro.
  ///
  /// In en, this message translates to:
  /// **'Upload a clear photo of each document. We\'ll review them within 1–2 working days.'**
  String get documentsIntro;

  /// No description provided for @docDrivingLicence.
  ///
  /// In en, this message translates to:
  /// **'Driving licence'**
  String get docDrivingLicence;

  /// No description provided for @docRc.
  ///
  /// In en, this message translates to:
  /// **'Registration certificate (RC)'**
  String get docRc;

  /// No description provided for @docInsurance.
  ///
  /// In en, this message translates to:
  /// **'Vehicle insurance'**
  String get docInsurance;

  /// No description provided for @docPermit.
  ///
  /// In en, this message translates to:
  /// **'Permit'**
  String get docPermit;

  /// No description provided for @docIdProof.
  ///
  /// In en, this message translates to:
  /// **'ID proof (Aadhaar, PAN or voter ID)'**
  String get docIdProof;

  /// No description provided for @docSelfie.
  ///
  /// In en, this message translates to:
  /// **'Selfie'**
  String get docSelfie;

  /// No description provided for @docFitness.
  ///
  /// In en, this message translates to:
  /// **'Fitness certificate'**
  String get docFitness;

  /// No description provided for @docOptional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get docOptional;

  /// No description provided for @docStatusNotUploaded.
  ///
  /// In en, this message translates to:
  /// **'Not uploaded'**
  String get docStatusNotUploaded;

  /// No description provided for @docStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Under review'**
  String get docStatusPending;

  /// No description provided for @docStatusApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get docStatusApproved;

  /// No description provided for @docStatusRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get docStatusRejected;

  /// No description provided for @docStatusExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get docStatusExpired;

  /// No description provided for @docExpires.
  ///
  /// In en, this message translates to:
  /// **'Valid until {date}'**
  String docExpires(String date);

  /// No description provided for @docUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get docUpload;

  /// No description provided for @docReupload.
  ///
  /// In en, this message translates to:
  /// **'Re-upload'**
  String get docReupload;

  /// No description provided for @documentsContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get documentsContinue;

  /// No description provided for @documentsRemaining.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 document left to upload} other{{count} documents left to upload}}'**
  String documentsRemaining(int count);

  /// No description provided for @uploadTitle.
  ///
  /// In en, this message translates to:
  /// **'Upload {doc}'**
  String uploadTitle(String doc);

  /// No description provided for @uploadHintSelfie.
  ///
  /// In en, this message translates to:
  /// **'Take a clear photo of your face in good light. No sunglasses or cap.'**
  String get uploadHintSelfie;

  /// No description provided for @uploadHintDocument.
  ///
  /// In en, this message translates to:
  /// **'Place the document on a flat surface. All four corners and the text must be readable.'**
  String get uploadHintDocument;

  /// No description provided for @uploadCamera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get uploadCamera;

  /// No description provided for @uploadGallery.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get uploadGallery;

  /// No description provided for @uploadExpiryLabel.
  ///
  /// In en, this message translates to:
  /// **'Valid until'**
  String get uploadExpiryLabel;

  /// No description provided for @uploadIdLast4Label.
  ///
  /// In en, this message translates to:
  /// **'Last 4 digits of the ID number'**
  String get uploadIdLast4Label;

  /// No description provided for @uploadIdLast4Help.
  ///
  /// In en, this message translates to:
  /// **'We only store the last 4 digits.'**
  String get uploadIdLast4Help;

  /// No description provided for @uploadIdLast4Invalid.
  ///
  /// In en, this message translates to:
  /// **'Enter exactly 4 digits'**
  String get uploadIdLast4Invalid;

  /// No description provided for @uploadPickFirst.
  ///
  /// In en, this message translates to:
  /// **'Take or choose a photo first'**
  String get uploadPickFirst;

  /// No description provided for @uploadPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing photo…'**
  String get uploadPreparing;

  /// No description provided for @uploadSending.
  ///
  /// In en, this message translates to:
  /// **'Uploading…'**
  String get uploadSending;

  /// No description provided for @uploadButton.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get uploadButton;

  /// No description provided for @uploadRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry upload'**
  String get uploadRetry;

  /// No description provided for @uploadDone.
  ///
  /// In en, this message translates to:
  /// **'Document uploaded'**
  String get uploadDone;

  /// No description provided for @uploadPhotoError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read that photo. Try another one.'**
  String get uploadPhotoError;

  /// No description provided for @pendingTitle.
  ///
  /// In en, this message translates to:
  /// **'Verification'**
  String get pendingTitle;

  /// No description provided for @pendingHeadline.
  ///
  /// In en, this message translates to:
  /// **'Your profile is under review'**
  String get pendingHeadline;

  /// No description provided for @pendingBody.
  ///
  /// In en, this message translates to:
  /// **'We\'ll let you know as soon as you\'re approved. This usually takes 1–2 working days. Pull down to check again.'**
  String get pendingBody;

  /// No description provided for @pendingNeedsAttention.
  ///
  /// In en, this message translates to:
  /// **'Needs your attention'**
  String get pendingNeedsAttention;

  /// No description provided for @pendingNotUploaded.
  ///
  /// In en, this message translates to:
  /// **'Not uploaded yet'**
  String get pendingNotUploaded;

  /// No description provided for @pendingFixDocuments.
  ///
  /// In en, this message translates to:
  /// **'Fix documents'**
  String get pendingFixDocuments;

  /// No description provided for @pendingAllDocuments.
  ///
  /// In en, this message translates to:
  /// **'Your documents'**
  String get pendingAllDocuments;

  /// No description provided for @pendingRefreshFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check your status. Pull down to try again.'**
  String get pendingRefreshFailed;

  /// No description provided for @suspendedTitle.
  ///
  /// In en, this message translates to:
  /// **'Account paused'**
  String get suspendedTitle;

  /// No description provided for @suspendedHeadline.
  ///
  /// In en, this message translates to:
  /// **'Account paused, contact support'**
  String get suspendedHeadline;

  /// No description provided for @suspendedBody.
  ///
  /// In en, this message translates to:
  /// **'You can\'t take rides right now. Please contact our support team to resolve this.'**
  String get suspendedBody;

  /// No description provided for @checkAgain.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get checkAgain;

  /// No description provided for @menuProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile, vehicle & documents'**
  String get menuProfile;

  /// No description provided for @menuHelp.
  ///
  /// In en, this message translates to:
  /// **'Help & support'**
  String get menuHelp;

  /// No description provided for @menuPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get menuPrivacy;

  /// No description provided for @menuLogout.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get menuLogout;

  /// No description provided for @logoutConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Log out?'**
  String get logoutConfirmTitle;

  /// No description provided for @logoutConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'You\'ll need a new code to log in again.'**
  String get logoutConfirmBody;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// No description provided for @profilePhone.
  ///
  /// In en, this message translates to:
  /// **'Mobile number'**
  String get profilePhone;

  /// No description provided for @profileRating.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get profileRating;

  /// No description provided for @profileStatus.
  ///
  /// In en, this message translates to:
  /// **'Verification'**
  String get profileStatus;

  /// No description provided for @statusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending review'**
  String get statusPending;

  /// No description provided for @statusApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get statusApproved;

  /// No description provided for @statusRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get statusRejected;

  /// No description provided for @statusSuspended.
  ///
  /// In en, this message translates to:
  /// **'Suspended'**
  String get statusSuspended;

  /// No description provided for @profileNoVehicle.
  ///
  /// In en, this message translates to:
  /// **'No vehicle added yet'**
  String get profileNoVehicle;

  /// No description provided for @profileDocuments.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get profileDocuments;

  /// No description provided for @helpTitle.
  ///
  /// In en, this message translates to:
  /// **'Help & support'**
  String get helpTitle;

  /// No description provided for @helpIntro.
  ///
  /// In en, this message translates to:
  /// **'Questions about onboarding, documents or payouts? Contact driver support:'**
  String get helpIntro;

  /// No description provided for @helpPhoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get helpPhoneLabel;

  /// No description provided for @helpPhone.
  ///
  /// In en, this message translates to:
  /// **'+91 00000 00000'**
  String get helpPhone;

  /// No description provided for @helpEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get helpEmailLabel;

  /// No description provided for @helpEmail.
  ///
  /// In en, this message translates to:
  /// **'drivers@example.com'**
  String get helpEmail;

  /// No description provided for @helpHours.
  ///
  /// In en, this message translates to:
  /// **'Support hours: 8 am – 10 pm IST, every day.'**
  String get helpHours;

  /// No description provided for @privacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get privacyTitle;

  /// No description provided for @privacyBody.
  ///
  /// In en, this message translates to:
  /// **'This is a placeholder privacy policy. The final policy will explain what we collect from drivers (mobile number, name, date of birth, licence and vehicle details, document photos, the last 4 digits of your ID, trip locations and earnings), why we collect it (to verify drivers, arrange rides, keep riders and drivers safe, settle payments and meet legal requirements), how long we keep it, and how to ask for a copy or deletion of your data.\n\nDocument photos are stored privately and are only visible to our verification team.'**
  String get privacyBody;

  /// No description provided for @homeEarningsSummary.
  ///
  /// In en, this message translates to:
  /// **'{amount} · {trips}'**
  String homeEarningsSummary(String amount, String trips);

  /// No description provided for @homeEarningsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'—'**
  String get homeEarningsUnavailable;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
