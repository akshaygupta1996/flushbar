library flushbar;

import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/scheduler.dart';

class _FlushbarRoute<T> extends OverlayRoute<T> {
  _FlushbarRoute({
    @required this.theme,
    @required this.child,
    RouteSettings settings,
  }) : super(settings: settings);

  final Widget child;
  final ThemeData theme;

  @override
  Iterable<OverlayEntry> createOverlayEntries() {
    return [
      OverlayEntry(
          builder: (BuildContext context) {
            final Widget annotatedChild = new Semantics(
              child: child,
              focused: true,
              scopesRoute: true,
              explicitChildNodes: true,
            );
            return theme != null ? new Theme(data: theme, child: annotatedChild) : annotatedChild;
          },
          maintainState: false,
          opaque: false),
    ];
  }
}

Future<T> _showFlushbar<T>({@required BuildContext context, WidgetBuilder builder}) {
  assert(builder != null);

  return Navigator.of(context, rootNavigator: false).push(new _FlushbarRoute<T>(
      child: new Builder(builder: builder), theme: Theme.of(context), settings: RouteSettings(name: FLUSHBAR_ROUTE_NAME)));
}

const String FLUSHBAR_ROUTE_NAME = "/flushbarRoute";
typedef void FlushbarStatusCallback(FlushbarStatus status);

/// A custom widget so you can notify your user when you fell like he needs an explanation.
/// This is inspired on a custom view (Flashbar)[https://github.com/aritraroy/Flashbar] created for android.
///
/// [title] The title displayed to the user
/// [message] The message displayed to the user.
/// [titleText] If you need something more personalized, pass a [Text] widget to this variable. [title] will be ignored if this variable is not null.
/// [messageText] If you need something more personalized, pass a [Text] widget to this variable. [message] will be ignored if this variable is not null.
/// [icon] The [Icon] indication what kind of message you are displaying.
/// [backgroundColor] Flushbar background color. Will be ignored if [backgroundGradient] is not null.
/// [leftBarIndicatorColor] If not null, shows a left vertical bar to better indicate the humor of the notification. It is not possible to use it with a [Form] and I do not recommend using it with [LinearProgressIndicator].
/// [shadowColor] The shadow generated by the Flushbar. Leave it null if you don't want a shadow.
/// [backgroundGradient] Flushbar background gradient. Makes [backgroundColor] be ignored.
/// [mainButton] A [FlatButton] widget if you need an action from the user.
/// [duration] How long until Flushbar will hide itself (be dismissed). To make it indefinite, leave it null.
/// [isDismissible] Determines if the user can swipe to dismiss the bar. It is recommended that you set [duration] != null if [isDismissible] == false.
/// [flushbarPosition] (final) Flushbar can be based on [FlushbarPosition.TOP] or on [FlushbarPosition.BOTTOM] of your screen. [FlushbarPosition.BOTTOM] is the default.
/// [forwardAnimationCurve] (final) The [Curve] animation used when show() is called. [Curves.easeOut] is default.
/// [reverseAnimationCurve] (final) The [Curve] animation used when dismiss() is called. [Curves.fastOutSlowIn] is default.
/// [showProgressIndicator] true if you want to show a [LinearProgressIndicator].
/// [progressIndicatorController] An optional [AnimationController] when you want to controll the progress of your [LinearProgressIndicator].
/// [progressIndicatorBackgroundColor] a [LinearProgressIndicator] configuration parameter.
/// [progressIndicatorValueColor] a [LinearProgressIndicator] configuration parameter.
/// [userInputForm] A [TextFormField] in case you want a simple user input. Every other widget is ignored if this is not null.
class Flushbar<T extends Object> extends StatefulWidget {
  Flushbar({
    Key key,
    this.title,
    this.message,
    this.titleText,
    this.messageText,
    this.icon,
    this.backgroundColor = const Color(0xFF303030),
    this.leftBarIndicatorColor,
    this.shadowColor,
    this.backgroundGradient,
    this.mainButton,
    this.duration,
    this.isDismissible = true,
    this.showProgressIndicator = false,
    this.progressIndicatorController,
    this.progressIndicatorBackgroundColor,
    this.progressIndicatorValueColor,
    this.flushbarPosition = FlushbarPosition.BOTTOM,
    this.forwardAnimationCurve = Curves.easeOut,
    this.reverseAnimationCurve = Curves.fastOutSlowIn,
  }) : super(key: key);

