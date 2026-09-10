import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:msal_auth/msal_auth.dart';

import '../core/http/ado_exceptions.dart';
import 'auth_service.dart';

sealed class AuthEvent extends Equatable {
  const AuthEvent();
  @override
  List<Object?> get props => const [];
}

/// App start: look for a cached account.
class AuthStarted extends AuthEvent {
  const AuthStarted();
}

class AuthSignInRequested extends AuthEvent {
  const AuthSignInRequested({this.loginHint});
  final String? loginHint;
  @override
  List<Object?> get props => [loginHint];
}

class AuthSignOutRequested extends AuthEvent {
  const AuthSignOutRequested();
}

/// Raised by data code when a silent token fails; drops back to sign-in.
class AuthInteractionRequired extends AuthEvent {
  const AuthInteractionRequired(this.reason);
  final String reason;
  @override
  List<Object?> get props => [reason];
}

sealed class AuthState extends Equatable {
  const AuthState();
  @override
  List<Object?> get props => const [];
}

class AuthUnknown extends AuthState {
  const AuthUnknown();
}

class AuthBusy extends AuthState {
  const AuthBusy();
}

class AuthSignedOut extends AuthState {
  const AuthSignedOut({this.error});
  final String? error;
  @override
  List<Object?> get props => [error];
}

class AuthSignedIn extends AuthState {
  const AuthSignedIn(this.account);
  final Account account;
  @override
  List<Object?> get props => [account.id];
}

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc(this._auth) : super(const AuthUnknown()) {
    on<AuthStarted>(_onStarted);
    on<AuthSignInRequested>(_onSignIn);
    on<AuthSignOutRequested>(_onSignOut);
    on<AuthInteractionRequired>(_onInteractionRequired);
  }

  final AuthService _auth;

  Future<void> _onStarted(AuthStarted event, Emitter<AuthState> emit) async {
    if (!_auth.isConfigured) {
      emit(
        const AuthSignedOut(
          error:
              'BOARDHOP_CLIENT_ID is not set. '
              'Run with --dart-define-from-file=.env',
        ),
      );
      return;
    }
    final account = await _auth.currentAccount();
    emit(account == null ? const AuthSignedOut() : AuthSignedIn(account));
  }

  Future<void> _onSignIn(
    AuthSignInRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthBusy());
    try {
      final result = await _auth.signIn(loginHint: event.loginHint);
      emit(AuthSignedIn(result.account));
    } on AdoAuthException catch (e) {
      emit(AuthSignedOut(error: e.message));
    }
  }

  Future<void> _onSignOut(
    AuthSignOutRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthBusy());
    await _auth.signOut();
    emit(const AuthSignedOut());
  }

  Future<void> _onInteractionRequired(
    AuthInteractionRequired event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthSignedOut(error: event.reason));
  }
}
