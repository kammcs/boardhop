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

/// App start: load the cached accounts.
class AuthStarted extends AuthEvent {
  const AuthStarted();
}

/// First sign-in, or "add another account" while signed in: the account
/// picker opens; choosing an account that is already signed in refreshes it.
class AuthSignInRequested extends AuthEvent {
  const AuthSignInRequested({this.loginHint});
  final String? loginHint;
  @override
  List<Object?> get props => [loginHint];
}

/// Sign one account out ([accountId]) or, with null, all of them.
class AuthSignOutRequested extends AuthEvent {
  const AuthSignOutRequested({this.accountId});
  final String? accountId;
  @override
  List<Object?> get props => [accountId];
}

/// Raised by data code when a silent token fails for an account: the user
/// is asked to sign that account in again; the others are unaffected.
class AuthInteractionRequired extends AuthEvent {
  const AuthInteractionRequired(this.reason, {this.accountId});
  final String reason;
  final String? accountId;
  @override
  List<Object?> get props => [reason, accountId];
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
  const AuthSignedIn(this.accounts, {this.error});

  /// At least one; sorted by username.
  final List<Account> accounts;

  /// The last add-account or re-sign-in failure, shown once.
  final String? error;

  @override
  List<Object?> get props => [for (final a in accounts) a.id, error];
}

/// Called after an account was removed from MSAL so its cached data can go.
typedef AccountRemovedCallback = Future<void> Function(String accountId);

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc(this._auth, {this._onAccountRemoved}) : super(const AuthUnknown()) {
    on<AuthStarted>(_onStarted);
    on<AuthSignInRequested>(_onSignIn);
    on<AuthSignOutRequested>(_onSignOut);
    on<AuthInteractionRequired>(_onInteractionRequired);
  }

  final AuthService _auth;
  final AccountRemovedCallback? _onAccountRemoved;

  AuthState _fromAccounts(List<Account> accounts, {String? error}) =>
      accounts.isEmpty
      ? AuthSignedOut(error: error)
      : AuthSignedIn(accounts, error: error);

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
    emit(_fromAccounts(await _auth.accounts()));
  }

  Future<void> _onSignIn(
    AuthSignInRequested event,
    Emitter<AuthState> emit,
  ) async {
    final before = _auth.knownAccounts;
    // Keep the org list on screen while the picker is up when accounts
    // already exist; the first sign-in shows the busy button instead.
    if (before.isEmpty) emit(const AuthBusy());
    try {
      await _auth.signIn(loginHint: event.loginHint);
      emit(_fromAccounts(await _auth.accounts()));
    } on AdoAuthException catch (e) {
      emit(_fromAccounts(await _auth.accounts(), error: e.message));
    }
  }

  Future<void> _onSignOut(
    AuthSignOutRequested event,
    Emitter<AuthState> emit,
  ) async {
    final id = event.accountId;
    final ids = id == null ? [for (final a in _auth.knownAccounts) a.id] : [id];
    if (id == null) emit(const AuthBusy());
    for (final accountId in ids) {
      await _auth.removeAccount(accountId);
      await _onAccountRemoved?.call(accountId);
    }
    emit(_fromAccounts(await _auth.accounts()));
  }

  Future<void> _onInteractionRequired(
    AuthInteractionRequired event,
    Emitter<AuthState> emit,
  ) async {
    final account = event.accountId == null
        ? null
        : _auth.accountById(event.accountId!);
    if (account == null && _auth.knownAccounts.isNotEmpty) {
      // Unknown account: report, keep the others signed in.
      emit(_fromAccounts(_auth.knownAccounts, error: event.reason));
      return;
    }
    try {
      await _auth.signIn(loginHint: account?.username);
      emit(_fromAccounts(await _auth.accounts()));
    } on AdoAuthException catch (e) {
      emit(
        _fromAccounts(
          await _auth.accounts(),
          error: '${event.reason} (${e.message})',
        ),
      );
    }
  }
}