  /// [onStatusChanged] A callback used to listen to Flushbar status [FlushbarStatus]. Set it using [setStatusListener()]
  FlushbarStatusCallback onStatusChanged = (FlushbarStatus status) {};
  String title;
  String message;
  Text titleText;
  Text messageText;
  Color backgroundColor;
  Color leftBarIndicatorColor;
  Color shadowColor;
  Gradient backgroundGradient;
  Icon icon;
  FlatButton mainButton;
  Duration duration;
  bool showProgressIndicator;
  AnimationController progressIndicatorController;
  Color progressIndicatorBackgroundColor;
  Animation<Color> progressIndicatorValueColor;
  bool isDismissible;
  Form userInputForm;

  final FlushbarPosition flushbarPosition;
  final Curve forwardAnimationCurve;
  final Curve reverseAnimationCurve;

  _FlushbarState _flushbarState;
  T _result;

  /// Show the flushbar. Kicks in [FlushbarStatus.IS_APPEARING] state followed by [FlushbarStatus.SHOWING]
  Future<T> show(BuildContext context) async {
    return await _showFlushbar<T>(
        context: context,
        builder: (BuildContext innerContext) {
          return this;
        });
  }

  /// Dismisses the flushbar causing is to return [result].
  void dismiss([T result]) {
    if (!_flushbarState._isDismissed()) {
      _result = result;
      _flushbarState._dismiss();
    }
  }

  /// Checks if the flushbar is visible
  bool isShowing() {
    return _flushbarState._isShowing();
  }

  /// Checks if the flushbar is dismissed
  bool isDismissed() {
    return _flushbarState._isDismissed();
  }

  @override
  State createState() {
    _flushbarState = new _FlushbarState<T>();

    return _flushbarState;
  }
}

class _FlushbarState<K extends Object> extends State<Flushbar> with TickerProviderStateMixin {
  _FlushbarState() {
    _animationStatusListener = (animationStatus) {
      switch (animationStatus) {
        case AnimationStatus.completed:
          {
            if (widget.onStatusChanged != null) {
              currentStatus = FlushbarStatus.SHOWING;
              widget.onStatusChanged(currentStatus);
            }
            _configureTimer();
            break;
          }

        case AnimationStatus.dismissed:
          {
            assert(widget._result is K || widget._result == null,
                "Flushbar is configured to return ${widget._result.runtimeType}. Check the value passed to dismiss([T result])!");
            (widget._result == null) ? Navigator.pop(context) : Navigator.pop(context, widget._result);

            currentStatus = FlushbarStatus.DISMISSED;
            widget.onStatusChanged(currentStatus);

            break;
          }

        case AnimationStatus.forward:
          {
            currentStatus = FlushbarStatus.IS_APPEARING;
            widget.onStatusChanged(currentStatus);

            break;
          }

        case AnimationStatus.reverse:
          {
            currentStatus = FlushbarStatus.IS_HIDING;
            widget.onStatusChanged(currentStatus);

            break;
          }
      }
    };
  }

  BoxShadow _boxShadow;
  FlushbarStatus currentStatus;
  Timer _timer;

  AnimationController _popController;
  Animation<Alignment> _popAnimation;
  AnimationController _fadeController;
  Animation<double> _fadeAnimation;

  EdgeInsets barInsets;
  AnimationStatusListener _animationStatusListener;

  final Widget _emptyWidget = SizedBox(width: 0.0, height: 0.0);
  final double _initialOpacity = 1.0;
  final double _finalOpacity = 0.4;

  final Duration _duration = Duration(seconds: 1);

  void _dismiss() {
    _popController.reverse();
    if (_timer != null && _timer.isActive) {
      _timer.cancel();
    }
  }

  bool _isShowing() {
    return _popController.isCompleted;
  }

  bool _isDismissed() {
    return _popController.isDismissed;
  }

