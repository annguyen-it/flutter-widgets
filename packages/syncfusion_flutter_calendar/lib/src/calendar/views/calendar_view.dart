import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:syncfusion_flutter_core/core.dart';
import 'package:syncfusion_flutter_core/core_internal.dart';
import 'package:syncfusion_flutter_core/localizations.dart';
import 'package:syncfusion_flutter_core/theme.dart';

import '../appointment_engine/appointment_helper.dart';
import '../appointment_engine/recurrence_helper.dart';
import '../appointment_layout/allday_appointment_layout.dart';
import '../appointment_layout/appointment_layout.dart';
import '../common/calendar_controller.dart';
import '../common/calendar_view_helper.dart';
import '../common/date_time_engine.dart';
import '../common/enums.dart';
import '../resource_view/calendar_resource.dart';
import '../settings/month_view_settings.dart';
import '../settings/time_region.dart';
import '../settings/time_slot_view_settings.dart';
import '../settings/view_header_style.dart';
import '../settings/week_number_style.dart';
import '../sfcalendar.dart';
import '../views/day_view.dart';
import '../views/month_view.dart';
import '../views/timeline_view.dart';

/// All day appointment views default height
const double _kAllDayLayoutHeight = 60;

/// Holds the looping widget for calendar view(time slot, month, timeline and
/// appointment views) widgets of calendar widget.
@immutable
class CustomCalendarScrollView extends StatefulWidget {
  /// Constructor to create the calendar scroll view for holding calendar
  /// view(time slot, month, timeline and appointment views) widgets of
  /// calendar widget.
  const CustomCalendarScrollView(
      this.calendar,
      this.view,
      this.width,
      this.height,
      this.agendaSelectedDate,
      this.locale,
      this.calendarTheme,
      this.specialRegions,
      this.blackoutDates,
      this.controller,
      this.removePicker,
      this.resourcePanelScrollController,
      this.resourceCollection,
      this.textScaleFactor,
      this.fadeInController,
      this.minDate,
      this.maxDate,
      this.localizations,
      this.updateCalendarState,
      this.getCalendarState,
      {Key? key})
      : super(key: key);

  /// Holds the calendar instance used to get the calendar properties.
  final SfCalendar calendar;

  /// Holds the current calendar view of the calendar widget.
  final CalendarView view;

  /// Defines the width of the calendar scroll view widget.
  final double width;

  /// Defines the height of the calendar scroll view widget.
  final double height;

  /// Defines the locale of the calendar.
  final String locale;

  /// Holds the theme data value for calendar.
  final SfCalendarThemeData calendarTheme;

  /// Holds the calendar controller for the calendar widget.
  final CalendarController controller;

  /// Used to update the calendar state details.
  final UpdateCalendarState updateCalendarState;

  /// Used to get the calendar state details.
  final UpdateCalendarState getCalendarState;

  /// Used to remove the calendar header picker.
  final VoidCallback removePicker;

  /// Holds the agenda selected date value and the value updated on month cell
  /// selection and it set to null on month appointment selection.
  final ValueNotifier<DateTime?> agendaSelectedDate;

  /// Holds the special time region of calendar widget.
  final List<TimeRegion>? specialRegions;

  /// Used to get the resource panel scroll position.
  final ScrollController? resourcePanelScrollController;

  /// Collection used to store the resource collection and check the collection
  /// manipulations(add, remove, reset).
  final List<CalendarResource>? resourceCollection;

  /// Defines the scale factor for the calendar widget.
  final double textScaleFactor;

  /// Holds the blackout dates collection of calendar.
  final List<DateTime>? blackoutDates;

  /// Used to animate the calendar views while navigation and view switching.
  final AnimationController? fadeInController;

  /// Defines the min date of the calendar.
  final DateTime minDate;

  /// Defines the max date of the calendar.
  final DateTime maxDate;

  /// Holds the localization data of the calendar widget.
  final SfLocalizations localizations;

  /// Updates the focus to the custom scroll view element.
  void updateFocus() {
    if (key == null) {
      return;
    }

    // ignore: avoid_as
    final GlobalKey scrollViewKey = key! as GlobalKey;
    final Object? currentState = scrollViewKey.currentState;
    if (currentState == null) {
      return;
    }

    final _CustomCalendarScrollViewState state =
        // ignore: avoid_as
        currentState as _CustomCalendarScrollViewState;
    if (!state._focusNode.hasFocus) {
      state._focusNode.requestFocus();
    }
  }

  /// Update the scroll position when the display date time changes.
  void updateScrollPosition() {
    if (key == null) {
      return;
    }

    // ignore: avoid_as
    final GlobalKey scrollViewKey = key! as GlobalKey;
    final Object? currentState = scrollViewKey.currentState;
    if (currentState == null) {
      return;
    }

    final _CustomCalendarScrollViewState state =
        // ignore: avoid_as
        currentState as _CustomCalendarScrollViewState;
    state._updateMoveToDate();
  }

  @override
  _CustomCalendarScrollViewState createState() => _CustomCalendarScrollViewState();
}

class _CustomCalendarScrollViewState extends State<CustomCalendarScrollView> with TickerProviderStateMixin {
  // three views to arrange the view in vertical/horizontal direction and handle the swiping
  late _CalendarView _currentView, _nextView, _previousView;

  // the three children which to be added into the layout
  final List<_CalendarView> _children = <_CalendarView>[];

  // holds the index of the current displaying view
  int _currentChildIndex = 1;

  // _scrollStartPosition contains the touch movement starting position
  late double _scrollStartPosition;

  // _position contains distance that the view swiped
  double _position = 0;

  // animation controller to control the animation
  late AnimationController _animationController;

  // animation handled for the view swiping
  late Animation<double> _animation;

  // tween animation to handle the animation
  final Tween<double> _tween = Tween<double>(begin: 0.0, end: 0.1);

  // Three visible dates for the three views, the dates will updated based on
  // the swiping in the swipe end currentViewVisibleDates which stores the
  // visible dates of the current displaying view
  late List<DateTime> _visibleDates, _previousViewVisibleDates, _nextViewVisibleDates, _currentViewVisibleDates;

  /// keys maintained to access the data and methods from the calendar view
  /// class.
  final GlobalKey<_CalendarViewState> _previousViewKey = GlobalKey<_CalendarViewState>(),
      _currentViewKey = GlobalKey<_CalendarViewState>(),
      _nextViewKey = GlobalKey<_CalendarViewState>();

  final UpdateCalendarStateDetails _updateCalendarStateDetails = UpdateCalendarStateDetails();

  /// Collection used to store the special regions and
  /// check the special regions manipulations.
  List<TimeRegion>? _timeRegions;

  /// The variable stores the timeline view scroll start position used to
  /// decide the scroll as timeline scroll or scroll view on scroll update.
  double _timelineScrollStartPosition = 0;

  /// The variable used to store the scroll start position to calculate the
  /// scroll difference on scroll update.
  double _timelineStartPosition = 0;

  /// Boolean value used to trigger the horizontal end animation when user
  /// stops the scroll at middle.
  bool _isNeedTimelineScrollEnd = false;

  /// Used to perform the drag or scroll in timeline view.
  Drag? _drag;

  final FocusScopeNode _focusNode = FocusScopeNode();

