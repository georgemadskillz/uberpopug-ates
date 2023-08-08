%%%-------------------------------------------------------------------
%% @doc ates_auth public API
%% @end
%%%-------------------------------------------------------------------

-module(ates_auth_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    ates_auth_sup:start_link().

stop(_State) ->
    ok.

%% internal functions