  void _resetAnimations() {
    _popController.reset();
  }

  List<BoxShadow> _getBoxShadowList() {
    if (_boxShadow != null) {
      return [_boxShadow];
    } else {
      return null;
    }
  }

  void _configureTimer() {
    if (widget.duration != null) {
      if (_timer != null && _timer.isActive) {
        _timer.cancel();
      }
      _timer = new Timer(widget.duration, () {
        _popController.reverse();
      });
    } else {
      if (_timer != null) {
        _timer.cancel();
      }
    }
  }

  bool _isTitlePresent;
  double _messageTopMargin;

  @override
  void initState() {
    super.initState();

    assert(((widget.userInputForm != null || (widget.message != null || widget.messageText != null))),
        "Don't forget to show a message to your user!");

    _isTitlePresent = (widget.title != null || widget.titleText != null);

    _messageTopMargin = _isTitlePresent ? 6.0 : 16.0;

    Alignment initialAlignment;
    Alignment endAlignment;

    switch (widget.flushbarPosition) {
      case FlushbarPosition.TOP:
        {
          initialAlignment = new Alignment(-1.0, -2.0);
          endAlignment = new Alignment(-1.0, -1.0);
          barInsets = EdgeInsets.only(top: 24.0);
          _setBoxShadow();

          break;
        }
      case FlushbarPosition.BOTTOM:
        {
          initialAlignment = new Alignment(-1.0, 2.0);
          endAlignment = new Alignment(-1.0, 1.0);
          barInsets = EdgeInsets.only(top: 0.0);
          _setBoxShadow();

          break;
        }
    }

    _configureLeftBarFuture();
    _configurePopAnimation(initialAlignment, endAlignment);
    _configurePulseAnimation();
    _configureProgressIndicatorAnimation();

    _popController.forward();
    _fadeController.forward();
  }

  void _configureLeftBarFuture() {
    SchedulerBinding.instance.addPostFrameCallback(
      (_) {
        final keyContext = backgroundBoxKey.currentContext;

        if (keyContext != null) {
          final RenderBox box = keyContext.findRenderObject();
          _boxHeight = Future.value(box.size.height);
        }
      },
    );
  }

  Future<double> _boxHeight;

  void _configurePopAnimation(Alignment initialAlignment, Alignment endAlignment) {
    _popController = AnimationController(vsync: this, duration: Duration(seconds: 1));

    _popAnimation = AlignmentTween(begin: initialAlignment, end: endAlignment).animate(new CurvedAnimation(
        parent: _popController, curve: widget.forwardAnimationCurve, reverseCurve: widget.reverseAnimationCurve));

    _popAnimation.addStatusListener(_animationStatusListener);

    _popController.addListener(() {
      setState(() {});
    });
  }