  @override
  void initState() {
    widget.controller.forward = _moveToNextViewWithAnimation;
    widget.controller.backward = _moveToPreviousViewWithAnimation;

    _currentChildIndex = 1;
    _updateVisibleDates();
    _animationController = AnimationController(
        duration: const Duration(milliseconds: 250), vsync: this, animationBehavior: AnimationBehavior.normal);
    _animation = _tween.animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.ease,
    ))
      ..addListener(animationListener);

    _timeRegions = CalendarViewHelper.cloneList(widget.specialRegions);

    super.initState();
  }

  @override
  void didUpdateWidget(CustomCalendarScrollView oldWidget) {
    if (oldWidget.controller != widget.controller) {
      widget.controller.forward = _moveToNextViewWithAnimation;
      widget.controller.backward = _moveToPreviousViewWithAnimation;

      if (!CalendarViewHelper.isSameTimeSlot(oldWidget.controller.selectedDate, widget.controller.selectedDate) ||
          !CalendarViewHelper.isSameTimeSlot(_updateCalendarStateDetails.selectedDate, widget.controller.selectedDate)) {
        _selectResourceProgrammatically();
      }
    }

    if (oldWidget.view != widget.view) {
      _children.clear();

      /// Switching timeline view from non timeline view or non timeline view
      /// from timeline view creates the scroll layout as new because we handle
      /// the scrolling touch for timeline view in this widget, so current
      /// widget tree differ on timeline and non timeline views, so it creates
      /// new widget tree.
      if (CalendarViewHelper.isTimelineView(widget.view) != CalendarViewHelper.isTimelineView(oldWidget.view)) {
        _currentChildIndex = 1;
      }

      _updateVisibleDates();
      _position = 0;
    }

    if ((widget.calendar.monthViewSettings.navigationDirection != oldWidget.calendar.monthViewSettings.navigationDirection) ||
        widget.calendar.scheduleViewMonthHeaderBuilder != oldWidget.calendar.scheduleViewMonthHeaderBuilder ||
        widget.calendar.monthCellBuilder != oldWidget.calendar.monthCellBuilder ||
        widget.width != oldWidget.width ||
        widget.height != oldWidget.height ||
        widget.textScaleFactor != oldWidget.textScaleFactor) {
      _position = 0;
      _children.clear();
    }

    if (!_isTimeRegionsEquals(widget.specialRegions, _timeRegions)) {
      _timeRegions = CalendarViewHelper.cloneList(widget.specialRegions);
      _position = 0;
      _children.clear();
    }

    if ((widget.view == CalendarView.month || widget.view == CalendarView.timelineMonth) &&
        widget.blackoutDates != oldWidget.blackoutDates) {
      _children.clear();
      if (!_animationController.isAnimating) {
        _position = 0;
      }
    }

    /// Check and re renders the views if the resource collection changed.
    if (CalendarViewHelper.isTimelineView(widget.view) &&
        !CalendarViewHelper.isCollectionEqual(oldWidget.resourceCollection, widget.resourceCollection)) {
      _updateSelectedResourceIndex();
      _position = 0;
      _children.clear();
    }

    if (oldWidget.calendar.showCurrentTimeIndicator != widget.calendar.showCurrentTimeIndicator) {
      _position = 0;
      _children.clear();
    }

    //// condition to check and update the view when the settings changed, it will check each and every property of settings
    //// to avoid unwanted repainting
    if (oldWidget.calendar.timeSlotViewSettings != widget.calendar.timeSlotViewSettings ||
        oldWidget.calendar.monthViewSettings != widget.calendar.monthViewSettings ||
        oldWidget.calendar.blackoutDatesTextStyle != widget.calendar.blackoutDatesTextStyle ||
        oldWidget.calendar.resourceViewSettings != widget.calendar.resourceViewSettings ||
        oldWidget.calendar.viewHeaderStyle != widget.calendar.viewHeaderStyle ||
        oldWidget.calendar.viewHeaderHeight != widget.calendar.viewHeaderHeight ||
        oldWidget.calendar.todayHighlightColor != widget.calendar.todayHighlightColor ||
        oldWidget.calendar.cellBorderColor != widget.calendar.cellBorderColor ||
        oldWidget.calendarTheme != widget.calendarTheme ||
        oldWidget.locale != widget.locale ||
        oldWidget.calendar.selectionDecoration != widget.calendar.selectionDecoration ||
        oldWidget.calendar.weekNumberStyle != widget.calendar.weekNumberStyle) {
      final bool isTimelineView = CalendarViewHelper.isTimelineView(widget.view);
      if (widget.view != CalendarView.month &&
          (oldWidget.calendar.timeSlotViewSettings.timeInterval != widget.calendar.timeSlotViewSettings.timeInterval ||
              (!isTimelineView &&
                  oldWidget.calendar.timeSlotViewSettings.timeIntervalHeight !=
                      widget.calendar.timeSlotViewSettings.timeIntervalHeight) ||
              (isTimelineView &&
                  oldWidget.calendar.timeSlotViewSettings.timeIntervalWidth !=
                      widget.calendar.timeSlotViewSettings.timeIntervalWidth))) {
        if (_currentChildIndex == 0) {
          _previousViewKey.currentState!._retainScrolledDateTime();
        } else if (_currentChildIndex == 1) {
          _currentViewKey.currentState!._retainScrolledDateTime();
        } else if (_currentChildIndex == 2) {
          _nextViewKey.currentState!._retainScrolledDateTime();
        }
      }
      _children.clear();
      _position = 0;
    }

    if (widget.calendar.monthViewSettings.numberOfWeeksInView != oldWidget.calendar.monthViewSettings.numberOfWeeksInView ||
        widget.calendar.timeSlotViewSettings.nonWorkingDays != oldWidget.calendar.timeSlotViewSettings.nonWorkingDays ||
        widget.calendar.firstDayOfWeek != oldWidget.calendar.firstDayOfWeek) {
      _updateVisibleDates();
      _position = 0;
    }

    if (!isSameDate(widget.calendar.minDate, oldWidget.calendar.minDate) ||
        !isSameDate(widget.calendar.maxDate, oldWidget.calendar.maxDate)) {
      _updateVisibleDates();
      _position = 0;
    }

    if (CalendarViewHelper.isTimelineView(widget.view) != CalendarViewHelper.isTimelineView(oldWidget.view)) {
      _children.clear();
    }

    /// position set as zero to maintain the existing scroll position in
    /// timeline view
    if (CalendarViewHelper.isTimelineView(widget.view) &&
        (oldWidget.calendar.backgroundColor != widget.calendar.backgroundColor ||
            oldWidget.calendar.headerStyle != widget.calendar.headerStyle)) {
      _position = 0;
    }

    if (widget.controller == oldWidget.controller) {
      if (oldWidget.controller.displayDate != widget.controller.displayDate ||
          !isSameDate(_updateCalendarStateDetails.currentDate, widget.controller.displayDate)) {
        widget.getCalendarState(_updateCalendarStateDetails);
        _updateCalendarStateDetails.currentDate = widget.controller.displayDate!;
        widget.updateCalendarState(_updateCalendarStateDetails);
        _updateVisibleDates();
        _updateMoveToDate();
        _position = 0;
      }

      if (!CalendarViewHelper.isSameTimeSlot(oldWidget.controller.selectedDate, widget.controller.selectedDate) ||
          !CalendarViewHelper.isSameTimeSlot(_updateCalendarStateDetails.selectedDate, widget.controller.selectedDate)) {
        widget.getCalendarState(_updateCalendarStateDetails);
        _updateCalendarStateDetails.selectedDate = widget.controller.selectedDate;
        widget.updateCalendarState(_updateCalendarStateDetails);
        _selectResourceProgrammatically();
        _updateSelection();
        _position = 0;
      }
    }

    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    if (!CalendarViewHelper.isTimelineView(widget.view) && widget.view != CalendarView.month) {
      _updateScrollPosition();
    }

    double leftPosition = 0, rightPosition = 0, topPosition = 0, bottomPosition = 0;
    final bool isHorizontalNavigation =
        widget.calendar.monthViewSettings.navigationDirection == MonthNavigationDirection.horizontal ||
            widget.view != CalendarView.month;
    if (isHorizontalNavigation) {
      leftPosition = -widget.width;
      rightPosition = -widget.width;
    } else {
      topPosition = -widget.height;
      bottomPosition = -widget.height;
    }

    final bool isTimelineView = CalendarViewHelper.isTimelineView(widget.view);
    final Widget customScrollWidget = GestureDetector(
      child: CustomScrollViewerLayout(
          _addViews(),
          isHorizontalNavigation ? CustomScrollDirection.horizontal : CustomScrollDirection.vertical,
          _position,
          _currentChildIndex),
      onTapDown: (TapDownDetails details) {
        if (!_focusNode.hasFocus) {
          _focusNode.requestFocus();
        }
      },
      onHorizontalDragStart: isTimelineView ? null : _onHorizontalStart,
      onHorizontalDragUpdate: isTimelineView ? null : _onHorizontalUpdate,
      onHorizontalDragEnd: isTimelineView ? null : _onHorizontalEnd,
      onVerticalDragStart: isHorizontalNavigation ? null : _onVerticalStart,
      onVerticalDragUpdate: isHorizontalNavigation ? null : _onVerticalUpdate,
      onVerticalDragEnd: isHorizontalNavigation ? null : _onVerticalEnd,
    );

    return Stack(
      children: <Widget>[
        Positioned(
            left: leftPosition,
            right: rightPosition,
            bottom: bottomPosition,
            top: topPosition,
            child: FocusScope(
              node: _focusNode,
              child: isTimelineView
                  ? Listener(
                      onPointerSignal: _handlePointerSignal,
                      child: RawGestureDetector(gestures: <Type, GestureRecognizerFactory>{
                        HorizontalDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<HorizontalDragGestureRecognizer>(
                          () => HorizontalDragGestureRecognizer(),
                          (HorizontalDragGestureRecognizer instance) {
                            instance.onUpdate = _handleDragUpdate;
                            instance.onStart = _handleDragStart;
                            instance.onEnd = _handleDragEnd;
                            instance.onCancel = _handleDragCancel;
                          },
                        )
                      }, behavior: HitTestBehavior.opaque, child: customScrollWidget),
                    )
                  : customScrollWidget,
            )),
      ],
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _animation.removeListener(animationListener);
    _focusNode.dispose();
    super.dispose();
  }

  /// Get the scroll layout current child view state based on its visible dates.
  GlobalKey<_CalendarViewState>? _getCurrentViewByVisibleDates() {
    _CalendarView? view;
    for (int i = 0; i < _children.length; i++) {
      final _CalendarView currentView = _children[i];
      if (currentView.visibleDates == _currentViewVisibleDates) {
        view = currentView;
        break;
      }
    }

    if (view == null) {
      return null;
    }
    // ignore: avoid_as
    return view.key! as GlobalKey<_CalendarViewState>;
  }

  /// Handle start of the scroll, set the scroll start position and check
  /// the start position as start or end of timeline scroll controller.
  /// If the timeline view scroll starts at min or max scroll position then
  /// move the previous view to end of the scroll or move the next view to
  /// start of the scroll and set the drag as timeline scroll controller drag.
  void _handleDragStart(DragStartDetails details) {
    if (!CalendarViewHelper.isTimelineView(widget.view)) {
      return;
    }
    final GlobalKey<_CalendarViewState> viewKey = _getCurrentViewByVisibleDates()!;
    _timelineScrollStartPosition = viewKey.currentState!._scrollController!.position.pixels;
    _timelineStartPosition = details.globalPosition.dx;
    _isNeedTimelineScrollEnd = false;

    /// If the timeline view scroll starts at min or max scroll position then
    /// move the previous view to end of the scroll or move the next view to
    /// start of the scroll
    if (_timelineScrollStartPosition >= viewKey.currentState!._scrollController!.position.maxScrollExtent) {
      _positionTimelineView();
    } else if (_timelineScrollStartPosition <= viewKey.currentState!._scrollController!.position.minScrollExtent) {
      _positionTimelineView();
    }

    /// Set the drag as timeline scroll controller drag.
    if (viewKey.currentState!._scrollController!.hasClients) {
      _drag = viewKey.currentState!._scrollController!.position.drag(details, _disposeDrag);
    }
  }

  /// Handles the scroll update, if the scroll moves after the timeline max
  /// scroll position or before the timeline min scroll position then check the
  /// scroll start position if it is start or end of the timeline scroll view
  /// then pass the touch to custom scroll view and set the timeline view
  /// drag as null;
  void _handleDragUpdate(DragUpdateDetails details) {
    if (!CalendarViewHelper.isTimelineView(widget.view)) {
      return;
    }
    final GlobalKey<_CalendarViewState> viewKey = _getCurrentViewByVisibleDates()!;

    /// Calculate the scroll difference by current scroll position and start
    /// scroll position.
    final double difference = details.globalPosition.dx - _timelineStartPosition;
    if (_timelineScrollStartPosition >= viewKey.currentState!._scrollController!.position.maxScrollExtent && difference < 0) {
      /// Set the scroll position as timeline scroll start position and the
      /// value used on horizontal update method.
      _scrollStartPosition = _timelineStartPosition;
      _drag?.cancel();

      /// Move the touch(drag) to custom scroll view.
      _onHorizontalUpdate(details);

      /// Enable boolean value used to trigger the horizontal end animation on
      /// drag end.
      _isNeedTimelineScrollEnd = true;

      /// Remove the timeline view drag or scroll.
      _disposeDrag();
      return;
    } else if (_timelineScrollStartPosition <= viewKey.currentState!._scrollController!.position.minScrollExtent &&
        difference > 0) {
      /// Set the scroll position as timeline scroll start position and the
      /// value used on horizontal update method.
      _scrollStartPosition = _timelineStartPosition;
      _drag?.cancel();

      /// Move the touch(drag) to custom scroll view.
      _onHorizontalUpdate(details);

      /// Enable boolean value used to trigger the horizontal end animation on
      /// drag end.
      _isNeedTimelineScrollEnd = true;

      /// Remove the timeline view drag or scroll.
      _disposeDrag();
      return;
    }

    _drag?.update(details);
  }

  /// Handle the scroll end to update the timeline view scroll or custom scroll
  /// view scroll based on [_isNeedTimelineScrollEnd] value
  void _handleDragEnd(DragEndDetails details) {
    if (_isNeedTimelineScrollEnd) {
      _isNeedTimelineScrollEnd = false;
      _onHorizontalEnd(details);
      return;
    }

    _isNeedTimelineScrollEnd = false;
    _drag?.end(details);
  }

  /// Handle drag cancel related operations.
  void _handleDragCancel() {
    _isNeedTimelineScrollEnd = false;
    _drag?.cancel();
  }

  /// Remove the drag when the touch(drag) passed to custom scroll view.
  void _disposeDrag() {
    _drag = null;
  }

  /// Handle the pointer scroll when a pointer signal occurs over this object.
  /// eg., track pad scroll.
  void _handlePointerSignal(PointerSignalEvent event) {
    final GlobalKey<_CalendarViewState>? viewKey = _getCurrentViewByVisibleDates();
    if (event is PointerScrollEvent && viewKey != null) {
      final double scrolledPosition = event.scrollDelta.dx;
      final double targetScrollOffset = math.min(
          math.max(viewKey.currentState!._scrollController!.position.pixels + scrolledPosition,
              viewKey.currentState!._scrollController!.position.minScrollExtent),
          viewKey.currentState!._scrollController!.position.maxScrollExtent);
      if (targetScrollOffset != viewKey.currentState!._scrollController!.position.pixels) {
        viewKey.currentState!._scrollController!.position.jumpTo(targetScrollOffset);
      }
    }
  }

  void _updateVisibleDates() {
    widget.getCalendarState(_updateCalendarStateDetails);
    final DateTime currentDate = DateTime(_updateCalendarStateDetails.currentDate!.year,
        _updateCalendarStateDetails.currentDate!.month, _updateCalendarStateDetails.currentDate!.day);
    final DateTime prevDate =
        DateTimeHelper.getPreviousViewStartDate(widget.view, widget.calendar.monthViewSettings.numberOfWeeksInView, currentDate);
    final DateTime nextDate =
        DateTimeHelper.getNextViewStartDate(widget.view, widget.calendar.monthViewSettings.numberOfWeeksInView, currentDate);
    final List<int>? nonWorkingDays = (widget.view == CalendarView.workWeek || widget.view == CalendarView.timelineWorkWeek)
        ? widget.calendar.timeSlotViewSettings.nonWorkingDays
        : null;
    final int visibleDatesCount =
        DateTimeHelper.getViewDatesCount(widget.view, widget.calendar.monthViewSettings.numberOfWeeksInView);

    _visibleDates = getVisibleDates(currentDate, nonWorkingDays, widget.calendar.firstDayOfWeek, visibleDatesCount).cast();
    _previousViewVisibleDates =
        getVisibleDates(prevDate, nonWorkingDays, widget.calendar.firstDayOfWeek, visibleDatesCount).cast();
    _nextViewVisibleDates = getVisibleDates(nextDate, nonWorkingDays, widget.calendar.firstDayOfWeek, visibleDatesCount).cast();
    if (widget.view == CalendarView.timelineMonth) {
      _visibleDates = DateTimeHelper.getCurrentMonthDates(_visibleDates);
      _previousViewVisibleDates = DateTimeHelper.getCurrentMonthDates(_previousViewVisibleDates);
      _nextViewVisibleDates = DateTimeHelper.getCurrentMonthDates(_nextViewVisibleDates);
    }

    _currentViewVisibleDates = _visibleDates;
    _updateCalendarStateDetails.currentViewVisibleDates = _currentViewVisibleDates;
    widget.updateCalendarState(_updateCalendarStateDetails);

    if (_currentChildIndex == 0) {
      _visibleDates = _nextViewVisibleDates;
      _nextViewVisibleDates = _previousViewVisibleDates;
      _previousViewVisibleDates = _currentViewVisibleDates;
    } else if (_currentChildIndex == 1) {
      _visibleDates = _currentViewVisibleDates;
    } else if (_currentChildIndex == 2) {
      _visibleDates = _previousViewVisibleDates;
      _previousViewVisibleDates = _nextViewVisibleDates;
      _nextViewVisibleDates = _currentViewVisibleDates;
    }
  }

  void _updateNextViewVisibleDates() {
    DateTime currentViewDate = _currentViewVisibleDates[0];
    if (widget.view == CalendarView.month && widget.calendar.monthViewSettings.numberOfWeeksInView == 6) {
      currentViewDate = _currentViewVisibleDates[(_currentViewVisibleDates.length / 2).truncate()];
    }

    currentViewDate =
        DateTimeHelper.getNextViewStartDate(widget.view, widget.calendar.monthViewSettings.numberOfWeeksInView, currentViewDate);

    List<DateTime> dates = getVisibleDates(
            currentViewDate,
            widget.view == CalendarView.workWeek || widget.view == CalendarView.timelineWorkWeek
                ? widget.calendar.timeSlotViewSettings.nonWorkingDays
                : null,
            widget.calendar.firstDayOfWeek,
            DateTimeHelper.getViewDatesCount(widget.view, widget.calendar.monthViewSettings.numberOfWeeksInView))
        .cast();

    if (widget.view == CalendarView.timelineMonth) {
      dates = DateTimeHelper.getCurrentMonthDates(dates);
    }

    if (_currentChildIndex == 0) {
      _nextViewVisibleDates = dates;
    } else if (_currentChildIndex == 1) {
      _previousViewVisibleDates = dates;
    } else {
      _visibleDates = dates;
    }
  }

  void _updatePreviousViewVisibleDates() {
    DateTime currentViewDate = _currentViewVisibleDates[0];
    if (widget.view == CalendarView.month && widget.calendar.monthViewSettings.numberOfWeeksInView == 6) {
      currentViewDate = _currentViewVisibleDates[(_currentViewVisibleDates.length / 2).truncate()];
    }

    currentViewDate = DateTimeHelper.getPreviousViewStartDate(
        widget.view, widget.calendar.monthViewSettings.numberOfWeeksInView, currentViewDate);

    List<DateTime> dates = getVisibleDates(
            currentViewDate,
            widget.view == CalendarView.workWeek || widget.view == CalendarView.timelineWorkWeek
                ? widget.calendar.timeSlotViewSettings.nonWorkingDays
                : null,
            widget.calendar.firstDayOfWeek,
            DateTimeHelper.getViewDatesCount(widget.view, widget.calendar.monthViewSettings.numberOfWeeksInView))
        .cast();

    if (widget.view == CalendarView.timelineMonth) {
      dates = DateTimeHelper.getCurrentMonthDates(dates);
    }

    if (_currentChildIndex == 0) {
      _visibleDates = dates;
    } else if (_currentChildIndex == 1) {
      _nextViewVisibleDates = dates;
    } else {
      _previousViewVisibleDates = dates;
    }
  }

  void _getCalendarViewStateDetails(UpdateCalendarStateDetails details) {
    widget.getCalendarState(_updateCalendarStateDetails);
    details.currentDate = _updateCalendarStateDetails.currentDate;
    details.currentViewVisibleDates = _updateCalendarStateDetails.currentViewVisibleDates;
    details.selectedDate = _updateCalendarStateDetails.selectedDate;
    details.allDayPanelHeight = _updateCalendarStateDetails.allDayPanelHeight;
    details.allDayAppointmentViewCollection = _updateCalendarStateDetails.allDayAppointmentViewCollection;
    details.appointments = _updateCalendarStateDetails.appointments;
    details.visibleAppointments = _updateCalendarStateDetails.visibleAppointments;
  }

  void _updateCalendarViewStateDetails(UpdateCalendarStateDetails details) {
    _updateCalendarStateDetails.selectedDate = details.selectedDate;
    widget.updateCalendarState(_updateCalendarStateDetails);
  }

  CalendarTimeRegion _getCalendarTimeRegionFromTimeRegion(TimeRegion region) {
    return CalendarTimeRegion(
      startTime: region.startTime,
      endTime: region.endTime,
      color: region.color,
      text: region.text,
      textStyle: region.textStyle,
      recurrenceExceptionDates: region.recurrenceExceptionDates,
      recurrenceRule: region.recurrenceRule,
      resourceIds: region.resourceIds,
      timeZone: region.timeZone,
      enablePointerInteraction: region.enablePointerInteraction,
      iconData: region.iconData,
    );
  }

  /// Return collection of time region, in between the visible dates.
  List<CalendarTimeRegion> _getRegions(List<DateTime> visibleDates) {
    final DateTime visibleStartDate = visibleDates[0];
    final DateTime visibleEndDate = visibleDates[visibleDates.length - 1];
    final List<CalendarTimeRegion> regionCollection = <CalendarTimeRegion>[];
    if (_timeRegions == null) {
      return regionCollection;
    }

    final DateTime startDate = AppointmentHelper.convertToStartTime(visibleStartDate);
    final DateTime endDate = AppointmentHelper.convertToEndTime(visibleEndDate);
    for (int j = 0; j < _timeRegions!.length; j++) {
      final TimeRegion timeRegion = _timeRegions![j];
      final CalendarTimeRegion region = _getCalendarTimeRegionFromTimeRegion(timeRegion);
      region.actualStartTime =
          AppointmentHelper.convertTimeToAppointmentTimeZone(region.startTime, region.timeZone, widget.calendar.timeZone);
      region.actualEndTime =
          AppointmentHelper.convertTimeToAppointmentTimeZone(region.endTime, region.timeZone, widget.calendar.timeZone);
      region.data = timeRegion;

      if (region.recurrenceRule == null || region.recurrenceRule == '') {
        if (AppointmentHelper.isDateRangeWithinVisibleDateRange(
            region.actualStartTime, region.actualEndTime, startDate, endDate)) {
          regionCollection.add(region);
        }

        continue;
      }

      getRecurrenceRegions(region, regionCollection, startDate, endDate, widget.calendar.timeZone);
    }

    return regionCollection;
  }

  /// Get the recurrence time regions in between the visible date range.
  void getRecurrenceRegions(CalendarTimeRegion region, List<CalendarTimeRegion> regions, DateTime visibleStartDate,
      DateTime visibleEndDate, String? calendarTimeZone) {
    final DateTime regionStartDate = region.actualStartTime;
    if (regionStartDate.isAfter(visibleEndDate)) {
      return;
    }

    String rule = region.recurrenceRule!;
    if (!rule.contains('COUNT') && !rule.contains('UNTIL')) {
      final DateFormat formatter = DateFormat('yyyyMMdd');
      final String newSubString = ';UNTIL=' + formatter.format(visibleEndDate);
      rule = rule + newSubString;
    }

    final List<DateTime> recursiveDates = RecurrenceHelper.getRecurrenceDateTimeCollection(rule, region.actualStartTime,
        recurrenceDuration: region.actualEndTime.difference(region.actualStartTime),
        specificStartDate: visibleStartDate,
        specificEndDate: visibleEndDate);

    for (int j = 0; j < recursiveDates.length; j++) {
      final DateTime recursiveDate = recursiveDates[j];
      if (region.recurrenceExceptionDates != null) {
        bool isDateContains = false;
        for (int i = 0; i < region.recurrenceExceptionDates!.length; i++) {
          final DateTime date =
              AppointmentHelper.convertTimeToAppointmentTimeZone(region.recurrenceExceptionDates![i], '', calendarTimeZone);
          if (isSameDate(date, recursiveDate)) {
            isDateContains = true;
            break;
          }
        }
        if (isDateContains) {
          continue;
        }
      }

      final CalendarTimeRegion occurrenceRegion = cloneRecurrenceRegion(region, recursiveDate, calendarTimeZone);
      regions.add(occurrenceRegion);
    }
  }

  /// Used to clone the time region with new values.
  CalendarTimeRegion cloneRecurrenceRegion(CalendarTimeRegion region, DateTime recursiveDate, String? calendarTimeZone) {
    final int minutes = region.actualEndTime.difference(region.actualStartTime).inMinutes;
    final DateTime actualEndTime = DateTimeHelper.getDateTimeValue(addDuration(recursiveDate, Duration(minutes: minutes)));
    final DateTime startDate =
        AppointmentHelper.convertTimeToAppointmentTimeZone(recursiveDate, region.timeZone, calendarTimeZone);

    final DateTime endDate = AppointmentHelper.convertTimeToAppointmentTimeZone(actualEndTime, region.timeZone, calendarTimeZone);

    final TimeRegion occurrenceTimeRegion = region.data.copyWith(startTime: startDate, endTime: endDate);
    final CalendarTimeRegion occurrenceRegion = _getCalendarTimeRegionFromTimeRegion(occurrenceTimeRegion);
    occurrenceRegion.actualStartTime = recursiveDate;
    occurrenceRegion.actualEndTime = actualEndTime;
    occurrenceRegion.data = occurrenceTimeRegion;
    return occurrenceRegion;
  }

  /// Return date collection which falls between the visible date range.
  List<DateTime> _getDatesWithInVisibleDateRange(List<DateTime>? dates, List<DateTime> visibleDates) {
    final List<DateTime> visibleMonthDates = <DateTime>[];
    if (dates == null) {
      return visibleMonthDates;
    }

    final DateTime visibleStartDate = visibleDates[0];
    final DateTime visibleEndDate = visibleDates[visibleDates.length - 1];
    final int datesCount = dates.length;
    final Map<String, DateTime> dateCollection = <String, DateTime>{};
    for (int i = 0; i < datesCount; i++) {
      final DateTime currentDate = dates[i];
      if (!isDateWithInDateRange(visibleStartDate, visibleEndDate, currentDate)) {
        continue;
      }

      if (dateCollection.keys.contains(currentDate.day.toString() + currentDate.month.toString())) {
        continue;
      }

      dateCollection[currentDate.day.toString() + currentDate.month.toString()] = currentDate;
      visibleMonthDates.add(currentDate);
    }

    return visibleMonthDates;
  }

  List<Widget> _addViews() {
    if (_children.isEmpty) {
      _previousView = _CalendarView(
        widget.calendar,
        widget.view,
        _previousViewVisibleDates,
        widget.width,
        widget.height,
        widget.agendaSelectedDate,
        widget.locale,
        widget.calendarTheme,
        _getRegions(_previousViewVisibleDates),
        _getDatesWithInVisibleDateRange(widget.blackoutDates, _previousViewVisibleDates),
        _focusNode,
        widget.removePicker,
        widget.calendar.allowViewNavigation,
        widget.controller,
        widget.resourcePanelScrollController,
        widget.resourceCollection,
        widget.textScaleFactor,
        widget.minDate,
        widget.maxDate,
        widget.localizations,
        (UpdateCalendarStateDetails details) {
          _updateCalendarViewStateDetails(details);
        },
        (UpdateCalendarStateDetails details) {
          _getCalendarViewStateDetails(details);
        },
        key: _previousViewKey,
      );
      _currentView = _CalendarView(
        widget.calendar,
        widget.view,
        _visibleDates,
        widget.width,
        widget.height,
        widget.agendaSelectedDate,
        widget.locale,
        widget.calendarTheme,
        _getRegions(_visibleDates),
        _getDatesWithInVisibleDateRange(widget.blackoutDates, _visibleDates),
        _focusNode,
        widget.removePicker,
        widget.calendar.allowViewNavigation,
        widget.controller,
        widget.resourcePanelScrollController,
        widget.resourceCollection,
        widget.textScaleFactor,
        widget.minDate,
        widget.maxDate,
        widget.localizations,
        (UpdateCalendarStateDetails details) {
          _updateCalendarViewStateDetails(details);
        },
        (UpdateCalendarStateDetails details) {
          _getCalendarViewStateDetails(details);
        },
        key: _currentViewKey,
      );
      _nextView = _CalendarView(
        widget.calendar,
        widget.view,
        _nextViewVisibleDates,
        widget.width,
        widget.height,
        widget.agendaSelectedDate,
        widget.locale,
        widget.calendarTheme,
        _getRegions(_nextViewVisibleDates),
        _getDatesWithInVisibleDateRange(widget.blackoutDates, _nextViewVisibleDates),
        _focusNode,
        widget.removePicker,
        widget.calendar.allowViewNavigation,
        widget.controller,
        widget.resourcePanelScrollController,
        widget.resourceCollection,
        widget.textScaleFactor,
        widget.minDate,
        widget.maxDate,
        widget.localizations,
        (UpdateCalendarStateDetails details) {
          _updateCalendarViewStateDetails(details);
        },
        (UpdateCalendarStateDetails details) {
          _getCalendarViewStateDetails(details);
        },
        key: _nextViewKey,
      );

      _children.add(_previousView);
      _children.add(_currentView);
      _children.add(_nextView);
      return _children;
    }

    widget.getCalendarState(_updateCalendarStateDetails);
    final _CalendarView previousView = _updateViews(_previousView, _previousViewKey, _previousViewVisibleDates);
    final _CalendarView currentView = _updateViews(_currentView, _currentViewKey, _visibleDates);
    final _CalendarView nextView = _updateViews(_nextView, _nextViewKey, _nextViewVisibleDates);

    //// Update views while the all day view height differ from original height,
    //// else repaint the appointment painter while current child visible appointment not equals calendar visible appointment
    if (_previousView != previousView) {
      _previousView = previousView;
    }
    if (_currentView != currentView) {
      _currentView = currentView;
    }
    if (_nextView != nextView) {
      _nextView = nextView;
    }

    return _children;
  }

  // method to check and update the views and appointments on the swiping end
  _CalendarView _updateViews(_CalendarView view, GlobalKey<_CalendarViewState> viewKey, List<DateTime> visibleDates) {
    final int index = _children.indexOf(view);

    final AppointmentLayout appointmentLayout = viewKey.currentState!._appointmentLayout;
    // update the view with the visible dates on swiping end.
    if (view.visibleDates != visibleDates) {
      view = _CalendarView(
        widget.calendar,
        widget.view,
        visibleDates,
        widget.width,
        widget.height,
        widget.agendaSelectedDate,
        widget.locale,
        widget.calendarTheme,
        _getRegions(visibleDates),
        _getDatesWithInVisibleDateRange(widget.blackoutDates, visibleDates),
        _focusNode,
        widget.removePicker,
        widget.calendar.allowViewNavigation,
        widget.controller,
        widget.resourcePanelScrollController,
        widget.resourceCollection,
        widget.textScaleFactor,
        widget.minDate,
        widget.maxDate,
        widget.localizations,
        (UpdateCalendarStateDetails details) {
          _updateCalendarViewStateDetails(details);
        },
        (UpdateCalendarStateDetails details) {
          _getCalendarViewStateDetails(details);
        },
        key: viewKey,
      );

      _children[index] = view;
    } // check and update the visible appointments in the view
    else if (!CalendarViewHelper.isCollectionEqual(
        appointmentLayout.visibleAppointments.value, _updateCalendarStateDetails.visibleAppointments)) {
      if (widget.view != CalendarView.month && !CalendarViewHelper.isTimelineView(widget.view)) {
        view = _CalendarView(
          widget.calendar,
          widget.view,
          visibleDates,
          widget.width,
          widget.height,
          widget.agendaSelectedDate,
          widget.locale,
          widget.calendarTheme,
          view.regions,
          view.blackoutDates,
          _focusNode,
          widget.removePicker,
          widget.calendar.allowViewNavigation,
          widget.controller,
          widget.resourcePanelScrollController,
          widget.resourceCollection,
          widget.textScaleFactor,
          widget.minDate,
          widget.maxDate,
          widget.localizations,
          (UpdateCalendarStateDetails details) {
            _updateCalendarViewStateDetails(details);
          },
          (UpdateCalendarStateDetails details) {
            _getCalendarViewStateDetails(details);
          },
          key: viewKey,
        );
        _children[index] = view;
      } else if (view.visibleDates == _currentViewVisibleDates) {
        /// Remove the appointment selection when the selected
        /// appointment removed.
        if (viewKey.currentState!._selectionPainter != null &&
            viewKey.currentState!._selectionPainter!.appointmentView != null &&
            (!_updateCalendarStateDetails.visibleAppointments
                .contains(viewKey.currentState!._selectionPainter!.appointmentView!.appointment))) {
          viewKey.currentState!._selectionPainter!.appointmentView = null;
          viewKey.currentState!._selectionPainter!.repaintNotifier.value =
              !viewKey.currentState!._selectionPainter!.repaintNotifier.value;
        }

        appointmentLayout.visibleAppointments.value = _updateCalendarStateDetails.visibleAppointments;
        if (widget.view == CalendarView.month && widget.calendar.monthCellBuilder != null) {
          viewKey.currentState!._monthView.visibleAppointmentNotifier.value = _updateCalendarStateDetails.visibleAppointments;
        }
      }
    }
    // When calendar state changed the state doesn't pass to the child of
    // custom scroll view, hence to update the calendar state to the child we
    // have added this.
    else if (view.calendar != widget.calendar) {
      /// Update the calendar view when calendar properties like blackout dates
      /// dynamically changed.
      view = _CalendarView(
        widget.calendar,
        widget.view,
        visibleDates,
        widget.width,
        widget.height,
        widget.agendaSelectedDate,
        widget.locale,
        widget.calendarTheme,
        view.regions,
        view.blackoutDates,
        _focusNode,
        widget.removePicker,
        widget.calendar.allowViewNavigation,
        widget.controller,
        widget.resourcePanelScrollController,
        widget.resourceCollection,
        widget.textScaleFactor,
        widget.minDate,
        widget.maxDate,
        widget.localizations,
        (UpdateCalendarStateDetails details) {
          _updateCalendarViewStateDetails(details);
        },
        (UpdateCalendarStateDetails details) {
          _getCalendarViewStateDetails(details);
        },
        key: viewKey,
      );

      _children[index] = view;
    }

    return view;
  }

  void animationListener() {
    setState(() {
      _position = _animation.value;
    });
  }

  /// Check both the region collection as equal or not.
  bool _isTimeRegionsEquals(List<TimeRegion>? regions1, List<TimeRegion>? regions2) {
    /// Check both instance as equal
    /// eg., if both are null then its equal.
    if (regions1 == regions2) {
      return true;
    }

    /// Check the collections are not equal based on its length
    if (regions2 == null || regions1 == null || regions1.length != regions2.length) {
      return false;
    }

    /// Check each of the region is equal to another or not.
    for (int i = 0; i < regions1.length; i++) {
      if (regions1[i] != regions2[i]) {
        return false;
      }
    }

    return true;
  }

  /// Updates the selected date programmatically, when resource enables, in
  /// this scenario the first resource cell will be selected
  void _selectResourceProgrammatically() {
    if (!CalendarViewHelper.isTimelineView(widget.view)) {
      return;
    }

    for (int i = 0; i < _children.length; i++) {
      final GlobalKey<_CalendarViewState> viewKey =
          // ignore: avoid_as
          _children[i].key! as GlobalKey<_CalendarViewState>;
      if (CalendarViewHelper.isResourceEnabled(widget.calendar.dataSource, widget.view)) {
        viewKey.currentState!._selectedResourceIndex = 0;
        viewKey.currentState!._selectionPainter!.selectedResourceIndex = 0;
      } else {
        viewKey.currentState!._selectedResourceIndex = -1;
        viewKey.currentState!._selectionPainter!.selectedResourceIndex = -1;
      }
    }
  }

  /// Updates the selection, when the resource enabled and the resource
  /// collection modified, moves or removes the selection based on the action
  /// performed.
  void _updateSelectedResourceIndex() {
    for (int i = 0; i < _children.length; i++) {
      final GlobalKey<_CalendarViewState> viewKey =
          // ignore: avoid_as
          _children[i].key! as GlobalKey<_CalendarViewState>;
      final int selectedResourceIndex = viewKey.currentState!._selectedResourceIndex;
      if (selectedResourceIndex != -1) {
        final Object selectedResourceId = widget.resourceCollection![selectedResourceIndex].id;
        final int newIndex = CalendarViewHelper.getResourceIndex(widget.calendar.dataSource?.resources, selectedResourceId);
        viewKey.currentState!._selectedResourceIndex = newIndex;
      }
    }
  }

  void _updateSelection() {
    widget.getCalendarState(_updateCalendarStateDetails);
    final _CalendarViewState previousViewState = _previousViewKey.currentState!;
    final _CalendarViewState currentViewState = _currentViewKey.currentState!;
    final _CalendarViewState nextViewState = _nextViewKey.currentState!;
    previousViewState._allDaySelectionNotifier.value = null;
    currentViewState._allDaySelectionNotifier.value = null;
    nextViewState._allDaySelectionNotifier.value = null;
    previousViewState._selectionPainter!.selectedDate = _updateCalendarStateDetails.selectedDate;
    nextViewState._selectionPainter!.selectedDate = _updateCalendarStateDetails.selectedDate;
    currentViewState._selectionPainter!.selectedDate = _updateCalendarStateDetails.selectedDate;
    previousViewState._selectionPainter!.appointmentView = null;
    nextViewState._selectionPainter!.appointmentView = null;
    currentViewState._selectionPainter!.appointmentView = null;
    previousViewState._selectionNotifier.value = !previousViewState._selectionNotifier.value;
    currentViewState._selectionNotifier.value = !currentViewState._selectionNotifier.value;
    nextViewState._selectionNotifier.value = !nextViewState._selectionNotifier.value;
  }

  void _updateMoveToDate() {
    if (widget.view == CalendarView.month) {
      return;
    }

    SchedulerBinding.instance!.addPostFrameCallback((_) {
      if (_currentChildIndex == 0) {
        _previousViewKey.currentState!._scrollToPosition();
      } else if (_currentChildIndex == 1) {
        _currentViewKey.currentState!._scrollToPosition();
      } else if (_currentChildIndex == 2) {
        _nextViewKey.currentState!._scrollToPosition();
      }
    });
  }

  /// Updates the current view visible dates for calendar in the swiping end
  void _updateCurrentViewVisibleDates({bool isNextView = false}) {
    if (isNextView) {
      if (_currentChildIndex == 0) {
        _currentViewVisibleDates = _visibleDates;
      } else if (_currentChildIndex == 1) {
        _currentViewVisibleDates = _nextViewVisibleDates;
      } else {
        _currentViewVisibleDates = _previousViewVisibleDates;
      }
    } else {
      if (_currentChildIndex == 0) {
        _currentViewVisibleDates = _nextViewVisibleDates;
      } else if (_currentChildIndex == 1) {
        _currentViewVisibleDates = _previousViewVisibleDates;
      } else {
        _currentViewVisibleDates = _visibleDates;
      }
    }

    _updateCalendarStateDetails.currentViewVisibleDates = _currentViewVisibleDates;
    if (widget.view == CalendarView.month && widget.calendar.monthViewSettings.numberOfWeeksInView == 6) {
      final DateTime currentMonthDate = _currentViewVisibleDates[_currentViewVisibleDates.length ~/ 2];
      _updateCalendarStateDetails.currentDate = DateTime(currentMonthDate.year, currentMonthDate.month, 01);
    } else {
      _updateCalendarStateDetails.currentDate = _currentViewVisibleDates[0];
    }

    widget.updateCalendarState(_updateCalendarStateDetails);
  }

  void _updateNextView() {
    if (!_animationController.isCompleted) {
      return;
    }

    _updateSelection();
    _updateNextViewVisibleDates();

    /// Updates the all day panel of the view, when the all day panel expanded
    /// and the view swiped with the expanded all day panel, and when we swipe
    /// back to the view or swipes three times will render the all day panel as
    /// expanded, to collapse the all day panel in day, week and work week view,
    /// we have added this condition and called the method.
    if (widget.view != CalendarView.month && !CalendarViewHelper.isTimelineView(widget.view)) {
      _updateAllDayPanel();
    }

    setState(() {
      /// Update the custom scroll layout current child index when the
      /// animation ends.
      if (_currentChildIndex == 0) {
        _currentChildIndex = 1;
      } else if (_currentChildIndex == 1) {
        _currentChildIndex = 2;
      } else if (_currentChildIndex == 2) {
        _currentChildIndex = 0;
      }
    });

    _resetPosition();
    _updateAppointmentPainter();
  }

  void _updatePreviousView() {
    if (!_animationController.isCompleted) {
      return;
    }

    _updateSelection();
    _updatePreviousViewVisibleDates();

    /// Updates the all day panel of the view, when the all day panel expanded
    /// and the view swiped with the expanded all day panel, and when we swipe
    /// back to the view or swipes three times will render the all day panel as
    /// expanded, to collapse the all day panel in day, week and work week view,
    /// we have added this condition and called the method.
    if (widget.view != CalendarView.month && !CalendarViewHelper.isTimelineView(widget.view)) {
      _updateAllDayPanel();
    }

    setState(() {
      /// Update the custom scroll layout current child index when the
      /// animation ends.
      if (_currentChildIndex == 0) {
        _currentChildIndex = 2;
      } else if (_currentChildIndex == 1) {
        _currentChildIndex = 0;
      } else if (_currentChildIndex == 2) {
        _currentChildIndex = 1;
      }
    });

    _resetPosition();
    _updateAppointmentPainter();
  }

  void _moveToNextViewWithAnimation() {
    if (!DateTimeHelper.canMoveToNextView(
        widget.view,
        widget.calendar.monthViewSettings.numberOfWeeksInView,
        widget.calendar.minDate,
        widget.calendar.maxDate,
        _currentViewVisibleDates,
        widget.calendar.timeSlotViewSettings.nonWorkingDays)) {
      return;
    }

    // Resets the controller to forward it again, the animation will forward
    // only from the dismissed state
    if (_animationController.isCompleted || _animationController.isDismissed) {
      _animationController.reset();
    } else {
      return;
    }

    // Handled for time line view, to move the previous and next view to it's
    // start and end position accordingly
    if (CalendarViewHelper.isTimelineView(widget.view)) {
      _positionTimelineView(isScrolledToEnd: false);
    }

    if (widget.calendar.monthViewSettings.navigationDirection == MonthNavigationDirection.vertical &&
        widget.view == CalendarView.month) {
      // update the bottom to top swiping
      _tween.begin = 0;
      _tween.end = -widget.height;
    } else {
      // update the right to left swiping
      _tween.begin = 0;
      _tween.end = -widget.width;
    }

    _animationController.duration = const Duration(milliseconds: 250);
    _animationController.forward().then<dynamic>((dynamic value) => _updateNextView());

    /// updates the current view visible dates when the view swiped
    _updateCurrentViewVisibleDates(isNextView: true);
  }

  void _moveToPreviousViewWithAnimation({bool isScrollToEnd = false}) {
    if (!DateTimeHelper.canMoveToPreviousView(
        widget.view,
        widget.calendar.monthViewSettings.numberOfWeeksInView,
        widget.calendar.minDate,
        widget.calendar.maxDate,
        _currentViewVisibleDates,
        widget.calendar.timeSlotViewSettings.nonWorkingDays)) {
      return;
    }

    // Resets the controller to backward it again, the animation will backward
    // only from the dismissed state
    if (_animationController.isCompleted || _animationController.isDismissed) {
      _animationController.reset();
    } else {
      return;
    }

    // Handled for time line view, to move the previous and next view to it's
    // start and end position accordingly
    if (CalendarViewHelper.isTimelineView(widget.view)) {
      _positionTimelineView(isScrolledToEnd: isScrollToEnd);
    }

    if (widget.calendar.monthViewSettings.navigationDirection == MonthNavigationDirection.vertical &&
        widget.view == CalendarView.month) {
      // update the top to bottom swiping
      _tween.begin = 0;
      _tween.end = widget.height;
    } else {
      // update the left to right swiping
      _tween.begin = 0;
      _tween.end = widget.width;
    }

    _animationController.duration = const Duration(milliseconds: 250);
    _animationController.forward().then<dynamic>((dynamic value) => _updatePreviousView());

    /// updates the current view visible dates when the view swiped.
    _updateCurrentViewVisibleDates();
  }

  // resets position to zero on the swipe end to avoid the unwanted date updates
  void _resetPosition() {
    SchedulerBinding.instance!.addPostFrameCallback((_) {
      if (_position.abs() == widget.width || _position.abs() == widget.height) {
        _position = 0;
      }
    });
  }

  void _updateScrollPosition() {
    SchedulerBinding.instance!.addPostFrameCallback((_) {
      if (_previousViewKey.currentState == null ||
          _currentViewKey.currentState == null ||
          _nextViewKey.currentState == null ||
          _previousViewKey.currentState!._scrollController == null ||
          _currentViewKey.currentState!._scrollController == null ||
          _nextViewKey.currentState!._scrollController == null ||
          !_previousViewKey.currentState!._scrollController!.hasClients ||
          !_currentViewKey.currentState!._scrollController!.hasClients ||
          !_nextViewKey.currentState!._scrollController!.hasClients) {
        return;
      }

      _updateDayViewScrollPosition();
    });
  }

  /// Update the current day view view scroll position to other views.
  void _updateDayViewScrollPosition() {
    double scrolledPosition = 0;
    if (_currentChildIndex == 0) {
      scrolledPosition = _previousViewKey.currentState!._scrollController!.offset;
    } else if (_currentChildIndex == 1) {
      scrolledPosition = _currentViewKey.currentState!._scrollController!.offset;
    } else if (_currentChildIndex == 2) {
      scrolledPosition = _nextViewKey.currentState!._scrollController!.offset;
    }

    if (_previousViewKey.currentState!._scrollController!.offset != scrolledPosition &&
        _previousViewKey.currentState!._scrollController!.position.maxScrollExtent >= scrolledPosition) {
      _previousViewKey.currentState!._scrollController!.jumpTo(scrolledPosition);
    }

    if (_currentViewKey.currentState!._scrollController!.offset != scrolledPosition &&
        _currentViewKey.currentState!._scrollController!.position.maxScrollExtent >= scrolledPosition) {
      _currentViewKey.currentState!._scrollController!.jumpTo(scrolledPosition);
    }

    if (_nextViewKey.currentState!._scrollController!.offset != scrolledPosition &&
        _nextViewKey.currentState!._scrollController!.position.maxScrollExtent >= scrolledPosition) {
      _nextViewKey.currentState!._scrollController!.jumpTo(scrolledPosition);
    }
  }

  void _positionTimelineView({bool isScrolledToEnd = true}) {
    final _CalendarViewState previousViewState = _previousViewKey.currentState!;
    final _CalendarViewState currentViewState = _currentViewKey.currentState!;
    final _CalendarViewState nextViewState = _nextViewKey.currentState!;

    if (_currentChildIndex == 0) {
      nextViewState._scrollController!.jumpTo(isScrolledToEnd ? nextViewState._scrollController!.position.maxScrollExtent : 0);
      currentViewState._scrollController!.jumpTo(0);
    } else if (_currentChildIndex == 1) {
      previousViewState._scrollController!
          .jumpTo(isScrolledToEnd ? previousViewState._scrollController!.position.maxScrollExtent : 0);
      nextViewState._scrollController!.jumpTo(0);
    } else if (_currentChildIndex == 2) {
      currentViewState._scrollController!
          .jumpTo(isScrolledToEnd ? currentViewState._scrollController!.position.maxScrollExtent : 0);
      previousViewState._scrollController!.jumpTo(0);
    }
  }

  void _onHorizontalStart(DragStartDetails dragStartDetails) {
    switch (widget.calendar.viewNavigationMode) {
      case ViewNavigationMode.none:
        return;
      case ViewNavigationMode.snap:
        widget.removePicker();
        if (widget.calendar.monthViewSettings.navigationDirection == MonthNavigationDirection.horizontal ||
            widget.view != CalendarView.month) {
          _scrollStartPosition = dragStartDetails.globalPosition.dx;
        }

        // Handled for time line view, to move the previous and
        // next view to it's start and end position accordingly
        if (CalendarViewHelper.isTimelineView(widget.view)) {
          _positionTimelineView();
        }
    }
  }

  void _onHorizontalUpdate(DragUpdateDetails dragUpdateDetails) {
    switch (widget.calendar.viewNavigationMode) {
      case ViewNavigationMode.none:
        return;
      case ViewNavigationMode.snap:
        widget.removePicker();
        if (widget.calendar.monthViewSettings.navigationDirection == MonthNavigationDirection.horizontal ||
            widget.view != CalendarView.month) {
          final double difference = dragUpdateDetails.globalPosition.dx - _scrollStartPosition;
          if (difference < 0 &&
              !DateTimeHelper.canMoveToNextView(
                  widget.view,
                  widget.calendar.monthViewSettings.numberOfWeeksInView,
                  widget.calendar.minDate,
                  widget.calendar.maxDate,
                  _currentViewVisibleDates,
                  widget.calendar.timeSlotViewSettings.nonWorkingDays)) {
            _position = 0;
            return;
          } else if (difference > 0 &&
              !DateTimeHelper.canMoveToPreviousView(
                widget.view,
                widget.calendar.monthViewSettings.numberOfWeeksInView,
                widget.calendar.minDate,
                widget.calendar.maxDate,
                _currentViewVisibleDates,
                widget.calendar.timeSlotViewSettings.nonWorkingDays,
              )) {
            _position = 0;
            return;
          }
          _position = difference;
          _clearSelection();
          setState(() {
            /* Updates the widget navigated distance and moves the widget
       in the custom scroll view */
          });
        }
    }
  }

  void _onHorizontalEnd(DragEndDetails dragEndDetails) {
    switch (widget.calendar.viewNavigationMode) {
      case ViewNavigationMode.none:
        return;
      case ViewNavigationMode.snap:
        widget.removePicker();
        if (widget.calendar.monthViewSettings.navigationDirection == MonthNavigationDirection.horizontal ||
            widget.view != CalendarView.month) {
          // condition to check and update the right to left swiping
          if (-_position >= widget.width / 2) {
            _tween.begin = _position;
            _tween.end = -widget.width;

            // Resets the controller to forward it again,
            // the animation will forward only from the dismissed state
            if (_animationController.isCompleted && _position != _tween.end) {
              _animationController.reset();
            }

            _animationController.forward().then<dynamic>((dynamic value) => _updateNextView());

            /// updates the current view visible dates when the view swiped in
            /// right to left direction
            _updateCurrentViewVisibleDates(isNextView: true);
          }
          // fling the view from right to left
          else if (-dragEndDetails.velocity.pixelsPerSecond.dx > widget.width) {
            if (!DateTimeHelper.canMoveToNextView(
                widget.view,
                widget.calendar.monthViewSettings.numberOfWeeksInView,
                widget.calendar.minDate,
                widget.calendar.maxDate,
                _currentViewVisibleDates,
                widget.calendar.timeSlotViewSettings.nonWorkingDays)) {
              _position = 0;
              setState(() {
                /* Completes the swiping and rearrange the children position
                in the custom scroll view */
              });
              return;
            }

            _tween.begin = _position;
            _tween.end = -widget.width;

            // Resets the controller to forward it again, the animation will
            // forward only from the dismissed state
            if (_animationController.isCompleted && _position != _tween.end) {
              _animationController.reset();
            }

            _animationController
                .fling(velocity: 5.0, animationBehavior: AnimationBehavior.normal)
                .then<dynamic>((dynamic value) => _updateNextView());

            /// updates the current view visible dates when fling the view in
            /// right to left direction
            _updateCurrentViewVisibleDates(isNextView: true);
          }
          // condition to check and update the left to right swiping
          else if (_position >= widget.width / 2) {
            _tween.begin = _position;
            _tween.end = widget.width;

            // Resets the controller to forward it again, the animation will
            // forward only from the dismissed state
            if (_animationController.isCompleted || _position != _tween.end) {
              _animationController.reset();
            }

            _animationController.forward().then<dynamic>((dynamic value) => _updatePreviousView());

            /// updates the current view visible dates when the view swiped in
            /// left to right direction
            _updateCurrentViewVisibleDates();
          }
          // fling the view from left to right
          else if (dragEndDetails.velocity.pixelsPerSecond.dx > widget.width) {
            if (!DateTimeHelper.canMoveToPreviousView(
                widget.view,
                widget.calendar.monthViewSettings.numberOfWeeksInView,
                widget.calendar.minDate,
                widget.calendar.maxDate,
                _currentViewVisibleDates,
                widget.calendar.timeSlotViewSettings.nonWorkingDays)) {
              _position = 0;
              setState(() {
                /* Completes the swiping and rearrange the children position
            in the custom scroll view */
              });
              return;
            }

            _tween.begin = _position;
            _tween.end = widget.width;

            // Resets the controller to forward it again, the animation will
            // forward only from the dismissed state
            if (_animationController.isCompleted && _position != _tween.end) {
              _animationController.reset();
            }

            _animationController
                .fling(velocity: 5.0, animationBehavior: AnimationBehavior.normal)
                .then<dynamic>((dynamic value) => _updatePreviousView());

            /// updates the current view visible dates when fling the view in
            /// left to right direction
            _updateCurrentViewVisibleDates();
          }
          // condition to check and revert the right to left swiping
          else if (_position.abs() <= widget.width / 2) {
            _tween.begin = _position;
            _tween.end = 0.0;

            // Resets the controller to forward it again, the animation will
            // forward only from the dismissed state
            if (_animationController.isCompleted && _position != _tween.end) {
              _animationController.reset();
            }

            _animationController.forward();
          }
        }
    }
  }

  void _onVerticalStart(DragStartDetails dragStartDetails) {
    switch (widget.calendar.viewNavigationMode) {
      case ViewNavigationMode.none:
        return;
      case ViewNavigationMode.snap:
        widget.removePicker();
        if (widget.calendar.monthViewSettings.navigationDirection == MonthNavigationDirection.vertical &&
            !CalendarViewHelper.isTimelineView(widget.view)) {
          _scrollStartPosition = dragStartDetails.globalPosition.dy;
        }
    }
  }

  void _onVerticalUpdate(DragUpdateDetails dragUpdateDetails) {
    switch (widget.calendar.viewNavigationMode) {
      case ViewNavigationMode.none:
        return;
      case ViewNavigationMode.snap:
        widget.removePicker();
        if (widget.calendar.monthViewSettings.navigationDirection == MonthNavigationDirection.vertical &&
            !CalendarViewHelper.isTimelineView(widget.view)) {
          final double difference = dragUpdateDetails.globalPosition.dy - _scrollStartPosition;
          if (difference < 0 &&
              !DateTimeHelper.canMoveToNextView(
                  widget.view,
                  widget.calendar.monthViewSettings.numberOfWeeksInView,
                  widget.calendar.minDate,
                  widget.calendar.maxDate,
                  _currentViewVisibleDates,
                  widget.calendar.timeSlotViewSettings.nonWorkingDays)) {
            _position = 0;
            return;
          } else if (difference > 0 &&
              !DateTimeHelper.canMoveToPreviousView(
                  widget.view,
                  widget.calendar.monthViewSettings.numberOfWeeksInView,
                  widget.calendar.minDate,
                  widget.calendar.maxDate,
                  _currentViewVisibleDates,
                  widget.calendar.timeSlotViewSettings.nonWorkingDays)) {
            _position = 0;
            return;
          }
          _position = difference;
          setState(() {
            /* Updates the widget navigated distance and moves the widget
       in the custom scroll view */
          });
        }
    }
  }

  void _onVerticalEnd(DragEndDetails dragEndDetails) {
    switch (widget.calendar.viewNavigationMode) {
      case ViewNavigationMode.none:
        return;
      case ViewNavigationMode.snap:
        widget.removePicker();
        if (widget.calendar.monthViewSettings.navigationDirection == MonthNavigationDirection.vertical &&
            !CalendarViewHelper.isTimelineView(widget.view)) {
          // condition to check and update the bottom to top swiping
          if (-_position >= widget.height / 2) {
            _tween.begin = _position;
            _tween.end = -widget.height;

            // Resets the controller to forward it again, the animation will
            // forward only from the dismissed state
            if (_animationController.isCompleted || _position != _tween.end) {
              _animationController.reset();
            }

            _animationController.forward().then<dynamic>((dynamic value) => _updateNextView());

            /// updates the current view visible dates when the view swiped in
            /// bottom to top direction
            _updateCurrentViewVisibleDates(isNextView: true);
          }
          // fling the view to bottom to top
          else if (-dragEndDetails.velocity.pixelsPerSecond.dy > widget.height) {
            if (!DateTimeHelper.canMoveToNextView(
                widget.view,
                widget.calendar.monthViewSettings.numberOfWeeksInView,
                widget.calendar.minDate,
                widget.calendar.maxDate,
                _currentViewVisibleDates,
                widget.calendar.timeSlotViewSettings.nonWorkingDays)) {
              _position = 0;
              setState(() {
                /* Completes the swiping and rearrange the children position in
            the custom scroll view */
              });
              return;
            }

            _tween.begin = _position;
            _tween.end = -widget.height;

            // Resets the controller to forward it again, the animation will
            // forward only from the dismissed state
            if (_animationController.isCompleted || _position != _tween.end) {
              _animationController.reset();
            }

            _animationController
                .fling(velocity: 5.0, animationBehavior: AnimationBehavior.normal)
                .then<dynamic>((dynamic value) => _updateNextView());

            /// updates the current view visible dates when fling the view in
            /// bottom to top direction
            _updateCurrentViewVisibleDates(isNextView: true);
          }
          // condition to check and update the top to bottom swiping
          else if (_position >= widget.height / 2) {
            _tween.begin = _position;
            _tween.end = widget.height;

            // Resets the controller to forward it again, the animation will
            // forward only from the dismissed state
            if (_animationController.isCompleted || _position != _tween.end) {
              _animationController.reset();
            }

            _animationController.forward().then<dynamic>((dynamic value) => _updatePreviousView());

            /// updates the current view visible dates when the view swiped in
            /// top to bottom direction
            _updateCurrentViewVisibleDates();
          }
          // fling the view to top to bottom
          else if (dragEndDetails.velocity.pixelsPerSecond.dy > widget.height) {
            if (!DateTimeHelper.canMoveToPreviousView(
                widget.view,
                widget.calendar.monthViewSettings.numberOfWeeksInView,
                widget.calendar.minDate,
                widget.calendar.maxDate,
                _currentViewVisibleDates,
                widget.calendar.timeSlotViewSettings.nonWorkingDays)) {
              _position = 0;
              setState(() {
                /* Completes the swiping and rearrange the children position in
            the custom scroll view */
              });
              return;
            }

            _tween.begin = _position;
            _tween.end = widget.height;

            // Resets the controller to forward it again, the animation will
            // forward only from the dismissed state
            if (_animationController.isCompleted || _position != _tween.end) {
              _animationController.reset();
            }

            _animationController
                .fling(velocity: 5.0, animationBehavior: AnimationBehavior.normal)
                .then<dynamic>((dynamic value) => _updatePreviousView());

            /// updates the current view visible dates when fling the view in
            /// top to bottom direction
            _updateCurrentViewVisibleDates();
          }
          // condition to check and revert the bottom to top swiping
          else if (_position.abs() <= widget.height / 2) {
            _tween.begin = _position;
            _tween.end = 0.0;

            // Resets the controller to forward it again, the animation will
            // forward only from the dismissed state
            if (_animationController.isCompleted || _position != _tween.end) {
              _animationController.reset();
            }

            _animationController.forward();
          }
        }
    }
  }

  void _clearSelection() {
    widget.getCalendarState(_updateCalendarStateDetails);
    for (int i = 0; i < _children.length; i++) {
      final GlobalKey<_CalendarViewState> viewKey =
          // ignore: avoid_as
          _children[i].key! as GlobalKey<_CalendarViewState>;
      if (viewKey.currentState!._selectionPainter!.selectedDate != _updateCalendarStateDetails.selectedDate) {
        viewKey.currentState!._selectionPainter!.selectedDate = _updateCalendarStateDetails.selectedDate;
        viewKey.currentState!._selectionNotifier.value = !viewKey.currentState!._selectionNotifier.value;
      }
    }
  }

  /// Updates the all day panel of the view, when the all day panel expanded and
  /// the view swiped to next or previous view with the expanded all day panel,
  /// it will be collapsed.
  void _updateAllDayPanel() {
    GlobalKey<_CalendarViewState> viewKey;
    if (_currentChildIndex == 0) {
      viewKey = _previousViewKey;
    } else if (_currentChildIndex == 1) {
      viewKey = _currentViewKey;
    } else {
      viewKey = _nextViewKey;
    }
    if (viewKey.currentState!._expanderAnimationController?.status == AnimationStatus.completed) {
      viewKey.currentState!._expanderAnimationController?.reset();
    }
    viewKey.currentState!._isExpanded = false;
  }

  /// Method to clear the appointments in the previous/next view
  void _updateAppointmentPainter() {
    for (int i = 0; i < _children.length; i++) {
      final _CalendarView view = _children[i];
      final GlobalKey<_CalendarViewState> viewKey =
          // ignore: avoid_as
          view.key! as GlobalKey<_CalendarViewState>;
      if (widget.view == CalendarView.month && widget.calendar.monthCellBuilder != null) {
        if (view.visibleDates == _currentViewVisibleDates) {
          widget.getCalendarState(_updateCalendarStateDetails);
          if (!CalendarViewHelper.isCollectionEqual(viewKey.currentState!._monthView.visibleAppointmentNotifier.value,
              _updateCalendarStateDetails.visibleAppointments)) {
            viewKey.currentState!._monthView.visibleAppointmentNotifier.value = _updateCalendarStateDetails.visibleAppointments;
          }
        } else {
          if (!CalendarViewHelper.isEmptyList(viewKey.currentState!._monthView.visibleAppointmentNotifier.value)) {
            viewKey.currentState!._monthView.visibleAppointmentNotifier.value = null;
          }
        }
      } else {
        final AppointmentLayout appointmentLayout = viewKey.currentState!._appointmentLayout;
        if (view.visibleDates == _currentViewVisibleDates) {
          widget.getCalendarState(_updateCalendarStateDetails);
          if (!CalendarViewHelper.isCollectionEqual(
              appointmentLayout.visibleAppointments.value, _updateCalendarStateDetails.visibleAppointments)) {
            appointmentLayout.visibleAppointments.value = _updateCalendarStateDetails.visibleAppointments;
          }
        } else {
          if (!CalendarViewHelper.isEmptyList(appointmentLayout.visibleAppointments.value)) {
            appointmentLayout.visibleAppointments.value = null;
          }
        }
      }
    }
  }
}

