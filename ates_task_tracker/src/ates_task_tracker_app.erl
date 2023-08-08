%%%-------------------------------------------------------------------
%% @doc ates_task_tracker public API
%% @end
%%%-------------------------------------------------------------------

-module(ates_task_tracker_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    ates_task_tracker_sup:start_link().

stop(_State) ->
    ok.

%% internal functions