  void _configurePulseAnimation() {
    _fadeController = AnimationController(vsync: this, duration: _duration);
    _fadeAnimation = new Tween(begin: _initialOpacity, end: _finalOpacity).animate(
      new CurvedAnimation(
        parent: _fadeController,
        curve: Curves.linear,
      ),
    );

    _fadeController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _fadeController.reverse();
      }
      if (status == AnimationStatus.dismissed) {
        _fadeController.forward();
      }
    });

    _fadeController.forward();
  }

  Function _progressListener;

  void _configureProgressIndicatorAnimation() {
    if (widget.showProgressIndicator && widget.progressIndicatorController != null) {
      _progressListener = () {
        setState(() {});
      };
      widget.progressIndicatorController.addListener(_progressListener);

      _progressAnimation = CurvedAnimation(curve: Curves.linear, parent: widget.progressIndicatorController);
    }
  }

  @override
  Widget build(BuildContext context) {
    return new Align(
      heightFactor: 1.0,
      child: new AlignTransition(
        alignment: _popAnimation,
        child: Material(
          child: SafeArea(
            minimum: widget.flushbarPosition == FlushbarPosition.BOTTOM
                ? EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom)
                : EdgeInsets.only(top: MediaQuery.of(context).viewInsets.top),
            bottom: widget.flushbarPosition == FlushbarPosition.BOTTOM,
            top: widget.flushbarPosition == FlushbarPosition.TOP,
            left: false,
            right: false,
            child: _getFlushbar(),
          ),
        ),
      ),
    );
  }

  void _setBoxShadow() {
    switch (widget.flushbarPosition) {
      case FlushbarPosition.TOP:
        {
          if (widget.shadowColor != null) {
            _boxShadow = BoxShadow(
              color: widget.shadowColor,
              offset: Offset(0.0, 2.0),
              blurRadius: 3.0,
            );
          }

          break;
        }
      case FlushbarPosition.BOTTOM:
        {
          if (widget.shadowColor != null) {
            _boxShadow = BoxShadow(
              color: widget.shadowColor,
              offset: Offset(0.0, -0.7),
              blurRadius: 3.0,
            );
          }

          break;
        }
    }
  }

  @override
  void dispose() {
    _popAnimation.removeStatusListener(_animationStatusListener);
    _popController.dispose();
    _fadeController.dispose();
    if (widget.progressIndicatorController != null) {
      widget.progressIndicatorController.removeListener(_progressListener);
      widget.progressIndicatorController.dispose();
    }
    focusNode.detach();
    super.dispose();
  }

  /// This string is a workaround until Dismissible supports a returning item
  String dismissibleKeyGen = "";

  Widget _getFlushbar() {
    if (widget.isDismissible) {
      return new Dismissible(
        key: Key(dismissibleKeyGen),
        onDismissed: (dismissDirection) {
          dismissibleKeyGen += "1";
          _resetAnimations();
        },
        child: (widget.userInputForm != null) ? _generateInputFlushbar() : _generateFlushbar(),
      );
    } else {
      return (widget.userInputForm != null) ? _generateInputFlushbar() : _generateFlushbar();
    }
  }

  FocusScopeNode focusNode = FocusScopeNode();

  Widget _generateInputFlushbar() {
    return new DecoratedBox(
      decoration: new BoxDecoration(
        color: widget.backgroundColor,
        gradient: widget.backgroundGradient,
        boxShadow: _getBoxShadowList(),
      ),
      child: new Padding(
        padding: barInsets,
        child: new Padding(
          padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 8.0, top: 8.0),
          child: FocusScope(
            child: widget.userInputForm,
            node: focusNode,
            autofocus: true,
          ),
        ),
      ),
    );
  }

  CurvedAnimation _progressAnimation;
  GlobalKey backgroundBoxKey = new GlobalKey();

  Widget _generateFlushbar() {
    return new DecoratedBox(
      key: backgroundBoxKey,
      decoration: new BoxDecoration(
        color: widget.backgroundColor,
        gradient: widget.backgroundGradient,
        boxShadow: _getBoxShadowList(),
      ),
      child: new Padding(
        padding: barInsets,
        child: new Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            widget.showProgressIndicator
                ? LinearProgressIndicator(
                    value: widget.progressIndicatorController != null ? _progressAnimation.value : null,
                    backgroundColor: widget.progressIndicatorBackgroundColor,
                    valueColor: widget.progressIndicatorValueColor,
                  )
                : _emptyWidget,
            new Row(mainAxisSize: MainAxisSize.max, children: _getRowLayout()),
          ],
        ),
      ),
    );
  }

  List<Widget> _getRowLayout() {
    if (widget.icon == null && widget.mainButton == null) {
      return [
        _buildLeftBarIndicator(),
        new Expanded(
          flex: 1,
          child: new Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              (_isTitlePresent)
                  ? new Padding(
                      padding: const EdgeInsets.only(top: 16.0, left: 16.0, right: 16.0),
                      child: _getTitleText(),
                    )
                  : _emptyWidget,
              new Padding(
                padding: EdgeInsets.only(top: _messageTopMargin, left: 16.0, right: 16.0, bottom: 16.0),
                child: widget.messageText ?? _getDefaultNotificationText(),
              ),
            ],
          ),
        ),
      ];
    } else if (widget.icon != null && widget.mainButton == null) {
      return <Widget>[
        _buildLeftBarIndicator(),
        new Expanded(
          flex: 1,
          child: _getIcon(),
        ),
        new Expanded(
          flex: 6,
          child: new Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              (_isTitlePresent)
                  ? new Padding(
                      padding: const EdgeInsets.only(top: 16.0, left: 4.0, right: 16.0),
                      child: _getTitleText(),
                    )
                  : _emptyWidget,
              new Padding(
                padding: EdgeInsets.only(top: _messageTopMargin, left: 4.0, right: 16.0, bottom: 16.0),
                child: widget.messageText ?? _getDefaultNotificationText(),
              ),
            ],
          ),
        ),
      ];
    } else if (widget.icon == null && widget.mainButton != null) {
      return <Widget>[
        _buildLeftBarIndicator(),
        new Expanded(
          flex: 7,
          child: new Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              (_isTitlePresent)
                  ? new Padding(
                      padding: const EdgeInsets.only(top: 16.0, left: 16.0, right: 16.0),
                      child: _getTitleText(),
                    )
                  : _emptyWidget,
              new Padding(
                padding: EdgeInsets.only(top: _messageTopMargin, left: 16.0, right: 16.0, bottom: 16.0),
                child: widget.messageText ?? _getDefaultNotificationText(),
              ),
            ],
          ),
        ),
        new Expanded(
          flex: 2,
          child: new Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: _getMainActionButton(),
          ),
        ),
      ];
    } else {
      return <Widget>[
        _buildLeftBarIndicator(),
        new Expanded(flex: 2, child: _getIcon()),
        new Expanded(
          flex: 8,
          child: new Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              (_isTitlePresent)
                  ? new Padding(
                      padding: const EdgeInsets.only(top: 16.0, left: 4.0, right: 8.0),
                      child: _getTitleText(),
                    )
                  : _emptyWidget,
              new Padding(
                padding: EdgeInsets.only(top: _messageTopMargin, left: 4.0, right: 8.0, bottom: 16.0),
                child: widget.messageText ?? _getDefaultNotificationText(),
              ),
            ],
          ),
        ),
        new Expanded(
          flex: 4,
          child: new Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: _getMainActionButton(),
              ) ??
              _emptyWidget,
        ),
      ];
    }
  }

  Widget _buildLeftBarIndicator() {
    if (widget.leftBarIndicatorColor != null) {
      return FutureBuilder(
        future: _boxHeight,
        builder: (BuildContext buildContext, AsyncSnapshot<double> snapshot) {
          if (snapshot.hasData) {
            return Container(
              color: widget.leftBarIndicatorColor,
              width: 5.0,
              height: snapshot.data,
            );
          } else {
            return _emptyWidget;
          }
        },
      );
    } else {
      return _emptyWidget;
    }
  }

  Widget _getIcon() {
    if (widget.icon != null) {
      return FadeTransition(
        opacity: _fadeAnimation,
        child: widget.icon,
      );
    } else {
      return _emptyWidget;
    }
  }

  Text _getTitleText() {
    return widget.titleText != null
        ? widget.titleText
        : new Text(
            widget.title ?? "",
            style: TextStyle(fontSize: 16.0, color: Colors.white, fontWeight: FontWeight.bold),
          );
  }

  Text _getDefaultNotificationText() {
    return new Text(
      widget.message ?? "",
      style: TextStyle(fontSize: 14.0, color: Colors.white),
    );
  }

  FlatButton _getMainActionButton() {
    if (widget.mainButton != null) {
      return widget.mainButton;
    } else {
      return null;
    }
  }
}

/// Indicates if flushbar is going to start at the [TOP] or at the [BOTTOM]
enum FlushbarPosition { TOP, BOTTOM }

/// Indicates the animation status
/// [FlushbarStatus.SHOWING] Flushbar has stopped and the user can see it
/// [FlushbarStatus.DISMISSED] Flushbar has finished its mission and returned any pending values
/// [FlushbarStatus.IS_APPEARING] Flushbar is moving towards [FlushbarStatus.SHOWING]
/// [FlushbarStatus.IS_HIDING] Flushbar is moving towards [] [FlushbarStatus.DISMISSED]
enum FlushbarStatus { SHOWING, DISMISSED, IS_APPEARING, IS_HIDING }