@immutable
class _CalendarView extends StatefulWidget {
  const _CalendarView(
      this.calendar,
      this.view,
      this.visibleDates,
      this.width,
      this.height,
      this.agendaSelectedDate,
      this.locale,
      this.calendarTheme,
      this.regions,
      this.blackoutDates,
      this.focusNode,
      this.removePicker,
      this.allowViewNavigation,
      this.controller,
      this.resourcePanelScrollController,
      this.resourceCollection,
      this.textScaleFactor,
      this.minDate,
      this.maxDate,
      this.localizations,
      this.updateCalendarState,
      this.getCalendarState,
      {Key? key})
      : super(key: key);

  final List<DateTime> visibleDates;
  final List<CalendarTimeRegion>? regions;
  final List<DateTime>? blackoutDates;
  final SfCalendar calendar;
  final CalendarView view;
  final double width;
  final SfCalendarThemeData calendarTheme;
  final double height;
  final String locale;
  final ValueNotifier<DateTime?> agendaSelectedDate;
  final CalendarController controller;
  final VoidCallback removePicker;
  final UpdateCalendarState updateCalendarState;
  final UpdateCalendarState getCalendarState;
  final bool allowViewNavigation;
  final FocusNode focusNode;
  final ScrollController? resourcePanelScrollController;
  final List<CalendarResource>? resourceCollection;
  final double textScaleFactor;
  final DateTime minDate;
  final DateTime maxDate;
  final SfLocalizations localizations;

  @override
  _CalendarViewState createState() => _CalendarViewState();
}

class _CalendarViewState extends State<_CalendarView> with TickerProviderStateMixin {
  // line count is the total time slot lines to be drawn in the view
  // line count per view is for time line view which contains the time slot
  // count for per view
  double? _horizontalLinesCount;

  // all day scroll controller is used to identify the scroll position for draw
  // all day selection.
  ScrollController? _scrollController;
  ScrollController? _timelineViewHeaderScrollController, _timelineViewVerticalScrollController, _timelineRulerController;

  late AppointmentLayout _appointmentLayout;
  AnimationController? _timelineViewAnimationController;
  Animation<double>? _timelineViewAnimation;
  final Tween<double> _timelineViewTween = Tween<double>(begin: 0.0, end: 0.1);

  //// timeline header is used to implement the sticky view header in horizontal calendar view mode.
  late TimelineViewHeaderView _timelineViewHeader;
  _SelectionPainter? _selectionPainter;
  double _allDayHeight = 0;
  late double _timeIntervalHeight;
  final UpdateCalendarStateDetails _updateCalendarStateDetails = UpdateCalendarStateDetails();
  ValueNotifier<SelectionDetails?> _allDaySelectionNotifier = ValueNotifier<SelectionDetails?>(null);
  late ValueNotifier<Offset?> _viewHeaderNotifier;
  final ValueNotifier<bool> _selectionNotifier = ValueNotifier<bool>(false),
      _timelineViewHeaderNotifier = ValueNotifier<bool>(false);

  bool _isExpanded = false;

  /// The property to hold the resource value associated with the selected
  /// calendar cell.
  int _selectedResourceIndex = -1;
  AnimationController? _animationController;
  Animation<double>? _heightAnimation;
  Animation<double>? _allDayExpanderAnimation;
  AnimationController? _expanderAnimationController;

  /// Store the month widget instance used to update the month view
  /// when the visible appointment updated.
  late MonthViewWidget _monthView;

  /// Used to hold the global key for restrict the new appointment layout
  /// creation.
  /// if set the appointment layout key property as new Global key when create
  /// the appointment layout then each of the time it creates new appointment
  /// layout rather than update the existing appointment layout.
  final GlobalKey _appointmentLayoutKey = GlobalKey();

  Timer? _timer;
  late ValueNotifier<int> _currentTimeNotifier;

  @override
  void initState() {
    _viewHeaderNotifier = ValueNotifier<Offset?>(null);
    if (!CalendarViewHelper.isTimelineView(widget.view) && widget.view != CalendarView.month) {
      _animationController = AnimationController(duration: const Duration(milliseconds: 200), vsync: this);
      _heightAnimation = CurveTween(curve: Curves.easeIn).animate(_animationController!)
        ..addListener(() {
          setState(() {
            /* Animates the all day panel height when
              expanding or collapsing */
          });
        });

      _expanderAnimationController = AnimationController(duration: const Duration(milliseconds: 100), vsync: this);
      _allDayExpanderAnimation = CurveTween(curve: Curves.easeIn).animate(_expanderAnimationController!)
        ..addListener(() {
          setState(() {
            /* Animates the all day panel height when
              expanding or collapsing */
          });
        });
    }

    _timeIntervalHeight = _getTimeIntervalHeight(
        widget.calendar, widget.view, widget.width, widget.height, widget.visibleDates.length, _allDayHeight);
    if (widget.view != CalendarView.month) {
      _horizontalLinesCount = CalendarViewHelper.getHorizontalLinesCount(widget.calendar.timeSlotViewSettings, widget.view);
      _scrollController = ScrollController(initialScrollOffset: 0, keepScrollOffset: true)..addListener(_scrollListener);
      if (CalendarViewHelper.isTimelineView(widget.view)) {
        _timelineRulerController = ScrollController(initialScrollOffset: 0, keepScrollOffset: true)
          ..addListener(_timeRulerListener);
        _timelineViewHeaderScrollController = ScrollController(initialScrollOffset: 0, keepScrollOffset: true);
        _timelineViewAnimationController = AnimationController(
            duration: const Duration(milliseconds: 300), vsync: this, animationBehavior: AnimationBehavior.normal);
        _timelineViewAnimation = _timelineViewTween.animate(_timelineViewAnimationController!)
          ..addListener(_scrollAnimationListener);
        _timelineViewVerticalScrollController = ScrollController(initialScrollOffset: 0, keepScrollOffset: true)
          ..addListener(_updateResourceScroll);
        widget.resourcePanelScrollController?.addListener(_updateResourcePanelScroll);
      }

      _scrollToPosition();
    }

    final DateTime today = DateTime.now();
    _currentTimeNotifier = ValueNotifier<int>((today.day * 24 * 60) + (today.hour * 60) + today.minute);
    _timer = _createTimer();
    super.initState();
  }

