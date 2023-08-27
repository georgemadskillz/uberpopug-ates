%%%-------------------------------------------------------------------
%% @doc ates_task_tracker top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(ates_task_tracker_sup).

-behaviour(supervisor).

-export([start_link/0]).

-export([init/1]).

-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%% sup_flags() = #{strategy => strategy(),         % optional
%%                 intensity => non_neg_integer(), % optional
%%                 period => pos_integer()}        % optional
%% child_spec() = #{id => child_id(),       % mandatory
%%                  start => mfargs(),      % mandatory
%%                  restart => restart(),   % optional
%%                  shutdown => shutdown(), % optional
%%                  type => worker(),       % optional
%%                  modules => modules()}   % optional
init([]) ->
    AtesTaskTrackerSpec = #{
        id => ates_task_tracker,
        start => {ates_task_tracker, start_link, []},
        restart => permanent,
        type => worker
    },
    SupFlags = #{strategy => one_for_all,
                 intensity => 3,
                 period => 5},
    ChildSpecs = [AtesTaskTrackerSpec],
    {ok, {SupFlags, ChildSpecs}}.


%% internal functions
