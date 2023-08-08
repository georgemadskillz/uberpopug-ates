%%%-------------------------------------------------------------------
%% @doc ates_accounter public API
%% @end
%%%-------------------------------------------------------------------

-module(ates_accounter_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    ates_accounter_sup:start_link().

stop(_State) ->
    ok.

%% internal functions