  @override
  void didUpdateWidget(_CalendarView oldWidget) {
    final bool isTimelineView = CalendarViewHelper.isTimelineView(widget.view);
    if (widget.view != CalendarView.month) {
      if (!isTimelineView) {
        _updateTimeSlotView(oldWidget);
      }

      _updateHorizontalLineCount(oldWidget);

      _scrollController ??= ScrollController(initialScrollOffset: 0, keepScrollOffset: true)..addListener(_scrollListener);

      if (isTimelineView) {
        _updateTimelineViews(oldWidget);
      }
    }

    /// Update the scroll position with following scenarios
    /// 1. View changed from month or schedule view.
    /// 2. View changed from timeline view(timeline day, timeline week,
    /// timeline work week) to timeslot view(day, week, work week).
    /// 3. View changed from timeslot view(day, week, work week) to
    /// timeline view(timeline day, timeline week, timeline work week).
    ///
    /// This condition used to restrict the following scenarios
    /// 1. View changed to month view.
    /// 2. View changed with in the day, week, work week
    /// (eg., view changed to week from day).
    /// 3. View changed with in the timeline day, timeline week, timeline
    /// work week(eg., view changed to timeline week from timeline day).
    if ((oldWidget.view == CalendarView.month ||
            oldWidget.view == CalendarView.schedule ||
            (oldWidget.view != widget.view && isTimelineView) ||
            (CalendarViewHelper.isTimelineView(oldWidget.view) && !isTimelineView)) &&
        widget.view != CalendarView.month) {
      _scrollToPosition();
    }

    /// Method called to update all day height, when the view changed from
    /// day to week views to avoid the blank space at the bottom of the view.
    final bool isCurrentView = _updateCalendarStateDetails.currentViewVisibleDates == widget.visibleDates;
    _updateAllDayHeight(isCurrentView);

    _timeIntervalHeight = _getTimeIntervalHeight(
        widget.calendar, widget.view, widget.width, widget.height, widget.visibleDates.length, _allDayHeight);

    /// Clear the all day panel selection when the calendar view changed
    /// Eg., if select the all day panel and switch to month view and again
    /// select the same month cell and move to day view then the view show
    /// calendar cell selection and all day panel selection.
    if (oldWidget.view != widget.view) {
      _allDaySelectionNotifier = ValueNotifier<SelectionDetails?>(null);
      final DateTime today = DateTime.now();
      _currentTimeNotifier = ValueNotifier<int>((today.day * 24 * 60) + (today.hour * 60) + today.minute);
      _timer?.cancel();
      _timer = null;
    }

    if (oldWidget.calendar.showCurrentTimeIndicator != widget.calendar.showCurrentTimeIndicator) {
      _timer?.cancel();
      _timer = _createTimer();
    }

    if ((oldWidget.view != widget.view || oldWidget.width != widget.width || oldWidget.height != widget.height) &&
        _selectionPainter!.appointmentView != null) {
      _selectionPainter!.appointmentView = null;
    }

    /// When view switched from any other view to timeline view, and resource
    /// enabled the selection must render the first resource view.
    widget.getCalendarState(_updateCalendarStateDetails);
    if (!CalendarViewHelper.isTimelineView(oldWidget.view) &&
        _updateCalendarStateDetails.selectedDate != null &&
        CalendarViewHelper.isResourceEnabled(widget.calendar.dataSource, widget.view) &&
        _selectedResourceIndex == -1) {
      _selectedResourceIndex = 0;
    }

    if (!CalendarViewHelper.isResourceEnabled(widget.calendar.dataSource, widget.view)) {
      _selectedResourceIndex = -1;
    }

    _timer ??= _createTimer();
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    widget.getCalendarState(_updateCalendarStateDetails);
    switch (widget.view) {
      case CalendarView.schedule:
        return Container();
      case CalendarView.month:
        return _getMonthView();
      case CalendarView.day:
      case CalendarView.week:
      case CalendarView.workWeek:
        return _getDayView();
      case CalendarView.timelineDay:
      case CalendarView.timelineWeek:
      case CalendarView.timelineWorkWeek:
      case CalendarView.timelineMonth:
        return _getTimelineView();
    }
  }

  @override
  void dispose() {
    if (_timelineViewAnimation != null) {
      _timelineViewAnimation!.removeListener(_scrollAnimationListener);
    }

    if (widget.resourcePanelScrollController != null) {
      widget.resourcePanelScrollController!.removeListener(_updateResourcePanelScroll);
    }

    if (CalendarViewHelper.isTimelineView(widget.view) && _timelineViewAnimationController != null) {
      _timelineViewAnimationController!.dispose();
      _timelineViewAnimationController = null;
    }
    if (_scrollController != null) {
      _scrollController!.removeListener(_scrollListener);
      _scrollController!.dispose();
      _scrollController = null;
    }
    if (_timelineViewHeaderScrollController != null) {
      _timelineViewHeaderScrollController!.dispose();
      _timelineViewHeaderScrollController = null;
    }
    if (_animationController != null) {
      _animationController!.dispose();
      _animationController = null;
    }
    if (_timelineRulerController != null) {
      _timelineRulerController!.dispose();
      _timelineRulerController = null;
    }

    if (_expanderAnimationController != null) {
      _expanderAnimationController!.dispose();
      _expanderAnimationController = null;
    }

    if (_timer != null) {
      _timer!.cancel();
      _timer = null;
    }

    super.dispose();
  }

  Timer? _createTimer() {
    return widget.calendar.showCurrentTimeIndicator &&
            widget.view != CalendarView.month &&
            widget.view != CalendarView.timelineMonth
        ? Timer.periodic(const Duration(seconds: 1), (Timer t) {
            final DateTime today = DateTime.now();
            final DateTime viewEndDate = widget.visibleDates[widget.visibleDates.length - 1];

            /// Check the today date is in between visible date range and
            /// today date hour and minute is 0(12 AM) because in day view
            /// current time as Feb 16, 23.59 and changed to Feb 17 then view
            /// will update both Feb 16 and 17 views.
            if (!isDateWithInDateRange(widget.visibleDates[0], viewEndDate, today) &&
                !(today.hour == 0 && today.minute == 0 && isSameDate(addDays(today, -1), viewEndDate))) {
              return;
            }

            _currentTimeNotifier.value = (today.day * 24 * 60) + (today.hour * 60) + today.minute;
          })
        : null;
  }

  /// Updates the resource panel scroll based on timeline scroll in vertical
  /// direction.
  void _updateResourcePanelScroll() {
    if (_updateCalendarStateDetails.currentViewVisibleDates == widget.visibleDates) {
      widget.removePicker();
    }

    if (widget.resourcePanelScrollController == null ||
        !CalendarViewHelper.isResourceEnabled(widget.calendar.dataSource, widget.view)) {
      return;
    }

    if (widget.resourcePanelScrollController!.offset != _timelineViewVerticalScrollController!.offset) {
      _timelineViewVerticalScrollController!.jumpTo(widget.resourcePanelScrollController!.offset);
    }
  }

  /// Updates the timeline view scroll in vertical direction based on resource
  /// panel scroll.
  void _updateResourceScroll() {
    if (_updateCalendarStateDetails.currentViewVisibleDates == widget.visibleDates) {
      widget.removePicker();
    }

    if (widget.resourcePanelScrollController == null ||
        !CalendarViewHelper.isResourceEnabled(widget.calendar.dataSource, widget.view)) {
      return;
    }

    if (widget.resourcePanelScrollController!.offset != _timelineViewVerticalScrollController!.offset) {
      widget.resourcePanelScrollController!.jumpTo(_timelineViewVerticalScrollController!.offset);
    }
  }

  Widget _getMonthView() {
    return GestureDetector(
      child: Container(
        width: widget.width,
        height: widget.height,
        child: _addMonthView(widget.locale),
      ),
      onTapUp: (TapUpDetails details) {
        _handleOnTapForMonth(details);
      },
      onLongPressStart: (LongPressStartDetails details) {
        _handleOnLongPressForMonth(details);
      },
    );
  }

  Widget _getDayView() {
    final bool isCurrentView = _updateCalendarStateDetails.currentViewVisibleDates == widget.visibleDates;
    _updateAllDayHeight(isCurrentView);

    return GestureDetector(
      child: Container(
        height: widget.height,
        width: widget.width,
        child: _addDayView(widget.width, _timeIntervalHeight * _horizontalLinesCount!, widget.locale, isCurrentView),
      ),
      onTapUp: (TapUpDetails details) {
        _handleOnTapForDay(details);
      },
      onLongPressStart: (LongPressStartDetails details) {
        _handleOnLongPressForDay(details);
      },
    );
  }

  /// Method to update allDayHeight calculation for day, week and work week
  /// view, based on the view also based on the timeIntervalHeight.
  void _updateAllDayHeight(bool isCurrentView) {
    if (widget.view != CalendarView.day && widget.view != CalendarView.week && widget.view != CalendarView.workWeek) {
      return;
    }

    _allDayHeight = 0;
    if (widget.view == CalendarView.day) {
      final double viewHeaderHeight = CalendarViewHelper.getViewHeaderHeight(widget.calendar.viewHeaderHeight, widget.view);
      if (isCurrentView) {
        _allDayHeight =
            _kAllDayLayoutHeight > viewHeaderHeight && _updateCalendarStateDetails.allDayPanelHeight > viewHeaderHeight
                ? _updateCalendarStateDetails.allDayPanelHeight > _kAllDayLayoutHeight
                    ? _kAllDayLayoutHeight
                    : _updateCalendarStateDetails.allDayPanelHeight
                : viewHeaderHeight;
        if (_allDayHeight < _updateCalendarStateDetails.allDayPanelHeight) {
          _allDayHeight += kAllDayAppointmentHeight;
        }
      } else {
        _allDayHeight = viewHeaderHeight;
      }
    } else if (isCurrentView) {
      _allDayHeight = _updateCalendarStateDetails.allDayPanelHeight > _kAllDayLayoutHeight
          ? _kAllDayLayoutHeight
          : _updateCalendarStateDetails.allDayPanelHeight;
      _allDayHeight = _allDayHeight * _heightAnimation!.value;
    }
  }

  Widget _getTimelineView() {
    return GestureDetector(
      child: Container(
        width: widget.width,
        height: widget.height,
        child: _addTimelineView(
          _timeIntervalHeight * (_horizontalLinesCount! * widget.visibleDates.length),
          widget.height,
          widget.locale,
        ),
      ),
      onTapUp: (TapUpDetails details) {
        _handleOnTapForTimeline(details);
      },
      onLongPressStart: (LongPressStartDetails details) {
        _handleOnLongPressForTimeline(details);
      },
    );
  }

  void _scrollAnimationListener() {
    _scrollController!.jumpTo(_timelineViewAnimation!.value);
  }

  void _scrollToPosition() {
    SchedulerBinding.instance!.addPostFrameCallback((_) {
      if (widget.view == CalendarView.month) {
        return;
      }

      widget.getCalendarState(_updateCalendarStateDetails);
      final double scrollPosition = _getScrollPositionForCurrentDate(_updateCalendarStateDetails.currentDate!);
      if (scrollPosition == -1 || _scrollController!.position.pixels == scrollPosition) {
        return;
      }

      _scrollController!.jumpTo(_scrollController!.position.maxScrollExtent > scrollPosition
          ? scrollPosition
          : _scrollController!.position.maxScrollExtent);
    });
  }

  double _getScrollPositionForCurrentDate(DateTime date) {
    final int visibleDatesCount = widget.visibleDates.length;
    if (!isDateWithInDateRange(widget.visibleDates[0], widget.visibleDates[visibleDatesCount - 1], date)) {
      return -1;
    }

    double timeToPosition = 0;
    if (!CalendarViewHelper.isTimelineView(widget.view)) {
      timeToPosition = AppointmentHelper.timeToPosition(widget.calendar, date, _timeIntervalHeight);
    } else {
      for (int i = 0; i < visibleDatesCount; i++) {
        if (!isSameDate(date, widget.visibleDates[i])) {
          continue;
        }

        if (widget.view == CalendarView.timelineMonth) {
          timeToPosition = _timeIntervalHeight * i;
        } else {
          timeToPosition = (_getSingleViewWidthForTimeLineView(this) * i) +
              AppointmentHelper.timeToPosition(widget.calendar, date, _timeIntervalHeight);
        }

        break;
      }
    }

    if (_scrollController!.hasClients) {
      if (timeToPosition > _scrollController!.position.maxScrollExtent) {
        timeToPosition = _scrollController!.position.maxScrollExtent;
      } else if (timeToPosition < _scrollController!.position.minScrollExtent) {
        timeToPosition = _scrollController!.position.minScrollExtent;
      }
    }

    return timeToPosition;
  }

  /// Used to retain the scrolled date time.
  void _retainScrolledDateTime() {
    if (widget.view == CalendarView.month) {
      return;
    }

    DateTime scrolledDate = widget.visibleDates[0];
    double scrolledPosition = 0;
    if (CalendarViewHelper.isTimelineView(widget.view)) {
      final double singleViewWidth = _getSingleViewWidthForTimeLineView(this);

      /// Calculate the scrolled position date.
      scrolledDate = widget.visibleDates[_scrollController!.position.pixels ~/ singleViewWidth];

      /// Calculate the scrolled hour position without visible date position.
      scrolledPosition = _scrollController!.position.pixels % singleViewWidth;
    } else {
      /// Calculate the scrolled hour position.
      scrolledPosition = _scrollController!.position.pixels;
    }

    /// Calculate the current horizontal line based on time interval height.
    final double columnIndex = scrolledPosition / _timeIntervalHeight;

    /// Calculate the time based on calculated horizontal position.
    final double time = ((CalendarViewHelper.getTimeInterval(widget.calendar.timeSlotViewSettings) / 60) * columnIndex) +
        widget.calendar.timeSlotViewSettings.startHour;
    final int hour = time.toInt();
    final int minute = ((time - hour) * 60).round();
    scrolledDate = DateTime(scrolledDate.year, scrolledDate.month, scrolledDate.day, hour, minute);

    /// Update the scrolled position after the widget generated.
    SchedulerBinding.instance!.addPostFrameCallback((_) {
      _scrollController!.jumpTo(_getPositionFromDate(scrolledDate));
    });
  }

  /// Calculate the position from date.
  double _getPositionFromDate(DateTime date) {
    final int visibleDatesCount = widget.visibleDates.length;
    _timeIntervalHeight =
        _getTimeIntervalHeight(widget.calendar, widget.view, widget.width, widget.height, visibleDatesCount, _allDayHeight);
    double timeToPosition = 0;
    final bool isTimelineView = CalendarViewHelper.isTimelineView(widget.view);
    if (!isTimelineView) {
      timeToPosition = AppointmentHelper.timeToPosition(widget.calendar, date, _timeIntervalHeight);
    } else {
      for (int i = 0; i < visibleDatesCount; i++) {
        if (!isSameDate(date, widget.visibleDates[i])) {
          continue;
        }

        if (widget.view == CalendarView.timelineMonth) {
          timeToPosition = _timeIntervalHeight * i;
        } else {
          timeToPosition = (_getSingleViewWidthForTimeLineView(this) * i) +
              AppointmentHelper.timeToPosition(widget.calendar, date, _timeIntervalHeight);
        }

        break;
      }
    }

    double maxScrollPosition = 0;
    if (!isTimelineView) {
      final double scrollViewHeight =
          widget.height - _allDayHeight - CalendarViewHelper.getViewHeaderHeight(widget.calendar.viewHeaderHeight, widget.view);
      final double scrollViewContentHeight =
          CalendarViewHelper.getHorizontalLinesCount(widget.calendar.timeSlotViewSettings, widget.view) * _timeIntervalHeight;
      maxScrollPosition = scrollViewContentHeight - scrollViewHeight;
    } else {
      final double scrollViewContentWidth =
          CalendarViewHelper.getHorizontalLinesCount(widget.calendar.timeSlotViewSettings, widget.view) *
              _timeIntervalHeight *
              visibleDatesCount;
      maxScrollPosition = scrollViewContentWidth - widget.width;
    }

    return maxScrollPosition > timeToPosition ? timeToPosition : maxScrollPosition;
  }

  void _expandOrCollapseAllDay() {
    _isExpanded = !_isExpanded;
    if (_isExpanded) {
      _expanderAnimationController!.forward();
    } else {
      _expanderAnimationController!.reverse();
    }
  }

  /// Update the time slot view scroll based on time ruler view scroll in
  /// timeslot views.
  void _timeRulerListener() {
    if (!CalendarViewHelper.isTimelineView(widget.view)) {
      return;
    }

    if (_timelineRulerController!.offset != _scrollController!.offset) {
      _scrollController!.jumpTo(_timelineRulerController!.offset);
    }
  }

  void _scrollListener() {
    if (_updateCalendarStateDetails.currentViewVisibleDates == widget.visibleDates) {
      widget.removePicker();
    }

    if (CalendarViewHelper.isTimelineView(widget.view)) {
      widget.getCalendarState(_updateCalendarStateDetails);
      if (widget.view != CalendarView.timelineMonth) {
        _timelineViewHeaderNotifier.value = !_timelineViewHeaderNotifier.value;
      }

      if (_timelineRulerController!.offset != _scrollController!.offset) {
        _timelineRulerController!.jumpTo(_scrollController!.offset);
      }

      _timelineViewHeaderScrollController!.jumpTo(_scrollController!.offset);
    }
  }

  void _updateTimeSlotView(_CalendarView oldWidget) {
    _animationController ??= AnimationController(duration: const Duration(milliseconds: 200), vsync: this);
    _heightAnimation ??= CurveTween(curve: Curves.easeIn).animate(_animationController!)
      ..addListener(() {
        setState(() {
          /*Animates the all day panel when it's expanding or
        collapsing*/
        });
      });

    _expanderAnimationController ??= AnimationController(duration: const Duration(milliseconds: 100), vsync: this);
    _allDayExpanderAnimation ??= CurveTween(curve: Curves.easeIn).animate(_expanderAnimationController!)
      ..addListener(() {
        setState(() {
          /*Animates the all day panel when it's expanding or
        collapsing*/
        });
      });

    if (widget.view != CalendarView.day && _allDayHeight == 0) {
      if (_animationController!.status == AnimationStatus.completed) {
        _animationController!.reset();
      }

      _animationController!.forward();
    }
  }

  void _updateHorizontalLineCount(_CalendarView oldWidget) {
    if (widget.calendar.timeSlotViewSettings.startHour != oldWidget.calendar.timeSlotViewSettings.startHour ||
        widget.calendar.timeSlotViewSettings.endHour != oldWidget.calendar.timeSlotViewSettings.endHour ||
        CalendarViewHelper.getTimeInterval(widget.calendar.timeSlotViewSettings) !=
            CalendarViewHelper.getTimeInterval(oldWidget.calendar.timeSlotViewSettings) ||
        oldWidget.view == CalendarView.month ||
        oldWidget.view == CalendarView.timelineMonth ||
        oldWidget.view != CalendarView.timelineMonth && widget.view == CalendarView.timelineMonth) {
      _horizontalLinesCount = CalendarViewHelper.getHorizontalLinesCount(widget.calendar.timeSlotViewSettings, widget.view);
    } else {
      _horizontalLinesCount =
          _horizontalLinesCount ?? CalendarViewHelper.getHorizontalLinesCount(widget.calendar.timeSlotViewSettings, widget.view);
    }
  }

  void _updateTimelineViews(_CalendarView oldWidget) {
    _timelineRulerController ??= ScrollController(initialScrollOffset: 0, keepScrollOffset: true)
      ..addListener(_timeRulerListener);

    _timelineViewAnimationController ??= AnimationController(
        duration: const Duration(milliseconds: 300), vsync: this, animationBehavior: AnimationBehavior.normal);

    _timelineViewAnimation ??= _timelineViewTween.animate(_timelineViewAnimationController!)
      ..addListener(_scrollAnimationListener);

    _timelineViewHeaderScrollController ??= ScrollController(initialScrollOffset: 0, keepScrollOffset: true);
    _timelineViewVerticalScrollController = ScrollController(initialScrollOffset: 0, keepScrollOffset: true);
    _timelineViewVerticalScrollController!.addListener(_updateResourceScroll);
    widget.resourcePanelScrollController?.addListener(_updateResourcePanelScroll);
  }

  void _getPainterProperties(UpdateCalendarStateDetails details) {
    widget.getCalendarState(_updateCalendarStateDetails);
    details.allDayAppointmentViewCollection = _updateCalendarStateDetails.allDayAppointmentViewCollection;
    details.currentViewVisibleDates = _updateCalendarStateDetails.currentViewVisibleDates;
    details.visibleAppointments = _updateCalendarStateDetails.visibleAppointments;
    details.selectedDate = _updateCalendarStateDetails.selectedDate;
  }

