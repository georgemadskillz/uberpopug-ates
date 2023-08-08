%%%-------------------------------------------------------------------
%% @doc ates_analitics public API
%% @end
%%%-------------------------------------------------------------------

-module(ates_analitics_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    ates_analitics_sup:start_link().

stop(_State) ->
    ok.

%% internal functions