  Widget _addAllDayAppointmentPanel(SfCalendarThemeData calendarTheme, bool isCurrentView) {
    final Color borderColor = widget.calendar.cellBorderColor ?? calendarTheme.cellBorderColor;
    final Widget shadowView = Divider(
      height: 1,
      thickness: 1,
      color: borderColor.withOpacity(borderColor.opacity * 0.5),
    );

    final double timeLabelWidth =
        CalendarViewHelper.getTimeLabelWidth(widget.calendar.timeSlotViewSettings.timeRulerSize, widget.view);
    double topPosition = CalendarViewHelper.getViewHeaderHeight(widget.calendar.viewHeaderHeight, widget.view);
    if (widget.view == CalendarView.day) {
      topPosition = _allDayHeight;
    }

    if (_allDayHeight == 0 ||
        (widget.view != CalendarView.day && widget.visibleDates != _updateCalendarStateDetails.currentViewVisibleDates)) {
      return Positioned(left: 0, right: 0, top: topPosition, height: 1, child: shadowView);
    }

    if (widget.view == CalendarView.day) {
      //// Default minimum view header width in day view as 50,so set 50
      //// when view header width less than 50.
      topPosition = 0;
    }

    double panelHeight = isCurrentView ? _updateCalendarStateDetails.allDayPanelHeight - _allDayHeight : 0;
    if (panelHeight < 0) {
      panelHeight = 0;
    }

    /// Remove the all day appointment selection when the selected all
    /// day appointment removed.
    if (_allDaySelectionNotifier.value != null &&
        _allDaySelectionNotifier.value!.appointmentView != null &&
        (!_updateCalendarStateDetails.visibleAppointments
            .contains(_allDaySelectionNotifier.value!.appointmentView!.appointment))) {
      _allDaySelectionNotifier.value = null;
    }

    final double allDayExpanderHeight = _allDayHeight + (panelHeight * _allDayExpanderAnimation!.value);
    return Positioned(
      left: 0,
      top: topPosition,
      right: 0,
      height: allDayExpanderHeight,
      child: Stack(
        children: <Widget>[
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            height: _isExpanded ? allDayExpanderHeight : _allDayHeight,
            child: ListView(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(0.0),
              children: <Widget>[
                AllDayAppointmentLayout(
                    widget.calendar,
                    widget.view,
                    widget.visibleDates,
                    widget.visibleDates == _updateCalendarStateDetails.currentViewVisibleDates
                        ? _updateCalendarStateDetails.visibleAppointments
                        : null,
                    timeLabelWidth,
                    allDayExpanderHeight,
                    panelHeight > 0 && (_heightAnimation!.value == 1 || widget.view == CalendarView.day),
                    _allDayExpanderAnimation!.value != 0.0 && _allDayExpanderAnimation!.value != 1,
                    widget.calendarTheme,
                    _allDaySelectionNotifier,
                    widget.textScaleFactor,
                    widget.width,
                    (widget.view == CalendarView.day && _updateCalendarStateDetails.allDayPanelHeight < _allDayHeight) ||
                            !isCurrentView
                        ? _allDayHeight
                        : _updateCalendarStateDetails.allDayPanelHeight,
                    widget.localizations,
                    _getPainterProperties),
              ],
            ),
          ),
          Positioned(left: 0, top: allDayExpanderHeight - 1, right: 0, height: 1, child: shadowView),
        ],
      ),
    );
  }

  AppointmentLayout _addAppointmentPainter(double width, double height, [double? resourceItemHeight]) {
    final List<CalendarAppointment>? visibleAppointments =
        widget.visibleDates == _updateCalendarStateDetails.currentViewVisibleDates
            ? _updateCalendarStateDetails.visibleAppointments
            : null;
    _appointmentLayout = AppointmentLayout(
      widget.calendar,
      widget.view,
      widget.visibleDates,
      ValueNotifier<List<CalendarAppointment>?>(visibleAppointments),
      _timeIntervalHeight,
      widget.calendarTheme,
      widget.resourceCollection,
      resourceItemHeight,
      widget.textScaleFactor,
      width,
      height,
      widget.localizations,
      _getPainterProperties,
      key: _appointmentLayoutKey,
    );

    return _appointmentLayout;
  }

  // Returns the month view  as a child for the calendar view.
  Widget _addMonthView(String locale) {
    final double viewHeaderHeight = CalendarViewHelper.getViewHeaderHeight(widget.calendar.viewHeaderHeight, widget.view);
    final double height = widget.height - viewHeaderHeight;
    return Stack(
      children: <Widget>[
        Positioned(
          left: 0,
          top: 0,
          right: 0,
          height: viewHeaderHeight,
          child: Container(
            color: widget.calendar.viewHeaderStyle.backgroundColor ?? widget.calendarTheme.viewHeaderBackgroundColor,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _ViewHeaderViewPainter(
                    widget.visibleDates,
                    widget.view,
                    widget.calendar.viewHeaderStyle,
                    widget.calendar.timeSlotViewSettings,
                    CalendarViewHelper.getTimeLabelWidth(widget.calendar.timeSlotViewSettings.timeRulerSize, widget.view),
                    CalendarViewHelper.getViewHeaderHeight(widget.calendar.viewHeaderHeight, widget.view),
                    widget.calendar.monthViewSettings,
                    widget.locale,
                    widget.calendarTheme,
                    widget.calendar.todayHighlightColor ?? widget.calendarTheme.todayHighlightColor,
                    widget.calendar.todayTextStyle,
                    widget.calendar.cellBorderColor,
                    widget.calendar.minDate,
                    widget.calendar.maxDate,
                    _viewHeaderNotifier,
                    widget.textScaleFactor,
                    widget.calendar.showWeekNumber,
                    widget.calendar.weekNumberStyle),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: viewHeaderHeight,
          right: 0,
          bottom: 0,
          child: RepaintBoundary(
            child: _CalendarMultiChildContainer(
              width: widget.width,
              height: height,
              children: <Widget>[
                RepaintBoundary(child: _getMonthWidget(height)),
                RepaintBoundary(child: _addAppointmentPainter(widget.width, height)),
              ],
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: viewHeaderHeight,
          right: 0,
          bottom: 0,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _addSelectionView(),
              size: Size(widget.width, height),
            ),
          ),
        ),
      ],
    );
  }

  Widget _getMonthWidget(double height) {
    final List<CalendarAppointment>? visibleAppointments =
        widget.visibleDates == _updateCalendarStateDetails.currentViewVisibleDates
            ? _updateCalendarStateDetails.visibleAppointments
            : null;
    _monthView = MonthViewWidget(
        widget.visibleDates,
        widget.calendar.monthViewSettings.numberOfWeeksInView,
        widget.calendar.monthViewSettings.monthCellStyle,
        widget.calendar.todayHighlightColor ?? widget.calendarTheme.todayHighlightColor,
        widget.calendar.todayTextStyle,
        widget.calendar.cellBorderColor,
        widget.calendarTheme,
        widget.calendar.monthViewSettings.showTrailingAndLeadingDates,
        widget.calendar.minDate,
        widget.calendar.maxDate,
        widget.calendar,
        widget.blackoutDates,
        widget.calendar.blackoutDatesTextStyle,
        widget.textScaleFactor,
        widget.calendar.monthCellBuilder,
        widget.width,
        height,
        widget.calendar.weekNumberStyle,
        ValueNotifier<List<CalendarAppointment>?>(visibleAppointments));
    return _monthView;
  }

  // Returns the day view as a child for the calendar view.
  Widget _addDayView(double width, double height, String locale, bool isCurrentView) {
    double viewHeaderWidth = widget.width;
    final double actualViewHeaderHeight = CalendarViewHelper.getViewHeaderHeight(widget.calendar.viewHeaderHeight, widget.view);
    double viewHeaderHeight = actualViewHeaderHeight;
    final double timeLabelWidth =
        CalendarViewHelper.getTimeLabelWidth(widget.calendar.timeSlotViewSettings.timeRulerSize, widget.view);
    if (widget.view == CalendarView.day) {
      viewHeaderWidth = timeLabelWidth < 50 ? 50 : timeLabelWidth;
      viewHeaderHeight = _allDayHeight > viewHeaderHeight ? _allDayHeight : viewHeaderHeight;
    }

    double panelHeight = isCurrentView ? _updateCalendarStateDetails.allDayPanelHeight - _allDayHeight : 0;
    if (panelHeight < 0) {
      panelHeight = 0;
    }

    final double allDayExpanderHeight = panelHeight * _allDayExpanderAnimation!.value;
    return Stack(
      children: <Widget>[
        _addAllDayAppointmentPanel(widget.calendarTheme, isCurrentView),
        Positioned(
          left: 0,
          top: 0,
          right: widget.width - viewHeaderWidth,
          height: actualViewHeaderHeight,
          child: Container(
            color: widget.calendar.viewHeaderStyle.backgroundColor ?? widget.calendarTheme.viewHeaderBackgroundColor,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _ViewHeaderViewPainter(
                    widget.visibleDates,
                    widget.view,
                    widget.calendar.viewHeaderStyle,
                    widget.calendar.timeSlotViewSettings,
                    CalendarViewHelper.getTimeLabelWidth(widget.calendar.timeSlotViewSettings.timeRulerSize, widget.view),
                    actualViewHeaderHeight,
                    widget.calendar.monthViewSettings,
                    widget.locale,
                    widget.calendarTheme,
                    widget.calendar.todayHighlightColor ?? widget.calendarTheme.todayHighlightColor,
                    widget.calendar.todayTextStyle,
                    widget.calendar.cellBorderColor,
                    widget.calendar.minDate,
                    widget.calendar.maxDate,
                    _viewHeaderNotifier,
                    widget.textScaleFactor,
                    widget.calendar.showWeekNumber,
                    widget.calendar.weekNumberStyle),
              ),
            ),
          ),
        ),
        Positioned(
            top: (widget.view == CalendarView.day)
                ? viewHeaderHeight + allDayExpanderHeight
                : viewHeaderHeight + _allDayHeight + allDayExpanderHeight,
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
                child: Scrollbar(
              controller: _scrollController,
              isAlwaysShown: false,
              child: ListView(
                  padding: const EdgeInsets.all(0.0),
                  controller: _scrollController,
                  scrollDirection: Axis.vertical,
                  physics: const ClampingScrollPhysics(),
                  children: <Widget>[
                    Stack(children: <Widget>[
                      RepaintBoundary(
                          child: _CalendarMultiChildContainer(width: width, height: height, children: <Widget>[
                        RepaintBoundary(
                          child: TimeSlotWidget(
                              widget.visibleDates,
                              _horizontalLinesCount!,
                              _timeIntervalHeight,
                              timeLabelWidth,
                              widget.calendar.cellBorderColor,
                              widget.calendarTheme,
                              widget.calendar.timeSlotViewSettings,
                              widget.regions,
                              widget.textScaleFactor,
                              widget.calendar.timeRegionBuilder,
                              width,
                              height,
                              widget.calendar.minDate,
                              widget.calendar.maxDate),
                        ),
                        RepaintBoundary(child: _addAppointmentPainter(width, height)),
                      ])),
                      RepaintBoundary(
                        child: CustomPaint(
                          painter: _TimeRulerView(
                              _horizontalLinesCount!,
                              _timeIntervalHeight,
                              widget.calendar.timeSlotViewSettings,
                              widget.calendar.cellBorderColor,
                              widget.locale,
                              widget.calendarTheme,
                              CalendarViewHelper.isTimelineView(widget.view),
                              widget.visibleDates,
                              widget.textScaleFactor),
                          size: Size(timeLabelWidth, height),
                        ),
                      ),
                      RepaintBoundary(
                        child: CustomPaint(
                          painter: _addSelectionView(),
                          size: Size(width, height),
                        ),
                      ),
                      _getCurrentTimeIndicator(timeLabelWidth, width, height, false),
                    ])
                  ]),
            ))),
      ],
    );
  }

  Widget _getCurrentTimeIndicator(double timeLabelSize, double width, double height, bool isTimelineView) {
    if (!widget.calendar.showCurrentTimeIndicator || widget.view == CalendarView.timelineMonth) {
      return Container(
        width: 0,
        height: 0,
      );
    }

    return RepaintBoundary(
      child: CustomPaint(
        painter: _CurrentTimeIndicator(
          _timeIntervalHeight,
          timeLabelSize,
          widget.calendar.timeSlotViewSettings,
          isTimelineView,
          widget.visibleDates,
          widget.calendar.todayHighlightColor ?? widget.calendarTheme.todayHighlightColor,
          _currentTimeNotifier,
        ),
        size: Size(width, height),
      ),
    );
  }

  /// Updates the cell selection when the initial display date property of
  /// calendar has value, on this scenario the first resource cell must be
  /// selected;
  void _updateProgrammaticSelectedResourceIndex() {
    if (_updateCalendarStateDetails.selectedDate != null && _selectedResourceIndex == -1) {
      final bool isTimelineMonth = widget.view == CalendarView.timelineMonth;
      if ((isTimelineMonth && (isSameDate(_updateCalendarStateDetails.selectedDate, widget.calendar.initialSelectedDate))) ||
          (!isTimelineMonth &&
              (CalendarViewHelper.isSameTimeSlot(
                  _updateCalendarStateDetails.selectedDate, widget.calendar.initialSelectedDate)))) {
        _selectedResourceIndex = 0;
      }
    }
  }

  // Returns the timeline view  as a child for the calendar view.
  Widget _addTimelineView(double width, double height, String locale) {
    final double viewHeaderHeight = CalendarViewHelper.getViewHeaderHeight(widget.calendar.viewHeaderHeight, widget.view);
    final double timeLabelSize =
        CalendarViewHelper.getTimeLabelWidth(widget.calendar.timeSlotViewSettings.timeRulerSize, widget.view);
    final bool isResourceEnabled = CalendarViewHelper.isResourceEnabled(widget.calendar.dataSource, widget.view);
    double resourceItemHeight = 0;
    height -= viewHeaderHeight + timeLabelSize;
    if (isResourceEnabled) {
      _updateProgrammaticSelectedResourceIndex();
      final double resourceViewSize = widget.calendar.resourceViewSettings.size;
      resourceItemHeight = CalendarViewHelper.getResourceItemHeight(
          resourceViewSize,
          widget.height - viewHeaderHeight - timeLabelSize,
          widget.calendar.resourceViewSettings,
          widget.calendar.dataSource!.resources!.length);
      height = resourceItemHeight * widget.resourceCollection!.length;
    }
    return Stack(children: <Widget>[
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        height: viewHeaderHeight,
        child: Container(
          color: widget.calendar.viewHeaderStyle.backgroundColor ?? widget.calendarTheme.viewHeaderBackgroundColor,
          child: _getTimelineViewHeader(width, viewHeaderHeight, widget.locale),
        ),
      ),
      Positioned(
          top: viewHeaderHeight,
          left: 0,
          right: 0,
          height: timeLabelSize,
          child: ListView(
            padding: const EdgeInsets.all(0.0),
            controller: _timelineRulerController,
            scrollDirection: Axis.horizontal,
            physics: const _CustomNeverScrollableScrollPhysics(),
            children: <Widget>[
              RepaintBoundary(
                  child: CustomPaint(
                painter: _TimeRulerView(
                    _horizontalLinesCount!,
                    _timeIntervalHeight,
                    widget.calendar.timeSlotViewSettings,
                    widget.calendar.cellBorderColor,
                    locale,
                    widget.calendarTheme,
                    CalendarViewHelper.isTimelineView(widget.view),
                    widget.visibleDates,
                    widget.textScaleFactor),
                size: Size(width, timeLabelSize),
              )),
            ],
          )),
      Positioned(
          top: viewHeaderHeight + timeLabelSize,
          left: 0,
          right: 0,
          bottom: 0,
          child: Scrollbar(
            controller: _scrollController,
            isAlwaysShown: false,
            child: ListView(
                padding: const EdgeInsets.all(0.0),
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                physics: const _CustomNeverScrollableScrollPhysics(),
                children: <Widget>[
                  Container(
                      width: width,
                      child: Stack(children: <Widget>[
                        Scrollbar(
                            controller: _timelineViewVerticalScrollController,
                            isAlwaysShown: false,
                            child: ListView(
                                padding: const EdgeInsets.all(0.0),
                                scrollDirection: Axis.vertical,
                                controller: _timelineViewVerticalScrollController,
                                physics: isResourceEnabled ? const ClampingScrollPhysics() : const NeverScrollableScrollPhysics(),
                                children: <Widget>[
                                  Stack(children: <Widget>[
                                    RepaintBoundary(
                                        child: _CalendarMultiChildContainer(
                                      width: width,
                                      height: height,
                                      children: <Widget>[
                                        RepaintBoundary(
                                            child: TimelineWidget(
                                                _horizontalLinesCount!,
                                                widget.visibleDates,
                                                widget.calendar.timeSlotViewSettings,
                                                _timeIntervalHeight,
                                                widget.calendar.cellBorderColor,
                                                widget.calendarTheme,
                                                _scrollController!,
                                                widget.regions,
                                                resourceItemHeight,
                                                widget.resourceCollection,
                                                widget.textScaleFactor,
                                                widget.calendar.timeRegionBuilder,
                                                width,
                                                height,
                                                widget.minDate,
                                                widget.maxDate,
                                                widget.blackoutDates)),
                                        RepaintBoundary(child: _addAppointmentPainter(width, height, resourceItemHeight)),
                                      ],
                                    )),
                                    RepaintBoundary(
                                      child: CustomPaint(
                                        painter: _addSelectionView(resourceItemHeight),
                                        size: Size(width, height),
                                      ),
                                    ),
                                    _getCurrentTimeIndicator(timeLabelSize, width, height, true),
                                  ]),
                                ])),
                      ])),
                ]),
          )),
    ]);
  }

  //// Handles the onTap callback for month cells, and view header of month
  void _handleOnTapForMonth(TapUpDetails details) {
    _handleTouchOnMonthView(details, null);
  }

  /// Handles the tap and long press related functions for month view.
  void _handleTouchOnMonthView(TapUpDetails? tapDetails, LongPressStartDetails? longPressDetails) {
    widget.removePicker();
    final DateTime? previousSelectedDate = _selectionPainter!.selectedDate;
    double xDetails = 0, yDetails = 0;
    bool isTapCallback = false;
    if (tapDetails != null) {
      isTapCallback = true;
      xDetails = tapDetails.localPosition.dx;
      yDetails = tapDetails.localPosition.dy;
    } else if (longPressDetails != null) {
      xDetails = longPressDetails.localPosition.dx;
      yDetails = longPressDetails.localPosition.dy;
    }

    final double viewHeaderHeight = CalendarViewHelper.getViewHeaderHeight(widget.calendar.viewHeaderHeight, widget.view);
    final double weekNumberPanelWidth = CalendarViewHelper.getWeekNumberPanelWidth(widget.calendar.showWeekNumber, widget.width);
    if (xDetails < weekNumberPanelWidth) {
      return;
    }
    if (yDetails < viewHeaderHeight) {
      if (isTapCallback) {
        _handleOnTapForViewHeader(tapDetails!, widget.width);
      } else if (!isTapCallback) {
        _handleOnLongPressForViewHeader(longPressDetails!, widget.width);
      }
    } else if (yDetails > viewHeaderHeight) {
      if (!widget.focusNode.hasFocus) {
        widget.focusNode.requestFocus();
      }

      AppointmentView? appointmentView;

      if (appointmentView == null) {
        _drawSelection(xDetails, yDetails - viewHeaderHeight, 0);
      } else {
        _updateCalendarStateDetails.selectedDate = null;
        widget.agendaSelectedDate.value = null;
        _selectionPainter!.selectedDate = null;
        _selectionPainter!.appointmentView = appointmentView;
        _selectionNotifier.value = !_selectionNotifier.value;
      }

      widget.updateCalendarState(_updateCalendarStateDetails);
      final DateTime selectedDate = _getDateFromPosition(xDetails, yDetails - viewHeaderHeight, 0)!;
      if (appointmentView == null) {
        if (!isDateWithInDateRange(widget.calendar.minDate, widget.calendar.maxDate, selectedDate) ||
            CalendarViewHelper.isDateInDateCollection(widget.blackoutDates, selectedDate)) {
          return;
        }

        final int currentMonth = widget.visibleDates[widget.visibleDates.length ~/ 2].month;

        /// Check the selected cell date as trailing or leading date when
        /// [SfCalendar] month not shown leading and trailing dates.
        if (!CalendarViewHelper.isCurrentMonthDate(widget.calendar.monthViewSettings.numberOfWeeksInView,
            widget.calendar.monthViewSettings.showTrailingAndLeadingDates, currentMonth, selectedDate)) {
          return;
        }

        _handleMonthCellTapNavigation(selectedDate);
      }

      final bool canRaiseTap = CalendarViewHelper.shouldRaiseCalendarTapCallback(widget.calendar.onTap) && isTapCallback;
      final bool canRaiseLongPress =
          CalendarViewHelper.shouldRaiseCalendarLongPressCallback(widget.calendar.onLongPress) && !isTapCallback;
      final bool canRaiseSelectionChanged =
          CalendarViewHelper.shouldRaiseCalendarSelectionChangedCallback(widget.calendar.onSelectionChanged);

      if (canRaiseLongPress || canRaiseTap || canRaiseSelectionChanged) {
        final List<dynamic> selectedAppointments = appointmentView == null
            ? _getSelectedAppointments(selectedDate)
            : <dynamic>[CalendarViewHelper.getAppointmentDetail(appointmentView.appointment!)];
        final CalendarElement selectedElement =
            appointmentView == null ? CalendarElement.calendarCell : CalendarElement.appointment;
        if (canRaiseTap) {
          CalendarViewHelper.raiseCalendarTapCallback(widget.calendar, selectedDate, selectedAppointments, selectedElement, null);
        } else if (canRaiseLongPress) {
          CalendarViewHelper.raiseCalendarLongPressCallback(
              widget.calendar, selectedDate, selectedAppointments, selectedElement, null);
        }

        _updatedSelectionChangedCallback(canRaiseSelectionChanged, previousSelectedDate);
      }
    }
  }

  /// Raise selection changed callback based on the arguments passed.
  void _updatedSelectionChangedCallback(bool canRaiseSelectionChanged, DateTime? previousSelectedDate,
      [CalendarResource? selectedResource, int? previousSelectedResourceIndex]) {
    final bool isMonthView = widget.view == CalendarView.month || widget.view == CalendarView.timelineMonth;
    if (canRaiseSelectionChanged &&
        ((isMonthView && !isSameDate(previousSelectedDate, _selectionPainter!.selectedDate)) ||
            (!isMonthView && !CalendarViewHelper.isSameTimeSlot(previousSelectedDate, _selectionPainter!.selectedDate)) ||
            (CalendarViewHelper.isResourceEnabled(widget.calendar.dataSource, widget.view) &&
                _selectionPainter!.selectedResourceIndex != previousSelectedResourceIndex))) {
      CalendarViewHelper.raiseCalendarSelectionChangedCallback(
          widget.calendar, _selectionPainter!.selectedDate, selectedResource);
    }
  }

  void _handleMonthCellTapNavigation(DateTime date) {
    if (!widget.allowViewNavigation || widget.view != CalendarView.month || widget.calendar.monthViewSettings.showAgenda) {
      return;
    }

    widget.controller.view = CalendarView.day;
    widget.controller.displayDate = date;
  }

  //// Handles the onLongPress callback for month cells, and view header of month.
  void _handleOnLongPressForMonth(LongPressStartDetails details) {
    _handleTouchOnMonthView(null, details);
  }

  //// Handles the onTap callback for timeline view cells, and view header of timeline.
  void _handleOnTapForTimeline(TapUpDetails details) {
    _handleTouchOnTimeline(details, null);
  }

  /// Returns the index of resource value associated with the selected calendar
  /// cell in timeline views.
  int _getSelectedResourceIndex(double yPosition, double viewHeaderHeight, double timeLabelSize) {
    final int resourceCount = widget.calendar.dataSource != null && widget.calendar.dataSource!.resources != null
        ? widget.calendar.dataSource!.resources!.length
        : 0;
    final double resourceItemHeight = CalendarViewHelper.getResourceItemHeight(widget.calendar.resourceViewSettings.size,
        widget.height - viewHeaderHeight - timeLabelSize, widget.calendar.resourceViewSettings, resourceCount);
    return (yPosition / resourceItemHeight).truncate();
  }

  /// Handles the tap and long press related functions for timeline view.
  void _handleTouchOnTimeline(TapUpDetails? tapDetails, LongPressStartDetails? longPressDetails) {
    widget.removePicker();
    final DateTime? previousSelectedDate = _selectionPainter!.selectedDate;
    double xDetails = 0, yDetails = 0;
    bool isTapCallback = false;
    if (tapDetails != null) {
      isTapCallback = true;
      xDetails = tapDetails.localPosition.dx;
      yDetails = tapDetails.localPosition.dy;
    } else if (longPressDetails != null) {
      xDetails = longPressDetails.localPosition.dx;
      yDetails = longPressDetails.localPosition.dy;
    }

    final double viewHeaderHeight = CalendarViewHelper.getViewHeaderHeight(widget.calendar.viewHeaderHeight, widget.view);

    if (yDetails < viewHeaderHeight) {
      if (isTapCallback) {
        _handleOnTapForViewHeader(tapDetails!, widget.width);
      } else if (!isTapCallback) {
        _handleOnLongPressForViewHeader(longPressDetails!, widget.width);
      }
    } else if (yDetails > viewHeaderHeight) {
      if (!widget.focusNode.hasFocus) {
        widget.focusNode.requestFocus();
      }

      widget.getCalendarState(_updateCalendarStateDetails);
      DateTime? selectedDate = _updateCalendarStateDetails.selectedDate;

      final double xPosition = _scrollController!.offset + xDetails;
      double yPosition = yDetails - viewHeaderHeight;
      final double timeLabelWidth =
          CalendarViewHelper.getTimeLabelWidth(widget.calendar.timeSlotViewSettings.timeRulerSize, widget.view);

      if (yPosition < timeLabelWidth) {
        return;
      }

      yPosition -= timeLabelWidth;

      CalendarResource? selectedResource;

      if (CalendarViewHelper.isResourceEnabled(widget.calendar.dataSource, widget.view)) {
        yPosition += _timelineViewVerticalScrollController!.offset;
        _selectedResourceIndex = _getSelectedResourceIndex(yPosition, viewHeaderHeight, timeLabelWidth);
        selectedResource = widget.calendar.dataSource!.resources![_selectedResourceIndex];
      }

      final int previousSelectedResourceIndex = _selectionPainter!.selectedResourceIndex;
      _selectionPainter!.selectedResourceIndex = _selectedResourceIndex;

      final AppointmentView? appointmentView = _appointmentLayout.getAppointmentViewOnPoint(xPosition, yPosition);
      if (appointmentView == null) {
        _drawSelection(xDetails, yPosition, timeLabelWidth);
        selectedDate = _selectionPainter!.selectedDate;
      } else {
        if (selectedDate != null) {
          selectedDate = null;
          _selectionPainter!.selectedDate = selectedDate;
          _updateCalendarStateDetails.selectedDate = selectedDate;
        }

        _selectionPainter!.appointmentView = appointmentView;
        _selectionNotifier.value = !_selectionNotifier.value;
      }

      widget.updateCalendarState(_updateCalendarStateDetails);
      final bool canRaiseTap = CalendarViewHelper.shouldRaiseCalendarTapCallback(widget.calendar.onTap) && isTapCallback;
      final bool canRaiseLongPress =
          CalendarViewHelper.shouldRaiseCalendarLongPressCallback(widget.calendar.onLongPress) && !isTapCallback;
      final bool canRaiseSelectionChanged =
          CalendarViewHelper.shouldRaiseCalendarSelectionChangedCallback(widget.calendar.onSelectionChanged);

      if (canRaiseLongPress || canRaiseTap || canRaiseSelectionChanged) {
        final DateTime selectedDate = _getDateFromPosition(xDetails, yDetails - viewHeaderHeight, 0)!;
        final int timeInterval = CalendarViewHelper.getTimeInterval(widget.calendar.timeSlotViewSettings);
        if (appointmentView == null) {
          if (!CalendarViewHelper.isDateTimeWithInDateTimeRange(
                  widget.calendar.minDate, widget.calendar.maxDate, selectedDate, timeInterval) ||
              (widget.view == CalendarView.timelineMonth &&
                  CalendarViewHelper.isDateInDateCollection(widget.calendar.blackoutDates, selectedDate))) {
            return;
          }

          /// Restrict the callback, while selected region as disabled
          /// [TimeRegion].
          if (!_isEnabledRegion(xDetails, selectedDate, _selectedResourceIndex)) {
            return;
          }

          if (canRaiseTap) {
            CalendarViewHelper.raiseCalendarTapCallback(
                widget.calendar, selectedDate, null, CalendarElement.calendarCell, selectedResource);
          } else if (canRaiseLongPress) {
            CalendarViewHelper.raiseCalendarLongPressCallback(
                widget.calendar, selectedDate, null, CalendarElement.calendarCell, selectedResource);
          }
          _updatedSelectionChangedCallback(
              canRaiseSelectionChanged, previousSelectedDate, selectedResource, previousSelectedResourceIndex);
        } else {
          if (canRaiseTap) {
            CalendarViewHelper.raiseCalendarTapCallback(
                widget.calendar,
                selectedDate,
                <dynamic>[CalendarViewHelper.getAppointmentDetail(appointmentView.appointment!)],
                CalendarElement.appointment,
                selectedResource);
          } else if (canRaiseLongPress) {
            CalendarViewHelper.raiseCalendarLongPressCallback(
                widget.calendar,
                selectedDate,
                <dynamic>[CalendarViewHelper.getAppointmentDetail(appointmentView.appointment!)],
                CalendarElement.appointment,
                selectedResource);
          }
          _updatedSelectionChangedCallback(
              canRaiseSelectionChanged, previousSelectedDate, selectedResource, previousSelectedResourceIndex);
        }
      }
    }
  }

  //// Handles the onLongPress callback for timeline view cells, and view header
  //// of timeline.
  void _handleOnLongPressForTimeline(LongPressStartDetails details) {
    _handleTouchOnTimeline(null, details);
  }

  void _updateAllDaySelection(AppointmentView? view, DateTime? date) {
    if (_allDaySelectionNotifier.value != null &&
        view == _allDaySelectionNotifier.value!.appointmentView &&
        isSameDate(date, _allDaySelectionNotifier.value!.selectedDate)) {
      return;
    }

    _allDaySelectionNotifier.value = SelectionDetails(view, date);
  }

  //// Handles the onTap callback for day view cells, all day panel, and view
  //// header of day.
  void _handleOnTapForDay(TapUpDetails details) {
    _handleTouchOnDayView(details, null);
  }

  /// Handles the tap and long press related functions for day, week
  /// work week views.
  void _handleTouchOnDayView(TapUpDetails? tapDetails, LongPressStartDetails? longPressDetails) {
    widget.removePicker();
    final DateTime? previousSelectedDate = _selectionPainter!.selectedDate;
    final int timeInterval = CalendarViewHelper.getTimeInterval(widget.calendar.timeSlotViewSettings);
    double xDetails = 0, yDetails = 0;
    bool isTappedCallback = false;
    if (tapDetails != null) {
      isTappedCallback = true;
      xDetails = tapDetails.localPosition.dx;
      yDetails = tapDetails.localPosition.dy;
    } else if (longPressDetails != null) {
      xDetails = longPressDetails.localPosition.dx;
      yDetails = longPressDetails.localPosition.dy;
    }
    if (!widget.focusNode.hasFocus) {
      widget.focusNode.requestFocus();
    }

    widget.getCalendarState(_updateCalendarStateDetails);
    dynamic selectedAppointment;
    List<dynamic>? selectedAppointments;
    CalendarElement targetElement = CalendarElement.viewHeader;
    DateTime? selectedDate = _updateCalendarStateDetails.selectedDate;
    final double timeLabelWidth =
        CalendarViewHelper.getTimeLabelWidth(widget.calendar.timeSlotViewSettings.timeRulerSize, widget.view);

    final double viewHeaderHeight = widget.view == CalendarView.day
        ? 0
        : CalendarViewHelper.getViewHeaderHeight(widget.calendar.viewHeaderHeight, widget.view);
    final double allDayHeight = _isExpanded ? _updateCalendarStateDetails.allDayPanelHeight : _allDayHeight;
    if (xDetails <= timeLabelWidth && yDetails > viewHeaderHeight + allDayHeight) {
      return;
    }

    if (yDetails < viewHeaderHeight) {
      /// Check the touch position in time ruler view
      /// If RTL, time ruler placed at right side,
      /// else time ruler placed at left side.
      if (xDetails <= timeLabelWidth) {
        return;
      }

      if (isTappedCallback) {
        _handleOnTapForViewHeader(tapDetails!, widget.width);
      } else if (!isTappedCallback) {
        _handleOnLongPressForViewHeader(longPressDetails!, widget.width);
      }

      return;
    } else if (yDetails < viewHeaderHeight + allDayHeight) {
      /// Check the touch position in view header when [CalendarView] is day
      /// If RTL, view header placed at right side,
      /// else view header placed at left side.
      if (widget.view == CalendarView.day &&
          xDetails <= timeLabelWidth &&
          yDetails < CalendarViewHelper.getViewHeaderHeight(widget.calendar.viewHeaderHeight, widget.view)) {
        if (isTappedCallback) {
          _handleOnTapForViewHeader(tapDetails!, widget.width);
        } else if (!isTappedCallback) {
          _handleOnLongPressForViewHeader(longPressDetails!, widget.width);
        }

        return;
      } else if (timeLabelWidth >= xDetails) {
        /// Perform expand or collapse when the touch position on
        /// expander icon in all day panel.
        _expandOrCollapseAllDay();
        return;
      }

      final double yPosition = yDetails - viewHeaderHeight;
      final AppointmentView? appointmentView =
          _getAllDayAppointmentOnPoint(_updateCalendarStateDetails.allDayAppointmentViewCollection, xDetails, yPosition);

      if (appointmentView == null) {
        targetElement = CalendarElement.allDayPanel;
        if (isTappedCallback) {
          selectedDate = _getTappedViewHeaderDate(tapDetails!.localPosition, widget.width);
        } else {
          selectedDate = _getTappedViewHeaderDate(longPressDetails!.localPosition, widget.width);
        }
      }

      /// Check the count position tapped or not
      bool isTappedOnCount = appointmentView != null &&
          _updateCalendarStateDetails.allDayPanelHeight > allDayHeight &&
          yPosition > allDayHeight - kAllDayAppointmentHeight;

      /// Check the tap position inside the last appointment rendering position
      /// when the panel as collapsed and it does not position does not have
      /// appointment.
      /// Eg., If July 8 have 3 all day appointments spanned to July 9 and
      /// July 9 have 1 all day appointment spanned to July 10 then July 10
      /// appointment view does not shown and it only have count label.
      /// If user tap on count label then the panel does not have appointment
      /// view, because the view rendered after the end position, so calculate
      /// the visible date cell appointment and it have appointments after
      /// end position then perform expand operation.
      if (appointmentView == null &&
          selectedDate != null &&
          _updateCalendarStateDetails.allDayPanelHeight > allDayHeight &&
          yPosition > allDayHeight - kAllDayAppointmentHeight) {
        final int currentSelectedIndex = DateTimeHelper.getVisibleDateIndex(widget.visibleDates, selectedDate);
        if (currentSelectedIndex != -1) {
          final List<AppointmentView> selectedIndexAppointment = <AppointmentView>[];
          for (int i = 0; i < _updateCalendarStateDetails.allDayAppointmentViewCollection.length; i++) {
            final AppointmentView currentView = _updateCalendarStateDetails.allDayAppointmentViewCollection[i];
            if (currentView.appointment == null) {
              continue;
            }
            if (currentView.startIndex <= currentSelectedIndex && currentView.endIndex > currentSelectedIndex) {
              selectedIndexAppointment.add(currentView);
            }
          }

          int maxPosition = 0;
          if (selectedIndexAppointment.isNotEmpty) {
            maxPosition = selectedIndexAppointment
                .reduce((AppointmentView currentAppView, AppointmentView nextAppView) =>
                    currentAppView.maxPositions > nextAppView.maxPositions ? currentAppView : nextAppView)
                .maxPositions;
          }
          final int endAppointmentPosition = allDayHeight ~/ kAllDayAppointmentHeight;
          if (endAppointmentPosition < maxPosition) {
            isTappedOnCount = true;
          }
        }
      }

      if (appointmentView != null &&
          (yPosition < allDayHeight - kAllDayAppointmentHeight ||
              _updateCalendarStateDetails.allDayPanelHeight <= allDayHeight ||
              appointmentView.position + 1 >= appointmentView.maxPositions)) {
        if (!CalendarViewHelper.isDateTimeWithInDateTimeRange(
                widget.calendar.minDate, widget.calendar.maxDate, appointmentView.appointment!.actualStartTime, timeInterval) ||
            !CalendarViewHelper.isDateTimeWithInDateTimeRange(
                widget.calendar.minDate, widget.calendar.maxDate, appointmentView.appointment!.actualEndTime, timeInterval)) {
          return;
        }
        if (selectedDate != null) {
          selectedDate = null;
          _selectionPainter!.selectedDate = selectedDate;
          _updateCalendarStateDetails.selectedDate = selectedDate;
        }

        _selectionPainter!.appointmentView = null;
        _selectionNotifier.value = !_selectionNotifier.value;
        selectedAppointment = appointmentView.appointment;
        selectedAppointments = null;
        targetElement = CalendarElement.appointment;
        _updateAllDaySelection(appointmentView, null);
      } else if (isTappedOnCount) {
        _expandOrCollapseAllDay();
        return;
      } else if (appointmentView == null) {
        _updateAllDaySelection(null, selectedDate);
        _selectionPainter!.selectedDate = null;
        _selectionPainter!.appointmentView = null;
        _selectionNotifier.value = !_selectionNotifier.value;
        _updateCalendarStateDetails.selectedDate = null;
      }
    } else {
      final double yPosition = yDetails - viewHeaderHeight - allDayHeight + _scrollController!.offset;
      final AppointmentView? appointmentView = _appointmentLayout.getAppointmentViewOnPoint(xDetails, yPosition);
      _allDaySelectionNotifier.value = null;
      if (appointmentView == null) {
        _drawSelection(xDetails - timeLabelWidth, yDetails - viewHeaderHeight - allDayHeight, timeLabelWidth);
        targetElement = CalendarElement.calendarCell;
      } else {
        if (selectedDate != null) {
          selectedDate = null;
          _selectionPainter!.selectedDate = selectedDate;
          _updateCalendarStateDetails.selectedDate = selectedDate;
        }

        _selectionPainter!.appointmentView = appointmentView;
        _selectionNotifier.value = !_selectionNotifier.value;
        selectedAppointment = appointmentView.appointment;
        targetElement = CalendarElement.appointment;
      }
    }

    widget.updateCalendarState(_updateCalendarStateDetails);
    final bool canRaiseTap = CalendarViewHelper.shouldRaiseCalendarTapCallback(widget.calendar.onTap) && isTappedCallback;
    final bool canRaiseLongPress =
        CalendarViewHelper.shouldRaiseCalendarLongPressCallback(widget.calendar.onLongPress) && !isTappedCallback;
    final bool canRaiseSelectionChanged =
        CalendarViewHelper.shouldRaiseCalendarSelectionChangedCallback(widget.calendar.onSelectionChanged);
    if (canRaiseLongPress || canRaiseTap || canRaiseSelectionChanged) {
      final double yPosition = yDetails - viewHeaderHeight - allDayHeight;
      if (_selectionPainter!.selectedDate != null && targetElement != CalendarElement.allDayPanel) {
        selectedAppointments = null;

        /// In LTR, remove the time ruler width value from the
        /// touch x position while calculate the selected date value.
        selectedDate = _getDateFromPosition(xDetails - timeLabelWidth, yPosition, timeLabelWidth);

        if (!CalendarViewHelper.isDateTimeWithInDateTimeRange(
            widget.calendar.minDate, widget.calendar.maxDate, selectedDate!, timeInterval)) {
          return;
        }

        /// Restrict the callback, while selected region as disabled
        /// [TimeRegion].
        if (targetElement == CalendarElement.calendarCell && !_isEnabledRegion(yPosition, selectedDate, _selectedResourceIndex)) {
          return;
        }

        if (canRaiseTap) {
          CalendarViewHelper.raiseCalendarTapCallback(
              widget.calendar, _selectionPainter!.selectedDate, selectedAppointments, targetElement, null);
        } else if (canRaiseLongPress) {
          CalendarViewHelper.raiseCalendarLongPressCallback(
              widget.calendar, _selectionPainter!.selectedDate, selectedAppointments, targetElement, null);
        }
        _updatedSelectionChangedCallback(canRaiseSelectionChanged, previousSelectedDate);
      } else if (selectedAppointment != null) {
        selectedAppointments = <dynamic>[CalendarViewHelper.getAppointmentDetail(selectedAppointment)];

        /// In LTR, remove the time ruler width value from the
        /// touch x position while calculate the selected date value.
        selectedDate = _getDateFromPosition(xDetails - timeLabelWidth, yPosition, timeLabelWidth);

        if (canRaiseTap) {
          CalendarViewHelper.raiseCalendarTapCallback(
              widget.calendar, selectedDate, selectedAppointments, CalendarElement.appointment, null);
        } else if (canRaiseLongPress) {
          CalendarViewHelper.raiseCalendarLongPressCallback(
              widget.calendar, selectedDate, selectedAppointments, CalendarElement.appointment, null);
        }
        _updatedSelectionChangedCallback(canRaiseSelectionChanged, previousSelectedDate);
      } else if (selectedDate != null && targetElement == CalendarElement.allDayPanel) {
        if (canRaiseTap) {
          CalendarViewHelper.raiseCalendarTapCallback(widget.calendar, selectedDate, null, targetElement, null);
        } else if (canRaiseLongPress) {
          CalendarViewHelper.raiseCalendarLongPressCallback(widget.calendar, selectedDate, null, targetElement, null);
        }
        _updatedSelectionChangedCallback(canRaiseSelectionChanged, previousSelectedDate);
      }
    }
  }

  /// Check the selected date region as enabled time region or not.
  bool _isEnabledRegion(double y, DateTime? selectedDate, int resourceIndex) {
    if (widget.regions == null || widget.regions!.isEmpty || widget.view == CalendarView.timelineMonth || selectedDate == null) {
      return true;
    }

    final double timeIntervalSize = _getTimeIntervalHeight(
        widget.calendar, widget.view, widget.width, widget.height, widget.visibleDates.length, _allDayHeight);

    final double minuteHeight = timeIntervalSize / CalendarViewHelper.getTimeInterval(widget.calendar.timeSlotViewSettings);
    final Duration startDuration = Duration(
        hours: widget.calendar.timeSlotViewSettings.startHour.toInt(),
        minutes: ((widget.calendar.timeSlotViewSettings.startHour - widget.calendar.timeSlotViewSettings.startHour.toInt()) * 60)
            .toInt());
    int minutes;
    if (CalendarViewHelper.isTimelineView(widget.view)) {
      final double viewWidth = _timeIntervalHeight * _horizontalLinesCount!;
      minutes = ((_scrollController!.offset + y) % viewWidth) ~/ minuteHeight;
    } else {
      minutes = (_scrollController!.offset + y) ~/ minuteHeight;
    }

    final DateTime date =
        DateTime(selectedDate.year, selectedDate.month, selectedDate.day, 0, minutes + startDuration.inMinutes, 0);
    bool isValidRegion = true;
    final bool isResourcesEnabled = CalendarViewHelper.isResourceEnabled(widget.calendar.dataSource, widget.view);
    for (int i = 0; i < widget.regions!.length; i++) {
      final CalendarTimeRegion region = widget.regions![i];
      if (region.actualStartTime.isAfter(date) || region.actualEndTime.isBefore(date)) {
        continue;
      }

      /// Condition added ensure that the region is disabled only on the
      /// specified resource slot, for other resources it must be enabled.
      if (isResourcesEnabled &&
          resourceIndex != -1 &&
          region.resourceIds != null &&
          region.resourceIds!.isNotEmpty &&
          !region.resourceIds!.contains(widget.resourceCollection![resourceIndex].id)) {
        continue;
      }

      isValidRegion = region.enablePointerInteraction;
    }

    return isValidRegion;
  }

  bool _isAutoTimeIntervalHeight(SfCalendar calendar, bool isTimelineView) {
    if (isTimelineView) {
      return calendar.timeSlotViewSettings.timeIntervalWidth == -1;
    }

    return calendar.timeSlotViewSettings.timeIntervalHeight == -1;
  }

  /// Returns the default time interval width for timeline views.
  double _getTimeIntervalWidth(double timeIntervalHeight, CalendarView view, double width) {
    if (timeIntervalHeight >= 0) {
      return timeIntervalHeight;
    }

    return 60;
  }

  /// Returns the time interval width based on property value, also arrange the
  /// time slots into the view port size.
  double _getTimeIntervalHeight(
      SfCalendar calendar, CalendarView view, double width, double height, int visibleDatesCount, double allDayHeight) {
    final bool isTimelineView = CalendarViewHelper.isTimelineView(view);
    double timeIntervalHeight = isTimelineView
        ? _getTimeIntervalWidth(calendar.timeSlotViewSettings.timeIntervalWidth, view, width)
        : calendar.timeSlotViewSettings.timeIntervalHeight;

    if (!_isAutoTimeIntervalHeight(calendar, isTimelineView)) {
      return timeIntervalHeight;
    }

    double viewHeaderHeight = CalendarViewHelper.getViewHeaderHeight(calendar.viewHeaderHeight, view);

    if (view == CalendarView.day) {
      allDayHeight = _kAllDayLayoutHeight;
      viewHeaderHeight = 0;
    } else {
      allDayHeight = allDayHeight > _kAllDayLayoutHeight ? _kAllDayLayoutHeight : allDayHeight;
    }

    switch (view) {
      case CalendarView.day:
      case CalendarView.week:
      case CalendarView.workWeek:
        timeIntervalHeight = (height - allDayHeight - viewHeaderHeight) /
            CalendarViewHelper.getHorizontalLinesCount(calendar.timeSlotViewSettings, view);
        break;
      case CalendarView.timelineDay:
      case CalendarView.timelineWeek:
      case CalendarView.timelineWorkWeek:
      case CalendarView.timelineMonth:
        {
          final double _horizontalLinesCount = CalendarViewHelper.getHorizontalLinesCount(calendar.timeSlotViewSettings, view);
          timeIntervalHeight = width / (_horizontalLinesCount * visibleDatesCount);
          if (!_isValidWidth(width, calendar, visibleDatesCount, _horizontalLinesCount)) {
            /// we have used 40 as a default time interval height for timeline
            /// view when the time interval height set for auto time
            /// interval height.
            timeIntervalHeight = 40;
          }
        }
        break;
      case CalendarView.schedule:
      case CalendarView.month:
        return 0;
    }

    return timeIntervalHeight;
  }

  /// checks whether the width can afford the line count or else creates a
  /// scrollable width
  bool _isValidWidth(double screenWidth, SfCalendar calendar, int visibleDatesCount, double horizontalLinesCount) {
    const int offSetValue = 10;
    final double tempWidth = visibleDatesCount * offSetValue * horizontalLinesCount;

    if (tempWidth < screenWidth) {
      return true;
    }

    return false;
  }

  //// Handles the onLongPress callback for day view cells, all day panel and
  //// view header  of day.
  void _handleOnLongPressForDay(LongPressStartDetails details) {
    _handleTouchOnDayView(null, details);
  }

  //// Handles the on tap callback for view header
  void _handleOnTapForViewHeader(TapUpDetails details, double width) {
    final DateTime tappedDate = _getTappedViewHeaderDate(details.localPosition, width)!;
    _handleViewHeaderTapNavigation(tappedDate);
    if (!CalendarViewHelper.shouldRaiseCalendarTapCallback(widget.calendar.onTap)) {
      return;
    }

    CalendarViewHelper.raiseCalendarTapCallback(widget.calendar, tappedDate, null, CalendarElement.viewHeader, null);
  }

  //// Handles the on long press callback for view header
  void _handleOnLongPressForViewHeader(LongPressStartDetails details, double width) {
    final DateTime tappedDate = _getTappedViewHeaderDate(details.localPosition, width)!;
    _handleViewHeaderTapNavigation(tappedDate);
    if (!CalendarViewHelper.shouldRaiseCalendarLongPressCallback(widget.calendar.onLongPress)) {
      return;
    }

    CalendarViewHelper.raiseCalendarLongPressCallback(widget.calendar, tappedDate, null, CalendarElement.viewHeader, null);
  }

  void _handleViewHeaderTapNavigation(DateTime date) {
    if (!widget.allowViewNavigation ||
        widget.view == CalendarView.day ||
        widget.view == CalendarView.timelineDay ||
        widget.view == CalendarView.month) {
      return;
    }

    if (!isDateWithInDateRange(widget.calendar.minDate, widget.calendar.maxDate, date) ||
        (widget.controller.view == CalendarView.timelineMonth &&
            CalendarViewHelper.isDateInDateCollection(widget.blackoutDates, date))) {
      return;
    }

    if (widget.view == CalendarView.week || widget.view == CalendarView.workWeek) {
      widget.controller.view = CalendarView.day;
    } else {
      widget.controller.view = CalendarView.timelineDay;
    }

    widget.controller.displayDate = date;
  }

  DateTime? _getTappedViewHeaderDate(Offset localPosition, double width) {
    int index = 0;
    final double timeLabelViewWidth =
        CalendarViewHelper.getTimeLabelWidth(widget.calendar.timeSlotViewSettings.timeRulerSize, widget.view);
    final int visibleDatesLength = widget.visibleDates.length;
    if (!CalendarViewHelper.isTimelineView(widget.view)) {
      double cellWidth = 0;
      if (widget.view != CalendarView.month) {
        cellWidth = (width - timeLabelViewWidth) / visibleDatesLength;

        /// Set index value as 0 when calendar view as day because day view hold
        /// single visible date.
        if (widget.view == CalendarView.day) {
          index = 0;
        } else {
          index = ((localPosition.dx - timeLabelViewWidth) / cellWidth).truncate();
        }
      } else {
        cellWidth = width / DateTime.daysPerWeek;
        index = (localPosition.dx / cellWidth).truncate();
      }

      if (index < 0 || index >= visibleDatesLength) {
        return null;
      }

      return widget.visibleDates[index];
    } else {
      index = ((_scrollController!.offset + localPosition.dx) / _getSingleViewWidthForTimeLineView(this)).truncate();

      if (index < 0 || index >= visibleDatesLength) {
        return null;
      }

      return widget.visibleDates[index];
    }
  }

  AppointmentView? _getAllDayAppointmentOnPoint(List<AppointmentView>? appointmentCollection, double x, double y) {
    if (appointmentCollection == null) {
      return null;
    }

    AppointmentView? selectedAppointmentView;
    for (int i = 0; i < appointmentCollection.length; i++) {
      final AppointmentView appointmentView = appointmentCollection[i];
      if (appointmentView.appointment != null &&
          appointmentView.appointmentRect != null &&
          appointmentView.appointmentRect!.left <= x &&
          appointmentView.appointmentRect!.right >= x &&
          appointmentView.appointmentRect!.top <= y &&
          appointmentView.appointmentRect!.bottom >= y) {
        selectedAppointmentView = appointmentView;
        break;
      }
    }

    return selectedAppointmentView;
  }

  List<dynamic> _getSelectedAppointments(DateTime selectedDate) {
    return (widget.calendar.dataSource != null && !AppointmentHelper.isCalendarAppointment(widget.calendar.dataSource!))
        ? CalendarViewHelper.getCustomAppointments(AppointmentHelper.getSelectedDateAppointments(
            _updateCalendarStateDetails.appointments, widget.calendar.timeZone, selectedDate))
        : (AppointmentHelper.getSelectedDateAppointments(
            _updateCalendarStateDetails.appointments, widget.calendar.timeZone, selectedDate));
  }

  DateTime? _getDateFromPositionForMonth(double cellWidth, double cellHeight, double x, double y) {
    final int rowIndex = (x / cellWidth).truncate();
    final int columnIndex = (y / cellHeight).truncate();
    int index = 0;
    index = (columnIndex * DateTime.daysPerWeek) + rowIndex;

    if (index < 0 || index >= widget.visibleDates.length) {
      return null;
    }

    return widget.visibleDates[index];
  }

  DateTime _getDateFromPositionForDay(double cellWidth, double cellHeight, double x, double y) {
    final int columnIndex = ((_scrollController!.offset + y) / cellHeight).truncate();
    final double time = ((CalendarViewHelper.getTimeInterval(widget.calendar.timeSlotViewSettings) / 60) * columnIndex) +
        widget.calendar.timeSlotViewSettings.startHour;
    final int hour = time.toInt();
    final int minute = ((time - hour) * 60).round();
    return DateTime(widget.visibleDates[0].year, widget.visibleDates[0].month, widget.visibleDates[0].day, hour, minute);
  }

  DateTime? _getDateFromPositionForWeek(double cellWidth, double cellHeight, double x, double y) {
    final int columnIndex = ((_scrollController!.offset + y) / cellHeight).truncate();
    final double time = ((CalendarViewHelper.getTimeInterval(widget.calendar.timeSlotViewSettings) / 60) * columnIndex) +
        widget.calendar.timeSlotViewSettings.startHour;
    final int hour = time.toInt();
    final int minute = ((time - hour) * 60).round();
    final int rowIndex = (x / cellWidth).truncate();

    if (rowIndex < 0 || rowIndex >= widget.visibleDates.length) {
      return null;
    }

    final DateTime date = widget.visibleDates[rowIndex];

    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  DateTime? _getDateFromPositionForTimeline(double cellWidth, double cellHeight, double x, double y) {
    int rowIndex, columnIndex;
    rowIndex = (((_scrollController!.offset % _getSingleViewWidthForTimeLineView(this)) + x) / cellWidth).truncate();
    columnIndex = (_scrollController!.offset / _getSingleViewWidthForTimeLineView(this)).truncate();
    if (rowIndex >= _horizontalLinesCount!) {
      columnIndex += rowIndex ~/ _horizontalLinesCount!;
      rowIndex = (rowIndex % _horizontalLinesCount!).toInt();
    }
    final double time = ((CalendarViewHelper.getTimeInterval(widget.calendar.timeSlotViewSettings) / 60) * rowIndex) +
        widget.calendar.timeSlotViewSettings.startHour;
    final int hour = time.toInt();
    final int minute = ((time - hour) * 60).round();
    if (columnIndex < 0) {
      columnIndex = 0;
    } else if (columnIndex > widget.visibleDates.length) {
      columnIndex = widget.visibleDates.length - 1;
    }

    if (columnIndex < 0 || columnIndex >= widget.visibleDates.length) {
      return null;
    }

    final DateTime date = widget.visibleDates[columnIndex];

    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  DateTime? _getDateFromPosition(double x, double y, double timeLabelWidth) {
    double cellWidth = 0;
    double cellHeight = 0;
    final double width = widget.width - timeLabelWidth;
    switch (widget.view) {
      case CalendarView.schedule:
        return null;
      case CalendarView.month:
        {
          /// Remove the selection when the position is to week number panel.
          final double weekNumberPanelWidth =
              CalendarViewHelper.getWeekNumberPanelWidth(widget.calendar.showWeekNumber, widget.width);
          if (x > widget.width || x < weekNumberPanelWidth) {
            return null;
          }

          /// In RTL the week number panel will render on the right side hence,
          /// we didn't consider the week number panel width in rtl.
          x -= weekNumberPanelWidth;

          cellWidth = (widget.width - weekNumberPanelWidth) / DateTime.daysPerWeek;
          cellHeight = (widget.height - CalendarViewHelper.getViewHeaderHeight(widget.calendar.viewHeaderHeight, widget.view)) /
              widget.calendar.monthViewSettings.numberOfWeeksInView;
          return _getDateFromPositionForMonth(cellWidth, cellHeight, x, y);
        }
      case CalendarView.day:
        {
          if (y >= _timeIntervalHeight * _horizontalLinesCount! || x > width || x < 0) {
            return null;
          }
          cellWidth = width;
          cellHeight = _timeIntervalHeight;
          return _getDateFromPositionForDay(cellWidth, cellHeight, x, y);
        }
      case CalendarView.week:
      case CalendarView.workWeek:
        {
          if (y >= _timeIntervalHeight * _horizontalLinesCount! || x > width || x < 0) {
            return null;
          }
          cellWidth = width / widget.visibleDates.length;
          cellHeight = _timeIntervalHeight;
          return _getDateFromPositionForWeek(cellWidth, cellHeight, x, y);
        }
      case CalendarView.timelineDay:
      case CalendarView.timelineWeek:
      case CalendarView.timelineWorkWeek:
      case CalendarView.timelineMonth:
        {
          final double viewWidth = _timeIntervalHeight * (_horizontalLinesCount! * widget.visibleDates.length);
          if (x >= viewWidth) {
            return null;
          }
          cellWidth = _timeIntervalHeight;
          cellHeight = widget.height;
          return _getDateFromPositionForTimeline(cellWidth, cellHeight, x, y);
        }
    }
  }

  void _drawSelection(double x, double y, double timeLabelWidth) {
    final DateTime? selectedDate = _getDateFromPosition(x, y, timeLabelWidth);
    final bool isMonthView = widget.view == CalendarView.month || widget.view == CalendarView.timelineMonth;
    final int timeInterval = CalendarViewHelper.getTimeInterval(widget.calendar.timeSlotViewSettings);
    if (selectedDate == null ||
        (isMonthView && !isDateWithInDateRange(widget.calendar.minDate, widget.calendar.maxDate, selectedDate)) ||
        (!isMonthView &&
            !CalendarViewHelper.isDateTimeWithInDateTimeRange(
                widget.calendar.minDate, widget.calendar.maxDate, selectedDate, timeInterval))) {
      return;
    }

    /// Restrict the selection update, while selected region as disabled
    /// [TimeRegion].
    if (((widget.view == CalendarView.day || widget.view == CalendarView.week || widget.view == CalendarView.workWeek) &&
            !_isEnabledRegion(y, selectedDate, _selectedResourceIndex)) ||
        (CalendarViewHelper.isTimelineView(widget.view) && !_isEnabledRegion(x, selectedDate, _selectedResourceIndex))) {
      return;
    }

    if (isMonthView && CalendarViewHelper.isDateInDateCollection(widget.blackoutDates, selectedDate)) {
      return;
    }

    if (widget.view == CalendarView.month) {
      final int currentMonth = widget.visibleDates[widget.visibleDates.length ~/ 2].month;

      /// Check the selected cell date as trailing or leading date when
      /// [SfCalendar] month not shown leading and trailing dates.
      if (!CalendarViewHelper.isCurrentMonthDate(widget.calendar.monthViewSettings.numberOfWeeksInView,
          widget.calendar.monthViewSettings.showTrailingAndLeadingDates, currentMonth, selectedDate)) {
        return;
      }

      widget.agendaSelectedDate.value = selectedDate;
    }

    _updateCalendarStateDetails.selectedDate = selectedDate;
    _selectionPainter!.selectedDate = selectedDate;
    _selectionPainter!.appointmentView = null;
    _selectionNotifier.value = !_selectionNotifier.value;
  }

  _SelectionPainter _addSelectionView([double? resourceItemHeight]) {
    AppointmentView? appointmentView;
    if (_selectionPainter?.appointmentView != null) {
      appointmentView = _selectionPainter!.appointmentView;
    }

    _selectionPainter = _SelectionPainter(
      widget.calendar,
      widget.view,
      widget.visibleDates,
      _updateCalendarStateDetails.selectedDate,
      widget.calendar.selectionDecoration,
      _timeIntervalHeight,
      widget.calendarTheme,
      _selectionNotifier,
      _selectedResourceIndex,
      resourceItemHeight,
      widget.calendar.showWeekNumber,
      (UpdateCalendarStateDetails details) {
        _getPainterProperties(details);
      },
    );

    if (appointmentView != null && _updateCalendarStateDetails.visibleAppointments.contains(appointmentView.appointment)) {
      _selectionPainter!.appointmentView = appointmentView;
    }

    return _selectionPainter!;
  }

  Widget _getTimelineViewHeader(double width, double height, String locale) {
    _timelineViewHeader = TimelineViewHeaderView(
        widget.visibleDates,
        _timelineViewHeaderScrollController!,
        _timelineViewHeaderNotifier,
        widget.calendar.viewHeaderStyle,
        widget.calendar.timeSlotViewSettings,
        CalendarViewHelper.getViewHeaderHeight(widget.calendar.viewHeaderHeight, widget.view),
        widget.calendar.todayHighlightColor ?? widget.calendarTheme.todayHighlightColor,
        widget.calendar.todayTextStyle,
        widget.locale,
        widget.calendarTheme,
        widget.calendar.minDate,
        widget.calendar.maxDate,
        _viewHeaderNotifier,
        widget.blackoutDates,
        widget.calendar.blackoutDatesTextStyle,
        widget.textScaleFactor);
    return ListView(
        padding: const EdgeInsets.all(0.0),
        controller: _timelineViewHeaderScrollController,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        children: <Widget>[
          CustomPaint(
            painter: _timelineViewHeader,
            size: Size(width, height),
          )
        ]);
  }
}

class _ViewHeaderViewPainter extends CustomPainter {
  _ViewHeaderViewPainter(
      this.visibleDates,
      this.view,
      this.viewHeaderStyle,
      this.timeSlotViewSettings,
      this.timeLabelWidth,
      this.viewHeaderHeight,
      this.monthViewSettings,
      this.locale,
      this.calendarTheme,
      this.todayHighlightColor,
      this.todayTextStyle,
      this.cellBorderColor,
      this.minDate,
      this.maxDate,
      this.viewHeaderNotifier,
      this.textScaleFactor,
      this.showWeekNumber,
      this.weekNumberStyle)
      : super(repaint: viewHeaderNotifier);

  final CalendarView view;
  final ViewHeaderStyle viewHeaderStyle;
  final TimeSlotViewSettings timeSlotViewSettings;
  final MonthViewSettings monthViewSettings;
  final List<DateTime> visibleDates;
  final double timeLabelWidth;
  final double viewHeaderHeight;
  final SfCalendarThemeData calendarTheme;
  final String locale;
  final Color? todayHighlightColor;
  final TextStyle? todayTextStyle;
  final Color? cellBorderColor;
  final DateTime minDate;
  final DateTime maxDate;
  final ValueNotifier<Offset?> viewHeaderNotifier;
  final double textScaleFactor;
  final Paint _circlePainter = Paint();
  final TextPainter _dayTextPainter = TextPainter(), _dateTextPainter = TextPainter();
  final bool showWeekNumber;
  final WeekNumberStyle weekNumberStyle;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final double weekNumberPanelWidth = CalendarViewHelper.getWeekNumberPanelWidth(showWeekNumber, size.width);
    double width = view == CalendarView.month ? size.width - weekNumberPanelWidth : size.width;
    width = _getViewHeaderWidth(width);

    /// Initializes the default text style for the texts in view header of
    /// calendar.
    final TextStyle viewHeaderDayStyle = viewHeaderStyle.dayTextStyle ?? calendarTheme.viewHeaderDayTextStyle;
    final TextStyle viewHeaderDateStyle = viewHeaderStyle.dateTextStyle ?? calendarTheme.viewHeaderDateTextStyle;

    final DateTime today = DateTime.now();
    if (view != CalendarView.month) {
      _addViewHeaderForTimeSlotViews(canvas, size, viewHeaderDayStyle, viewHeaderDateStyle, width, today);
    } else {
      _addViewHeaderForMonthView(canvas, size, viewHeaderDayStyle, width, today, weekNumberPanelWidth);
    }
  }

  void _addViewHeaderForMonthView(
      Canvas canvas, Size size, TextStyle viewHeaderDayStyle, double width, DateTime today, double weekNumberPanelWidth) {
    TextStyle dayTextStyle = viewHeaderDayStyle;
    double xPosition = weekNumberPanelWidth;
    double yPosition = 0;
    final int visibleDatesLength = visibleDates.length;
    bool hasToday = monthViewSettings.numberOfWeeksInView > 0 && monthViewSettings.numberOfWeeksInView < 6 ||
        visibleDates[visibleDatesLength ~/ 2].month == today.month;
    if (hasToday) {
      hasToday = isDateWithInDateRange(visibleDates[0], visibleDates[visibleDatesLength - 1], today);
    }

    for (int i = 0; i < DateTime.daysPerWeek; i++) {
      final DateTime currentDate = visibleDates[i];
      String dayText = DateFormat(monthViewSettings.dayFormat, locale).format(currentDate).toString().toUpperCase();

      dayText = _updateViewHeaderFormat(monthViewSettings.dayFormat, dayText);

      if (hasToday && currentDate.weekday == today.weekday) {
        final Color? todayTextColor =
            CalendarViewHelper.getTodayHighlightTextColor(todayHighlightColor, todayTextStyle, calendarTheme);

        dayTextStyle = todayTextStyle != null
            ? todayTextStyle!.copyWith(fontSize: viewHeaderDayStyle.fontSize, color: todayTextColor)
            : viewHeaderDayStyle.copyWith(color: todayTextColor);
      } else {
        dayTextStyle = viewHeaderDayStyle;
      }

      _updateDayTextPainter(dayTextStyle, width, dayText);

      if (yPosition == 0) {
        yPosition = (viewHeaderHeight - _dayTextPainter.height) / 2;
      }

      _dayTextPainter.paint(canvas, Offset(xPosition + (width / 2 - _dayTextPainter.width / 2), yPosition));

      xPosition += width;
    }
  }

  void _addViewHeaderForTimeSlotViews(
      Canvas canvas, Size size, TextStyle viewHeaderDayStyle, TextStyle viewHeaderDateStyle, double width, DateTime today) {
    double xPosition, yPosition;
    final double labelWidth = view == CalendarView.day && timeLabelWidth < 50 ? 50 : timeLabelWidth;
    TextStyle dayTextStyle = viewHeaderDayStyle;
    TextStyle dateTextStyle = viewHeaderDateStyle;
    const double topPadding = 5;
    if (view == CalendarView.day) {
      width = labelWidth;
    }

    final Paint _linePainter = Paint();
    xPosition = view == CalendarView.day ? 0 : timeLabelWidth;
    yPosition = 2;
    final int visibleDatesLength = visibleDates.length;
    final double cellWidth = width / visibleDatesLength;
    for (int i = 0; i < visibleDatesLength; i++) {
      final DateTime currentDate = visibleDates[i];

      String dayText = DateFormat(timeSlotViewSettings.dayFormat, locale).format(currentDate).toString().toUpperCase();

      dayText = _updateViewHeaderFormat(timeSlotViewSettings.dayFormat, dayText);

      final String dateText = DateFormat(timeSlotViewSettings.dateFormat).format(currentDate).toString();
      final bool isToday = isSameDate(currentDate, today);
      if (isToday) {
        final Color? todayTextStyleColor = todayTextStyle != null ? todayTextStyle!.color : calendarTheme.todayTextStyle.color;
        final Color? todayTextColor =
            CalendarViewHelper.getTodayHighlightTextColor(todayHighlightColor, todayTextStyle, calendarTheme);
        dayTextStyle = todayTextStyle != null
            ? todayTextStyle!.copyWith(fontSize: viewHeaderDayStyle.fontSize, color: todayTextColor)
            : viewHeaderDayStyle.copyWith(color: todayTextColor);
        dateTextStyle = todayTextStyle != null
            ? todayTextStyle!.copyWith(fontSize: viewHeaderDateStyle.fontSize)
            : viewHeaderDateStyle.copyWith(color: todayTextStyleColor);
      } else {
        dayTextStyle = viewHeaderDayStyle;
        dateTextStyle = viewHeaderDateStyle;
      }

      if (!isDateWithInDateRange(minDate, maxDate, currentDate)) {
        if (calendarTheme.brightness == Brightness.light) {
          dayTextStyle = dayTextStyle.copyWith(color: Colors.black26);
          dateTextStyle = dateTextStyle.copyWith(color: Colors.black26);
        } else {
          dayTextStyle = dayTextStyle.copyWith(color: Colors.white38);
          dateTextStyle = dateTextStyle.copyWith(color: Colors.white38);
        }
      }

      _updateDayTextPainter(dayTextStyle, width, dayText);

      final TextSpan dateTextSpan = TextSpan(
        text: dateText,
        style: dateTextStyle,
      );

      _dateTextPainter.text = dateTextSpan;
      _dateTextPainter.textDirection = TextDirection.ltr;
      _dateTextPainter.textAlign = TextAlign.left;
      _dateTextPainter.textWidthBasis = TextWidthBasis.longestLine;
      _dateTextPainter.textScaleFactor = textScaleFactor;

      _dateTextPainter.layout(minWidth: 0, maxWidth: width);

      /// To calculate the day start position by width and day painter
      final double dayXPosition = (cellWidth - _dayTextPainter.width) / 2;

      /// To calculate the date start position by width and date painter
      final double dateXPosition = (cellWidth - _dateTextPainter.width) / 2;

      const int inBetweenPadding = 2;
      yPosition = size.height / 2 - (_dayTextPainter.height + topPadding + _dateTextPainter.height + inBetweenPadding) / 2;

      _dayTextPainter.paint(canvas, Offset(xPosition + dayXPosition, yPosition));

      if (isToday) {
        _drawTodayCircle(canvas, xPosition + dateXPosition, yPosition + topPadding + _dayTextPainter.height + inBetweenPadding,
            _dateTextPainter);
      }

      _dateTextPainter.paint(
          canvas, Offset(xPosition + dateXPosition, yPosition + topPadding + _dayTextPainter.height + inBetweenPadding));
      if (showWeekNumber &&
          ((currentDate.weekday == DateTime.monday) ||
              (view == CalendarView.workWeek &&
                  timeSlotViewSettings.nonWorkingDays.contains(DateTime.monday) &&
                  i == visibleDatesLength ~/ 2))) {
        final String weekNumber = DateTimeHelper.getWeekNumberOfYear(currentDate).toString();
        final TextStyle weekNumberTextStyle = weekNumberStyle.textStyle ?? calendarTheme.weekNumberTextStyle;
        final TextSpan dayTextSpan = TextSpan(
          text: weekNumber,
          style: weekNumberTextStyle,
        );
        _dateTextPainter.text = dayTextSpan;
        _dateTextPainter.textDirection = TextDirection.ltr;
        _dateTextPainter.textAlign = TextAlign.left;
        _dateTextPainter.textWidthBasis = TextWidthBasis.longestLine;
        _dateTextPainter.textScaleFactor = textScaleFactor;
        _dateTextPainter.layout(minWidth: 0, maxWidth: timeLabelWidth);
        final double weekNumberPosition = (timeLabelWidth - _dateTextPainter.width) / 2;
        final double weekNumberYPosition = size.height / 2 -
            (_dayTextPainter.height + topPadding + _dateTextPainter.height + inBetweenPadding) / 2 +
            topPadding +
            _dayTextPainter.height +
            inBetweenPadding;
        const double padding = 10;
        final Rect rect = Rect.fromLTRB(weekNumberPosition - padding, weekNumberYPosition - (padding / 2),
            weekNumberPosition + _dateTextPainter.width + padding, weekNumberYPosition + _dateTextPainter.height + (padding / 2));
        _linePainter.style = PaintingStyle.fill;
        _linePainter.color = weekNumberStyle.backgroundColor ?? calendarTheme.weekNumberBackgroundColor!;
        final RRect roundedRect = RRect.fromRectAndRadius(rect, const Radius.circular(padding / 2));
        canvas.drawRRect(roundedRect, _linePainter);
        _dateTextPainter.paint(canvas, Offset(weekNumberPosition, weekNumberYPosition));
      }

      xPosition += cellWidth;
    }
  }

  String _updateViewHeaderFormat(String dayFormat, String dayText) {
    switch (view) {
      case CalendarView.day:
      case CalendarView.schedule:
      case CalendarView.timelineDay:
      case CalendarView.timelineWeek:
      case CalendarView.timelineWorkWeek:
      case CalendarView.timelineMonth:
        break;
      case CalendarView.month:
      case CalendarView.week:
      case CalendarView.workWeek:
        {
          //// EE format value shows the week days as S, M, T, W, T, F, S.
          if (dayFormat == 'EE' && (locale.contains('en'))) {
            return dayText[0];
          }
        }
    }

    return dayText;
  }

  void _updateDayTextPainter(TextStyle dayTextStyle, double width, String dayText) {
    final TextSpan dayTextSpan = TextSpan(
      text: dayText,
      style: dayTextStyle,
    );

    _dayTextPainter.text = dayTextSpan;
    _dayTextPainter.textDirection = TextDirection.ltr;
    _dayTextPainter.textAlign = TextAlign.left;
    _dayTextPainter.textWidthBasis = TextWidthBasis.longestLine;
    _dayTextPainter.textScaleFactor = textScaleFactor;

    _dayTextPainter.layout(minWidth: 0, maxWidth: width);
  }

  double _getViewHeaderWidth(double width) {
    switch (view) {
      case CalendarView.timelineDay:
      case CalendarView.timelineWeek:
      case CalendarView.timelineWorkWeek:
      case CalendarView.timelineMonth:
      case CalendarView.schedule:
        return 0;
      case CalendarView.month:
        return width / DateTime.daysPerWeek;
      case CalendarView.day:
        return timeLabelWidth;
      case CalendarView.week:
      case CalendarView.workWeek:
        return width - timeLabelWidth;
    }
  }

  @override
  bool shouldRepaint(_ViewHeaderViewPainter oldDelegate) {
    final _ViewHeaderViewPainter oldWidget = oldDelegate;
    return oldWidget.visibleDates != visibleDates ||
        oldWidget.viewHeaderStyle != viewHeaderStyle ||
        oldWidget.viewHeaderHeight != viewHeaderHeight ||
        oldWidget.todayHighlightColor != todayHighlightColor ||
        oldWidget.timeSlotViewSettings != timeSlotViewSettings ||
        oldWidget.monthViewSettings != monthViewSettings ||
        oldWidget.cellBorderColor != cellBorderColor ||
        oldWidget.calendarTheme != calendarTheme ||
        oldWidget.locale != locale ||
        oldWidget.todayTextStyle != todayTextStyle ||
        oldWidget.textScaleFactor != textScaleFactor ||
        oldWidget.weekNumberStyle != weekNumberStyle ||
        oldWidget.showWeekNumber != showWeekNumber;
  }

  //// draw today highlight circle in view header.
  void _drawTodayCircle(Canvas canvas, double x, double y, TextPainter dateTextPainter) {
    _circlePainter.color = todayHighlightColor!;
    const double circlePadding = 5;
    final double painterWidth = dateTextPainter.width / 2;
    final double painterHeight = dateTextPainter.height / 2;
    final double radius = painterHeight > painterWidth ? painterHeight : painterWidth;
    canvas.drawCircle(Offset(x + painterWidth, y + painterHeight), radius + circlePadding, _circlePainter);
  }

  /// overrides this property to build the semantics information which uses to
  /// return the required information for accessibility, need to return the list
  /// of custom painter semantics which contains the rect area and the semantics
  /// properties for accessibility
  @override
  SemanticsBuilderCallback get semanticsBuilder {
    return (Size size) {
      return _getSemanticsBuilder(size);
    };
  }

  @override
  bool shouldRebuildSemantics(_ViewHeaderViewPainter oldDelegate) {
    final _ViewHeaderViewPainter oldWidget = oldDelegate;
    return oldWidget.visibleDates != visibleDates;
  }

  String _getAccessibilityText(DateTime date) {
    if (!isDateWithInDateRange(minDate, maxDate, date)) {
      return DateFormat('EEEEE').format(date).toString() + DateFormat('dd/MMMM/yyyy').format(date).toString() + ', Disabled date';
    }

    return DateFormat('EEEEE').format(date).toString() + DateFormat('dd/MMMM/yyyy').format(date).toString();
  }

  List<CustomPainterSemantics> _getSemanticsForMonthViewHeader(Size size) {
    final List<CustomPainterSemantics> semanticsBuilder = <CustomPainterSemantics>[];
    final double cellWidth = size.width / DateTime.daysPerWeek;
    double left = 0;
    const double top = 0;
    for (int i = 0; i < DateTime.daysPerWeek; i++) {
      semanticsBuilder.add(CustomPainterSemantics(
        rect: Rect.fromLTWH(left, top, cellWidth, size.height),
        properties: SemanticsProperties(
          label: DateFormat('EEEEE').format(visibleDates[i]).toString().toUpperCase(),
          textDirection: TextDirection.ltr,
        ),
      ));

      left += cellWidth;
    }

    return semanticsBuilder;
  }

  List<CustomPainterSemantics> _getSemanticsForDayHeader(Size size) {
    final List<CustomPainterSemantics> semanticsBuilder = <CustomPainterSemantics>[];
    const double top = 0;
    double left = view == CalendarView.day ? 0 : timeLabelWidth;
    final double cellWidth = view == CalendarView.day ? size.width : (size.width - timeLabelWidth) / visibleDates.length;

    for (int i = 0; i < visibleDates.length; i++) {
      final DateTime visibleDate = visibleDates[i];
      if (showWeekNumber &&
          ((visibleDate.weekday == DateTime.monday && view != CalendarView.day) ||
              (view == CalendarView.workWeek &&
                  timeSlotViewSettings.nonWorkingDays.contains(DateTime.monday) &&
                  i == visibleDates.length ~/ 2))) {
        final int weekNumber = DateTimeHelper.getWeekNumberOfYear(visibleDate);
        semanticsBuilder.add(CustomPainterSemantics(
            rect: Rect.fromLTWH(
              0,
              0,
              timeLabelWidth,
              viewHeaderHeight,
            ),
            properties: SemanticsProperties(
              label: 'week' + weekNumber.toString(),
              textDirection: TextDirection.ltr,
            )));
      }
      semanticsBuilder.add(CustomPainterSemantics(
        rect: Rect.fromLTWH(left, top, cellWidth, size.height),
        properties: SemanticsProperties(
          label: _getAccessibilityText(visibleDates[i]),
          textDirection: TextDirection.ltr,
        ),
      ));

      left += cellWidth;
    }

    return semanticsBuilder;
  }

  List<CustomPainterSemantics> _getSemanticsBuilder(Size size) {
    switch (view) {
      case CalendarView.schedule:
      case CalendarView.timelineDay:
      case CalendarView.timelineWeek:
      case CalendarView.timelineWorkWeek:
      case CalendarView.timelineMonth:
        return <CustomPainterSemantics>[];
      case CalendarView.month:
        return _getSemanticsForMonthViewHeader(size);
      case CalendarView.day:
      case CalendarView.week:
      case CalendarView.workWeek:
        return _getSemanticsForDayHeader(size);
    }
  }
}

class _SelectionPainter extends CustomPainter {
  _SelectionPainter(
      this.calendar,
      this.view,
      this.visibleDates,
      this.selectedDate,
      this.selectionDecoration,
      this.timeIntervalHeight,
      this.calendarTheme,
      this.repaintNotifier,
      this.selectedResourceIndex,
      this.resourceItemHeight,
      this.showWeekNumber,
      this.getCalendarState)
      : super(repaint: repaintNotifier);

  final SfCalendar calendar;
  final CalendarView view;
  final SfCalendarThemeData calendarTheme;
  final List<DateTime> visibleDates;
  Decoration? selectionDecoration;
  DateTime? selectedDate;
  final double timeIntervalHeight;
  final UpdateCalendarState getCalendarState;
  int selectedResourceIndex;
  final double? resourceItemHeight;

  late BoxPainter _boxPainter;
  AppointmentView? appointmentView;
  double _cellWidth = 0, _cellHeight = 0, _xPosition = 0, _yPosition = 0;
  final ValueNotifier<bool> repaintNotifier;
  final UpdateCalendarStateDetails _updateCalendarStateDetails = UpdateCalendarStateDetails();
  final bool showWeekNumber;

  @override
  void paint(Canvas canvas, Size size) {
    selectionDecoration ??= BoxDecoration(
      color: Colors.transparent,
      border: Border.all(color: calendarTheme.selectionBorderColor!, width: 2),
      borderRadius: const BorderRadius.all(Radius.circular(2)),
      shape: BoxShape.rectangle,
    );

    getCalendarState(_updateCalendarStateDetails);
    selectedDate = _updateCalendarStateDetails.selectedDate;
    final bool isMonthView = view == CalendarView.month || view == CalendarView.timelineMonth;
    final int timeInterval = CalendarViewHelper.getTimeInterval(calendar.timeSlotViewSettings);
    if (selectedDate != null &&
        ((isMonthView && !isDateWithInDateRange(calendar.minDate, calendar.maxDate, selectedDate)) ||
            (!isMonthView &&
                !CalendarViewHelper.isDateTimeWithInDateTimeRange(
                    calendar.minDate, calendar.maxDate, selectedDate!, timeInterval)))) {
      return;
    }
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final double timeLabelWidth = CalendarViewHelper.getTimeLabelWidth(calendar.timeSlotViewSettings.timeRulerSize, view);
    double width = size.width;
    final bool isTimeline = CalendarViewHelper.isTimelineView(view);
    if (view != CalendarView.month && !isTimeline) {
      width -= timeLabelWidth;
    }

    final bool isResourceEnabled = isTimeline && CalendarViewHelper.isResourceEnabled(calendar.dataSource, view);
    if ((selectedDate == null && appointmentView == null) ||
        visibleDates != _updateCalendarStateDetails.currentViewVisibleDates ||
        (isResourceEnabled && selectedResourceIndex == -1)) {
      return;
    }

    if (!isTimeline) {
      if (view == CalendarView.month) {
        _cellWidth = width / DateTime.daysPerWeek;
        _cellHeight = size.height / calendar.monthViewSettings.numberOfWeeksInView;
      } else {
        _cellWidth = width / visibleDates.length;
        _cellHeight = timeIntervalHeight;
      }
    } else {
      _cellWidth = timeIntervalHeight;
      _cellHeight = size.height;

      /// The selection view must render on the resource area alone, when the
      /// resource enabled.
      if (isResourceEnabled && selectedResourceIndex >= 0) {
        _cellHeight = resourceItemHeight!;
      }
    }

    if (appointmentView != null && appointmentView!.appointment != null) {
      _drawAppointmentSelection(canvas);
    }

    switch (view) {
      case CalendarView.schedule:
        return;
      case CalendarView.month:
        {
          if (selectedDate != null) {
            _drawMonthSelection(canvas, size, width);
          }
        }
        break;
      case CalendarView.day:
        {
          if (selectedDate != null) {
            _drawDaySelection(canvas, size, width, timeLabelWidth);
          }
        }
        break;
      case CalendarView.week:
      case CalendarView.workWeek:
        {
          if (selectedDate != null) {
            _drawWeekSelection(canvas, size, timeLabelWidth, width);
          }
        }
        break;
      case CalendarView.timelineDay:
        {
          if (selectedDate != null) {
            _drawTimelineDaySelection(canvas, size, width);
          }
        }
        break;
      case CalendarView.timelineWeek:
      case CalendarView.timelineWorkWeek:
        {
          if (selectedDate != null) {
            _drawTimelineWeekSelection(canvas, size, width);
          }
        }
        break;
      case CalendarView.timelineMonth:
        {
          if (selectedDate != null) {
            _drawTimelineMonthSelection(canvas, size, width);
          }
        }
    }
  }

  @override
  bool? hitTest(Offset position) {
    return false;
  }

  void _drawMonthSelection(Canvas canvas, Size size, double width) {
    final int visibleDatesLength = visibleDates.length;
    if (!isDateWithInDateRange(visibleDates[0], visibleDates[visibleDatesLength - 1], selectedDate)) {
      return;
    }

    final int currentMonth = visibleDates[visibleDatesLength ~/ 2].month;

    /// Check the selected cell date as trailing or leading date when
    /// [SfCalendar] month not shown leading and trailing dates.
    if (!CalendarViewHelper.isCurrentMonthDate(calendar.monthViewSettings.numberOfWeeksInView,
        calendar.monthViewSettings.showTrailingAndLeadingDates, currentMonth, selectedDate!)) {
      return;
    }

    if (CalendarViewHelper.isDateInDateCollection(calendar.blackoutDates, selectedDate!)) {
      return;
    }

    for (int i = 0; i < visibleDatesLength; i++) {
      if (isSameDate(visibleDates[i], selectedDate)) {
        final double weekNumberPanelWidth = CalendarViewHelper.getWeekNumberPanelWidth(showWeekNumber, width);
        _cellWidth = (size.width - weekNumberPanelWidth) / DateTime.daysPerWeek;
        final int columnIndex = (i / DateTime.daysPerWeek).truncate();
        _yPosition = columnIndex * _cellHeight;
        final int rowIndex = i % DateTime.daysPerWeek;
        _xPosition = rowIndex * _cellWidth + weekNumberPanelWidth;
        _drawSlotSelection(width, size.height, canvas);
        break;
      }
    }
  }

  void _drawDaySelection(Canvas canvas, Size size, double width, double timeLabelWidth) {
    if (isSameDate(visibleDates[0], selectedDate)) {
      _xPosition = timeLabelWidth;

      selectedDate = _updateSelectedDate();

      _yPosition = AppointmentHelper.timeToPosition(calendar, selectedDate!, timeIntervalHeight);
      _drawSlotSelection(width + timeLabelWidth, size.height, canvas);
    }
  }

  /// Method to update the selected date, when the selected date not fill the
  /// exact time slot, and render the mid of time slot, on this scenario we
  /// have updated the selected date to update the exact time slot.
  ///
  /// Eg: If the time interval is 60min, and the selected date is 12.45 PM the
  /// selection renders on the center of 12 to 1 PM slot, to avoid this we have
  /// modified the selected date to 1 PM so that the selection will render the
  /// exact time slot.
  DateTime _updateSelectedDate() {
    final int timeInterval = CalendarViewHelper.getTimeInterval(calendar.timeSlotViewSettings);
    final int startHour = calendar.timeSlotViewSettings.startHour.toInt();
    final double startMinute = (calendar.timeSlotViewSettings.startHour - calendar.timeSlotViewSettings.startHour.toInt()) * 60;
    final int selectedMinutes = ((selectedDate!.hour - startHour) * 60) + (selectedDate!.minute - startMinute.toInt());
    if (selectedMinutes % timeInterval != 0) {
      final int diff = selectedMinutes % timeInterval;
      if (diff < (timeInterval / 2)) {
        return selectedDate!.subtract(Duration(minutes: diff));
      } else {
        return selectedDate!.add(Duration(minutes: timeInterval - diff));
      }
    }

    return selectedDate!;
  }

  void _drawWeekSelection(Canvas canvas, Size size, double timeLabelWidth, double width) {
    final int visibleDatesLength = visibleDates.length;
    if (isDateWithInDateRange(visibleDates[0], visibleDates[visibleDatesLength - 1], selectedDate)) {
      for (int i = 0; i < visibleDatesLength; i++) {
        if (isSameDate(selectedDate, visibleDates[i])) {
          final int rowIndex = i;
          _xPosition = timeLabelWidth + _cellWidth * rowIndex;

          selectedDate = _updateSelectedDate();
          _yPosition = AppointmentHelper.timeToPosition(calendar, selectedDate!, timeIntervalHeight);
          _drawSlotSelection(width + timeLabelWidth, size.height, canvas);
          break;
        }
      }
    }
  }

  /// Returns the yPosition for selection view based on resource associated with
  /// the selected cell in  timeline views when resource enabled.
  double _getTimelineYPosition() {
    if (selectedResourceIndex == -1) {
      return 0;
    }

    return selectedResourceIndex * resourceItemHeight!;
  }

  void _drawTimelineDaySelection(Canvas canvas, Size size, double width) {
    if (isSameDate(visibleDates[0], selectedDate)) {
      selectedDate = _updateSelectedDate();
      _xPosition = AppointmentHelper.timeToPosition(calendar, selectedDate!, timeIntervalHeight);
      _yPosition = _getTimelineYPosition();
      final double height = selectedResourceIndex == -1 ? size.height : _yPosition + resourceItemHeight!;
      _drawSlotSelection(width, height, canvas);
    }
  }

  void _drawTimelineMonthSelection(Canvas canvas, Size size, double width) {
    if (!isDateWithInDateRange(visibleDates[0], visibleDates[visibleDates.length - 1], selectedDate)) {
      return;
    }

    if (CalendarViewHelper.isDateInDateCollection(calendar.blackoutDates, selectedDate!)) {
      return;
    }

    for (int i = 0; i < visibleDates.length; i++) {
      if (isSameDate(visibleDates[i], selectedDate)) {
        _yPosition = _getTimelineYPosition();
        _xPosition = i * _cellWidth;
        final double height = selectedResourceIndex == -1 ? size.height : _yPosition + resourceItemHeight!;
        _drawSlotSelection(width, height, canvas);
        break;
      }
    }
  }

  void _drawTimelineWeekSelection(Canvas canvas, Size size, double width) {
    if (isDateWithInDateRange(visibleDates[0], visibleDates[visibleDates.length - 1], selectedDate)) {
      selectedDate = _updateSelectedDate();
      for (int i = 0; i < visibleDates.length; i++) {
        if (isSameDate(selectedDate, visibleDates[i])) {
          final double singleViewWidth = width / visibleDates.length;
          _xPosition = (i * singleViewWidth) + AppointmentHelper.timeToPosition(calendar, selectedDate!, timeIntervalHeight);
          _yPosition = _getTimelineYPosition();
          final double height = selectedResourceIndex == -1 ? size.height : _yPosition + resourceItemHeight!;
          _drawSlotSelection(width, height, canvas);
          break;
        }
      }
    }
  }

  void _drawAppointmentSelection(Canvas canvas) {
    Rect rect = appointmentView!.appointmentRect!.outerRect;
    rect = Rect.fromLTRB(rect.left, rect.top, rect.right, rect.bottom);
    _boxPainter = selectionDecoration!.createBoxPainter(_updateSelectionDecorationPainter);
    _boxPainter.paint(canvas, Offset(rect.left, rect.top), ImageConfiguration(size: rect.size));
  }

  /// Used to pass the argument of create box painter and it is called when
  /// decoration have asynchronous data like image.
  void _updateSelectionDecorationPainter() {
    repaintNotifier.value = !repaintNotifier.value;
  }

  void _drawSlotSelection(double width, double height, Canvas canvas) {
    //// padding used to avoid first, last row and column selection clipping.
    const double padding = 0.5;
    final Rect rect = Rect.fromLTRB(
        _xPosition == 0 ? _xPosition + padding : _xPosition,
        _yPosition == 0 ? _yPosition + padding : _yPosition,
        _xPosition + _cellWidth == width ? _xPosition + _cellWidth - padding : _xPosition + _cellWidth,
        _yPosition + _cellHeight == height ? _yPosition + _cellHeight - padding : _yPosition + _cellHeight);

    _boxPainter = selectionDecoration!.createBoxPainter(_updateSelectionDecorationPainter);
    _boxPainter.paint(canvas, Offset(rect.left, rect.top), ImageConfiguration(size: rect.size, textDirection: TextDirection.ltr));
  }

  @override
  bool shouldRepaint(_SelectionPainter oldDelegate) {
    final _SelectionPainter oldWidget = oldDelegate;
    return oldWidget.selectionDecoration != selectionDecoration ||
        oldWidget.selectedDate != selectedDate ||
        oldWidget.view != view ||
        oldWidget.visibleDates != visibleDates ||
        oldWidget.selectedResourceIndex != selectedResourceIndex;
  }
}

class _TimeRulerView extends CustomPainter {
  _TimeRulerView(this.horizontalLinesCount, this.timeIntervalHeight, this.timeSlotViewSettings, this.cellBorderColor, this.locale,
      this.calendarTheme, this.isTimelineView, this.visibleDates, this.textScaleFactor);

  final double horizontalLinesCount;
  final double timeIntervalHeight;
  final TimeSlotViewSettings timeSlotViewSettings;
  final String locale;
  final SfCalendarThemeData calendarTheme;
  final Color? cellBorderColor;
  final bool isTimelineView;
  final List<DateTime> visibleDates;
  final double textScaleFactor;
  final Paint _linePainter = Paint();
  final TextPainter _textPainter = TextPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));
    const double offset = 0.5;
    double xPosition, yPosition;
    final DateTime date = DateTime.now();
    xPosition = 0;
    yPosition = timeIntervalHeight;
    _linePainter.strokeWidth = offset;
    _linePainter.color = cellBorderColor ?? calendarTheme.cellBorderColor;

    if (!isTimelineView) {
      final double lineXPosition = size.width - offset;
      // Draw vertical time label line
      canvas.drawLine(Offset(lineXPosition, 0), Offset(lineXPosition, size.height), _linePainter);
    }

    _textPainter.textDirection = TextDirection.ltr;
    _textPainter.textWidthBasis = TextWidthBasis.longestLine;
    _textPainter.textScaleFactor = textScaleFactor;

    final TextStyle timeTextStyle = timeSlotViewSettings.timeTextStyle ?? calendarTheme.timeTextStyle;

    final double hour = (timeSlotViewSettings.startHour - timeSlotViewSettings.startHour.toInt()) * 60;
    if (isTimelineView) {
      canvas.drawLine(const Offset(0, 0), Offset(size.width, 0), _linePainter);
      final double timelineViewWidth = timeIntervalHeight * horizontalLinesCount;
      for (int i = 0; i < visibleDates.length; i++) {
        _drawTimeLabels(canvas, size, date, hour, xPosition, yPosition, timeTextStyle);
        xPosition += timelineViewWidth;
      }
    } else {
      _drawTimeLabels(canvas, size, date, hour, xPosition, yPosition, timeTextStyle);
    }
  }

  /// Draws the time labels in the time label view for timeslot views in
  /// calendar.
  void _drawTimeLabels(
      Canvas canvas, Size size, DateTime date, double hour, double xPosition, double yPosition, TextStyle timeTextStyle) {
    const int padding = 5;
    final int timeInterval = CalendarViewHelper.getTimeInterval(timeSlotViewSettings);

    /// For timeline view we will draw 24 lines where as in day, week and work
    /// week view we will draw 23 lines excluding the 12 AM, hence to rectify
    /// this the i value handled accordingly.
    for (int i = isTimelineView ? 0 : 1; i <= (isTimelineView ? horizontalLinesCount - 1 : horizontalLinesCount); i++) {
      if (isTimelineView) {
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(xPosition, 0, timeIntervalHeight, size.height));
        canvas.restore();
        canvas.drawLine(Offset(xPosition, 0), Offset(xPosition, size.height), _linePainter);
      }

      final double minute = (i * timeInterval) + hour;
      date = DateTime(date.day, date.month, date.year, timeSlotViewSettings.startHour.toInt(), minute.toInt());
      final String time = DateFormat(timeSlotViewSettings.timeFormat, locale).format(date).toString();
      final TextSpan span = TextSpan(
        text: time,
        style: timeTextStyle,
      );

      final double cellWidth = isTimelineView ? timeIntervalHeight : size.width;

      _textPainter.text = span;
      _textPainter.layout(minWidth: 0, maxWidth: cellWidth);
      if (isTimelineView && _textPainter.height > size.height) {
        return;
      }

      double startXPosition = (cellWidth - _textPainter.width) / 2;
      if (startXPosition < 0) {
        startXPosition = 0;
      }

      if (isTimelineView) {
        startXPosition = xPosition;
      }

      double startYPosition = yPosition - (_textPainter.height / 2);

      if (isTimelineView) {
        startYPosition = (size.height - _textPainter.height) / 2;
        startXPosition = startXPosition + padding;
      }

      _textPainter.paint(canvas, Offset(startXPosition, startYPosition));

      if (!isTimelineView) {
        final Offset start = Offset(size.width - (startXPosition / 2), yPosition);
        final Offset end = Offset(size.width, yPosition);
        canvas.drawLine(start, end, _linePainter);
        yPosition += timeIntervalHeight;
        if (yPosition.round() == size.height.round()) {
          break;
        }
      } else {
        xPosition += timeIntervalHeight;
      }
    }
  }

  @override
  bool shouldRepaint(_TimeRulerView oldDelegate) {
    final _TimeRulerView oldWidget = oldDelegate;
    return oldWidget.timeSlotViewSettings != timeSlotViewSettings ||
        oldWidget.cellBorderColor != cellBorderColor ||
        oldWidget.calendarTheme != calendarTheme ||
        oldWidget.locale != locale ||
        oldWidget.visibleDates != visibleDates ||
        oldWidget.isTimelineView != isTimelineView ||
        oldWidget.textScaleFactor != textScaleFactor;
  }
}

class _CalendarMultiChildContainer extends Stack {
  _CalendarMultiChildContainer(
      {this.painter, List<Widget> children = const <Widget>[], required this.width, required this.height})
      : super(children: children);
  final CustomPainter? painter;
  final double width;
  final double height;

  @override
  RenderStack createRenderObject(BuildContext context) {
    final Directionality? widget = context.dependOnInheritedWidgetOfExactType<Directionality>();
    return _MultiChildContainerRenderObject(width, height,
        painter: painter, direction: widget != null ? widget.textDirection : null);
  }

  @override
  void updateRenderObject(BuildContext context, RenderStack renderObject) {
    super.updateRenderObject(context, renderObject);
    if (renderObject is _MultiChildContainerRenderObject) {
      final Directionality? widget = context.dependOnInheritedWidgetOfExactType<Directionality>();
      renderObject
        ..width = width
        ..height = height
        ..painter = painter
        ..textDirection = widget != null ? widget.textDirection : null;
    }
  }
}

class _MultiChildContainerRenderObject extends RenderStack {
  _MultiChildContainerRenderObject(this._width, this._height, {CustomPainter? painter, TextDirection? direction})
      : _painter = painter,
        super(textDirection: direction);

  CustomPainter? get painter => _painter;
  CustomPainter? _painter;

  set painter(CustomPainter? value) {
    if (_painter == value) {
      return;
    }

    final CustomPainter? oldPainter = _painter;
    _painter = value;
    _updatePainter(_painter, oldPainter);
    if (attached) {
      oldPainter?.removeListener(markNeedsPaint);
      _painter?.addListener(markNeedsPaint);
    }
  }

  double get width => _width;

  set width(double value) {
    if (_width == value) {
      return;
    }

    _width = value;
    markNeedsLayout();
  }

  double _width;
  double _height;

  double get height => _height;

  set height(double value) {
    if (_height == value) {
      return;
    }

    _height = value;
    markNeedsLayout();
  }

  /// Caches [SemanticsNode]s created during [assembleSemanticsNode] so they
  /// can be re-used when [assembleSemanticsNode] is called again. This ensures
  /// stable ids for the [SemanticsNode]s of children across
  /// [assembleSemanticsNode] invocations.
  /// Ref: assembleSemanticsNode method in RenderParagraph class
  /// (https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/rendering/paragraph.dart)
  List<SemanticsNode>? _cacheNodes;

  void _updatePainter(CustomPainter? newPainter, CustomPainter? oldPainter) {
    if (newPainter == null) {
      markNeedsPaint();
    } else if (oldPainter == null || newPainter.runtimeType != oldPainter.runtimeType || newPainter.shouldRepaint(oldPainter)) {
      markNeedsPaint();
    }

    if (newPainter == null) {
      if (attached) {
        markNeedsSemanticsUpdate();
      }
    } else if (oldPainter == null ||
        newPainter.runtimeType != oldPainter.runtimeType ||
        newPainter.shouldRebuildSemantics(oldPainter)) {
      markNeedsSemanticsUpdate();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _painter?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _painter?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void performLayout() {
    final Size widgetSize = constraints.biggest;
    size =
        Size(widgetSize.width.isInfinite ? width : widgetSize.width, widgetSize.height.isInfinite ? height : widgetSize.height);
    for (dynamic child = firstChild; child != null; child = childAfter(child)) {
      child.layout(constraints);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_painter != null) {
      _painter!.paint(context.canvas, size);
    }

    paintStack(context, offset);
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config.isSemanticBoundary = true;
  }

  @override
  void assembleSemanticsNode(
    SemanticsNode node,
    SemanticsConfiguration config,
    Iterable<SemanticsNode> children,
  ) {
    _cacheNodes ??= <SemanticsNode>[];
    final List<CustomPainterSemantics> semantics = _semanticsBuilder(size);
    final List<SemanticsNode> semanticsNodes = <SemanticsNode>[];
    for (int i = 0; i < semantics.length; i++) {
      final CustomPainterSemantics currentSemantics = semantics[i];
      final SemanticsNode newChild =
          _cacheNodes!.isNotEmpty ? _cacheNodes!.removeAt(0) : SemanticsNode(key: currentSemantics.key);

      final SemanticsProperties properties = currentSemantics.properties;
      final SemanticsConfiguration config = SemanticsConfiguration();
      if (properties.label != null) {
        config.label = properties.label!;
      }
      if (properties.textDirection != null) {
        config.textDirection = properties.textDirection;
      }

      newChild.updateWith(
        config: config,
        // As of now CustomPainter does not support multiple tree levels.
        childrenInInversePaintOrder: const <SemanticsNode>[],
      );

      newChild
        ..rect = currentSemantics.rect
        ..transform = currentSemantics.transform
        ..tags = currentSemantics.tags;

      semanticsNodes.add(newChild);
    }

    final List<SemanticsNode> finalChildren = <SemanticsNode>[];
    finalChildren.addAll(semanticsNodes);
    finalChildren.addAll(children);
    _cacheNodes = semanticsNodes;
    super.assembleSemanticsNode(node, config, finalChildren);
  }

  @override
  void clearSemantics() {
    super.clearSemantics();
    _cacheNodes = null;
  }

  SemanticsBuilderCallback get _semanticsBuilder {
    final List<CustomPainterSemantics> semantics = <CustomPainterSemantics>[];
    if (painter != null) {
      semantics.addAll(painter!.semanticsBuilder!(size));
    }
    // ignore: avoid_as
    for (RenderRepaintBoundary? child = firstChild! as RenderRepaintBoundary;
        child != null;
        // ignore: avoid_as
        child = childAfter(child) as RenderRepaintBoundary?) {
      if (child.child is! CustomCalendarRenderObject) {
        continue;
      }

      final CustomCalendarRenderObject appointmentRenderObject =
          // ignore: avoid_as
          child.child! as CustomCalendarRenderObject;
      semantics.addAll(appointmentRenderObject.semanticsBuilder!(size));
    }

    return (Size size) {
      return semantics;
    };
  }
}

class _CustomNeverScrollableScrollPhysics extends NeverScrollableScrollPhysics {
  /// Creates scroll physics that does not let the user scroll.
  const _CustomNeverScrollableScrollPhysics({ScrollPhysics? parent}) : super(parent: parent);

  @override
  _CustomNeverScrollableScrollPhysics applyTo(ScrollPhysics? ancestor) {
    /// Set the clamping scroll physics as default parent for never scroll
    /// physics, because flutter framework set different parent physics
    /// based on platform(iOS, Android, etc.,)
    return _CustomNeverScrollableScrollPhysics(
        parent: buildParent(const ClampingScrollPhysics(parent: RangeMaintainingScrollPhysics())));
  }
}

class _CurrentTimeIndicator extends CustomPainter {
  _CurrentTimeIndicator(this.timeIntervalSize, this.timeRulerSize, this.timeSlotViewSettings, this.isTimelineView,
      this.visibleDates, this.todayHighlightColor, ValueNotifier<int> repaintNotifier)
      : super(repaint: repaintNotifier);
  final double timeIntervalSize;
  final TimeSlotViewSettings timeSlotViewSettings;
  final bool isTimelineView;
  final List<DateTime> visibleDates;
  final double timeRulerSize;
  final Color? todayHighlightColor;

  @override
  void paint(Canvas canvas, Size size) {
    final DateTime now = DateTime.now();
    final int hours = now.hour;
    final int minutes = now.minute;
    final int totalMinutes = (hours * 60) + minutes;
    final int viewStartMinutes = (timeSlotViewSettings.startHour * 60).toInt();
    final int viewEndMinutes = (timeSlotViewSettings.endHour * 60).toInt();
    if (totalMinutes < viewStartMinutes || totalMinutes > viewEndMinutes) {
      return;
    }

    int index = -1;
    for (int i = 0; i < visibleDates.length; i++) {
      final DateTime date = visibleDates[i];
      if (isSameDate(date, now)) {
        index = i;
        break;
      }
    }

    if (index == -1) {
      return;
    }

    final double minuteHeight = timeIntervalSize / CalendarViewHelper.getTimeInterval(timeSlotViewSettings);
    final double currentTimePosition =
        CalendarViewHelper.getTimeToPosition(Duration(hours: hours, minutes: minutes), timeSlotViewSettings, minuteHeight);
    final Paint painter = Paint()
      ..color = todayHighlightColor!
      ..strokeWidth = 1
      ..isAntiAlias = true
      ..style = PaintingStyle.fill;
    if (isTimelineView) {
      final double viewSize = size.width / visibleDates.length;
      final double startXPosition = (index * viewSize) + currentTimePosition;
      canvas.drawCircle(Offset(startXPosition, 5), 5, painter);
      canvas.drawLine(Offset(startXPosition, 0), Offset(startXPosition, size.height), painter);
    } else {
      final double viewSize = (size.width - timeRulerSize) / visibleDates.length;
      final double startYPosition = currentTimePosition;
      final double viewStartPosition = (index * viewSize) + timeRulerSize;
      final double viewEndPosition = viewStartPosition + viewSize;
      final double startXPosition = viewStartPosition < 5 ? 5 : viewStartPosition;
      canvas.drawCircle(Offset(startXPosition, startYPosition), 5, painter);
      canvas.drawLine(Offset(viewStartPosition, startYPosition), Offset(viewEndPosition, startYPosition), painter);
    }
  }

  @override
  bool? hitTest(Offset position) {
    return false;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

/// Returns the single view width from the time line view for time line
double _getSingleViewWidthForTimeLineView(_CalendarViewState viewState) {
  return (viewState._scrollController!.position.maxScrollExtent + viewState._scrollController!.position.viewportDimension) /
      viewState.widget.visibleDates.length;
}
